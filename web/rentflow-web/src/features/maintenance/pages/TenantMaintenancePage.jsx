import { useCallback, useEffect, useRef, useState } from 'react'
import { useAuth } from '../../auth/useAuth.js'
import {
  getMaintenanceAttachmentDownload, getMaintenanceAttachments, getMaintenanceHistory,
  getMaintenanceRequestById, getTenantMaintenanceRequests, getLatestEstimate, MaintenanceApiError,
} from '../services/maintenanceApiService.js'
import { MAINTENANCE_CATEGORY, MAINTENANCE_PRIORITY, MAINTENANCE_STATUS, maintenanceEnumLabel } from '../services/maintenanceEnums.js'
import Icon from '../../../shared/ui/Icons.jsx'
import MaintenancePhoto from '../components/MaintenancePhoto.jsx'
import '../maintenance.css'

const reference = (request) => request.referenceCode?.trim() || 'Reference unavailable'
const propertyName = (request) => request.propertyTitle?.trim() || 'Property unavailable'
const accessLabel = (value) => ({ Morning: 'Morning 8-12', Afternoon: 'Afternoon 12-5', Evening: 'Evening 5-8' }[value] || 'Not provided')
const statusLabel = (value) => value === 'AwaitingLandlordApproval' || value === 5 ? 'Awaiting Approval' : maintenanceEnumLabel(value, MAINTENANCE_STATUS)
const estimateStatuses = ['Draft', 'Submitted', 'Revision requested', 'Approved', 'Rejected', 'Superseded']
const stages = ['Submitted', 'Triaged', 'Assigned', 'EstimatePending', 'EstimateSubmitted', 'AwaitingLandlordApproval', 'Approved', 'InProgress', 'Completed']
const decodeStatus = (value) => MAINTENANCE_STATUS.byValue[value] ?? value
const safeError = (error, fallback) => error instanceof MaintenanceApiError ? error.message : fallback
const date = (value) => value && Number.isFinite(Date.parse(value))
  ? new Date(value).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' }) : 'Not available'

function Progress({ request, history }) {
  const current = decodeStatus(request.status)
  const reached = new Set(history.flatMap((entry) => [entry.fromStatus, entry.toStatus])
    .filter((status) => status != null).map(decodeStatus))
  const visibleStages = stages.includes(current) ? stages : [...stages, current]
  return <section className="maintenance-detail__section" aria-label="Request progress">
    <h4>Current stage: {statusLabel(request.status)}</h4>
    <ol className="maintenance-progress">{visibleStages.map((stage, index) => <li key={stage}
      className={stage === current ? 'maintenance-progress__current' : reached.has(stage) ? 'maintenance-progress__reached' : ''}
      aria-current={stage === current ? 'step' : undefined}>
      <span className="maintenance-progress__marker" aria-hidden="true">{reached.has(stage) ? '\u2713' : index + 1}</span>
      <span>{statusLabel(stage)}</span>
      <small>{stage === current ? 'Current' : reached.has(stage) ? 'Recorded' : 'Not recorded'}</small>
    </li>)}</ol>
  </section>
}

function TenantMaintenanceCard({ summary, tenantId }) {
  const selectedId = summary.id
  const [detail, setDetail] = useState({ status: 'idle', item: null, error: '' })
  const [resources, setResources] = useState({ status: 'idle', attachments: [], history: [], estimate: null, errors: [] })
  const [downloadError, setDownloadError] = useState('')
  const detailVersion = useRef(0)

  const selectRequest = useCallback(async (id) => {
    const version = ++detailVersion.current
    setDetail({ status: 'loading', item: null, error: '' })
    setResources({ status: 'loading', attachments: [], history: [], estimate: null, errors: [] })
    setDownloadError('')
    try {
      const item = await getMaintenanceRequestById(id)
      if (version !== detailVersion.current) return
      setDetail({ status: 'ready', item, error: '' })
      const results = await Promise.allSettled([
        getMaintenanceAttachments(id, tenantId), getMaintenanceHistory(id), getLatestEstimate(id),
      ])
      if (version !== detailVersion.current) return
      const fallbacks = ['Unable to load photos.', 'Unable to load status history.', 'Unable to load the latest estimate.']
      setResources({ status: 'ready',
        attachments: results[0].status === 'fulfilled' ? results[0].value : [],
        history: results[1].status === 'fulfilled' ? results[1].value : [],
        estimate: results[2].status === 'fulfilled' ? results[2].value : null,
        errors: results.flatMap((result, index) => result.status === 'rejected'
          ? [safeError(result.reason, fallbacks[index])] : []),
      })
    } catch (error) {
      if (version !== detailVersion.current) return
      setDetail({ status: 'error', item: null, error: safeError(error, 'Unable to load request details.') })
      setResources({ status: 'idle', attachments: [], history: [], estimate: null, errors: [] })
    }
  }, [tenantId])

  useEffect(() => {
    const versionRef = detailVersion
    const timer = window.setTimeout(() => { void selectRequest(summary.id) }, 0)
    return () => { window.clearTimeout(timer); ++versionRef.current }
  }, [summary.id, selectRequest])

  async function openAttachment(attachment) {
    const version = detailVersion.current
    const requestId = selectedId
    const downloadWindow = window.open('', '_blank')
    if (!downloadWindow) { setDownloadError('Allow pop-ups to open the attachment.'); return }
    downloadWindow.opener = null
    try {
      const response = await getMaintenanceAttachmentDownload(requestId, attachment.id, tenantId)
      const objectUrl = URL.createObjectURL(await response.blob())
      downloadWindow.location.replace(objectUrl)
      window.setTimeout(() => URL.revokeObjectURL(objectUrl), 60_000)
    } catch (error) {
      downloadWindow.close()
      if (version === detailVersion.current) setDownloadError(safeError(error, 'Unable to open the photo.'))
    }
  }

  const request = detail.item || summary
  const estimate = resources.estimate
  return <article className="tenant-maintenance-card" aria-label={reference(summary)}>
    <div className="tenant-maintenance-card__heading">
      <span className="tenant-maintenance-card__icon" aria-hidden="true"><Icon name="tools" size={24} /></span>
      <div className="tenant-maintenance-card__identity">
        <h3>{request.title || reference(request)}</h3>
        <p>{propertyName(request)} <span className="tenant-maintenance-card__reference">{reference(request)}</span></p>
        <div className="tenant-maintenance-card__tags">
          <span>{maintenanceEnumLabel(request.category, MAINTENANCE_CATEGORY)}</span>
          <span>{maintenanceEnumLabel(request.priority, MAINTENANCE_PRIORITY)}</span>
        </div>
      </div>
      <span className={`status-badge tenant-maintenance-status tenant-maintenance-status--${decodeStatus(request.status)}`}>{statusLabel(request.status)}</span>
    </div>
    {request.description && <p className="tenant-maintenance-card__description">{request.description}</p>}
    <dl className="tenant-maintenance-card__facts">
      <div><dt>Created</dt><dd>{date(request.createdAt)}</dd></div>
      {request.assignedTechnicianName && <div><dt>Assigned technician</dt><dd>{request.assignedTechnicianName}</dd></div>}
      {request.assignedTechnicianContactPhone && <div><dt>Technician work contact</dt><dd>{request.assignedTechnicianContactPhone}</dd></div>}
    </dl>
    <Progress request={request} history={resources.history} />
    {resources.errors.map((error, index) => <p role="alert" key={index}>{error}</p>)}
        {detail.status === 'loading' && <p role="status">Loading request details...</p>}
        {detail.status === 'error' && <div role="alert"><p>{detail.error}</p><button type="button" className="button button--quiet" onClick={() => selectRequest(selectedId)}>Try again</button></div>}
        {detail.status === 'ready' && request && <details className="maintenance-detail"><summary>Request summary</summary>
          <dl className="maintenance-detail__meta">
            {[
              ['Property', propertyName(request)], ['Reference', reference(request)], ['Current status', statusLabel(request.status)],
              ['Category', maintenanceEnumLabel(request.category, MAINTENANCE_CATEGORY)], ['Priority', maintenanceEnumLabel(request.priority, MAINTENANCE_PRIORITY)],
              ['Preferred access', accessLabel(request.preferredAccessWindow)], ['Created', date(request.createdAt)],
            ].map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}
          </dl>
          <section className="maintenance-detail__section"><h4>Description</h4><p>{request.description || 'No description provided.'}</p></section>
          {resources.status === 'loading' && <p role="status">Loading photos, history and estimate...</p>}
          <section className="maintenance-detail__section" aria-label="Status history"><h4>Status history</h4>
            {resources.status === 'ready' && resources.history.length === 0 && <p>No status history available.</p>}
            <ol>{resources.history.map((entry) => <li key={entry.id}>{statusLabel(entry.toStatus)} <time dateTime={entry.changedAt}>{date(entry.changedAt)}</time></li>)}</ol>
          </section>
          <section className="maintenance-detail__section" aria-label="Request attachments"><h4>Photos and attachments</h4>
            {resources.status === 'ready' && resources.attachments.length === 0 && <p>No attachments have been added to this request.</p>}
            <ul className="maintenance-attachment-list">{resources.attachments.map((attachment) => <li key={attachment.id}>
              <div><MaintenancePhoto requestId={request.id} tenantId={tenantId} attachment={attachment} /><strong>{attachment.fileName}</strong></div>
              <button type="button" className="button button--quiet" onClick={() => openAttachment(attachment)}>Open</button>
            </li>)}</ul>
            {downloadError && <p role="alert">{downloadError}</p>}
          </section>
          {estimate && <section className="maintenance-detail__section" aria-label="Latest estimate"><h4>Latest estimate</h4>
            <dl className="maintenance-detail__meta">
              <div><dt>Status</dt><dd>{estimateStatuses[estimate.status] ?? estimate.status ?? 'Unknown'}</dd></div>
              <div><dt>Version</dt><dd>{estimate.versionNumber}</dd></div>
              <div><dt>Total cost</dt><dd>{estimate.totalCost != null && Number.isFinite(Number(estimate.totalCost)) ? new Intl.NumberFormat(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(estimate.totalCost) : 'Not available'}</dd></div>
              <div><dt>Created</dt><dd>{date(estimate.createdAt)}</dd></div>
            </dl>
          </section>}
        </details>}
  </article>
}

const FILTERS = [
  ['all', 'All requests'], ['open', 'Open'], ['InProgress', 'In Progress'],
  ['Completed', 'Completed'],
]

export default function TenantMaintenancePage() {
  const { user } = useAuth()
  const tenantId = user?.id
  const [attempt, setAttempt] = useState(0)
  const [filter, setFilter] = useState('all')
  const [list, setList] = useState({ status: 'loading', items: [], error: '' })
  useEffect(() => {
    let active = true
    const timer = window.setTimeout(() => {
      setList({ status: 'loading', items: [], error: '' })
      if (!tenantId) { setList({ status: 'error', items: [], error: 'Please sign in to view your maintenance requests.' }); return }
      getTenantMaintenanceRequests(tenantId).then((items) => {
        if (active) setList({ status: 'ready', items: [...items].sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt)), error: '' })
      }).catch((error) => {
        if (active) setList({ status: 'error', items: [], error: safeError(error, 'Unable to load your maintenance requests.') })
      })
    }, 0)
    return () => { active = false; window.clearTimeout(timer) }
  }, [tenantId, attempt])

  const visible = list.items.filter((item) => {
    const status = decodeStatus(item.status)
    return filter === 'all' || (filter === 'open'
      ? !['Completed', 'Cancelled', 'Rejected'].includes(status) : status === filter)
  })

  return <main className="maintenance-page maintenance-page--tenant" aria-busy={list.status === 'loading'}>
    <header className="maintenance-page__header"><div>
      <h1>Maintenance requests</h1>
      <p>Track issues in your home and review the latest status on each request.</p>
      <p className="maintenance-mobile-note">Use the RentFlow mobile app to submit a new maintenance request.</p>
    </div></header>
    {list.status === 'loading' && <p role="status">Loading maintenance requests...</p>}
    {list.status === 'error' && <div className="page-state page-state--error" role="alert"><p>{list.error}</p>
      <button type="button" className="button button--primary" onClick={() => setAttempt((value) => value + 1)}>Try again</button></div>}
    {list.status === 'ready' && <section className="tenant-maintenance-tracking" aria-labelledby="maintenance-list-title">
      <h2 id="maintenance-list-title">Your requests</h2>
      <div className="tenant-maintenance-filters">
        <div className="tenant-maintenance-filters__statuses" role="group" aria-label="Filter by status">
          {FILTERS.map(([value, label]) => <button type="button" key={value} aria-pressed={filter === value}
            onClick={() => setFilter(value)}>{label}</button>)}
        </div>
        <span role="status">{visible.length} {visible.length === 1 ? 'request' : 'requests'}</span>
      </div>
      {list.items.length === 0 ? <p>No maintenance requests yet.</p> : visible.length === 0
        ? <div className="page-state"><p>No requests match these filters.</p><button type="button" className="button button--quiet"
          onClick={() => setFilter('all')}>Clear filters</button></div>
        : <div className="tenant-maintenance-cards">{visible.map((item) => <TenantMaintenanceCard key={item.id} summary={item} tenantId={tenantId} />)}</div>}
    </section>}
  </main>
}
