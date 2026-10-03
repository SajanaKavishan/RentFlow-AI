import { useCallback, useContext, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { AuthContext } from '../../features/auth/useAuth.js'
import {
  completeWork,
  createRepairEstimate,
  getLatestEstimate,
  getTechnicianMaintenanceRequests,
  MaintenanceApiError,
  startWork,
  submitEstimateForReview,
} from '../../features/maintenance/services/maintenanceApiService.js'
import {
  MAINTENANCE_CATEGORY,
  MAINTENANCE_PRIORITY,
  MAINTENANCE_STATUS,
  maintenanceEnumLabel,
} from '../../features/maintenance/services/maintenanceEnums.js'
import { StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import './technician-assigned-work.css'

const statusToneMap = {
  Submitted: 'warning',
  Triaged: 'warning',
  Assigned: 'warning',
  EstimatePending: 'warning',
  AwaitingLandlordApproval: 'warning',
  Approved: 'success',
  InProgress: 'neutral',
  Completed: 'success',
  Rejected: 'danger',
  Cancelled: 'danger',
}

const DEFAULT_ESTIMATE_FORM = {
  laborCost: '',
  partsCost: '',
  additionalCost: '',
  notes: '',
}

function formatMoney(value) {
  const amount = Number(value)
  if (!Number.isFinite(amount)) return '—'
  return new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 2,
  }).format(amount)
}

export function AssignedWorkState({
  status,
  error = '',
  onRetry,
  requests = [],
  estimateState = 'idle',
  estimate = null,
  estimateForm = DEFAULT_ESTIMATE_FORM,
  estimatePending = false,
  onEstimateChange,
  onCreateEstimate,
  onSubmitEstimate,
}) {
  if (status === 'loading') {
    return <div className="assigned-work-state" role="status" aria-busy="true">
      <span className="shared-spinner" aria-hidden="true" />
      <h3>Loading assigned work</h3>
      <p>Please wait while the latest authorized work queue is loaded.</p>
    </div>
  }

  if (status === 'empty') {
    return <div className="assigned-work-state">
      <span className="assigned-work-state__icon"><Icon name="tools" size={28} /></span>
      <h3>No assigned work</h3>
      <p>Authorized maintenance assignments will appear here when work is allocated to your account.</p>
    </div>
  }

  if (status === 'error') {
    return <div className="assigned-work-state assigned-work-state--error" role="alert">
      <span className="assigned-work-state__icon"><Icon name="alert" size={28} /></span>
      <h3>Assigned work could not be loaded</h3>
      <p>{error || 'The assigned-work service is unavailable. Please try again.'}</p>
      {onRetry && <button className="shared-button" type="button" onClick={onRetry}>Try again</button>}
    </div>
  }

  if (status === 'ready') {
    return <div className="assigned-work-list" aria-live="polite">
      {requests.map((request) => (
        <article key={request.id} className="assigned-work-item shared-card">
          <div className="assigned-work-item__header">
            <div>
              <p className="assigned-work-page__eyebrow">Maintenance request</p>
              <h3>{request.title}</h3>
            </div>
            <StatusBadge tone={statusToneMap[request.status] ?? 'warning'}>{maintenanceEnumLabel(request.status, MAINTENANCE_STATUS)}</StatusBadge>
          </div>
          <p>{request.description}</p>
          <dl className="assigned-work-item__meta">
              <div><dt>Priority</dt><dd>{maintenanceEnumLabel(request.priority, MAINTENANCE_PRIORITY)}</dd></div>
              <div><dt>Category</dt><dd>{maintenanceEnumLabel(request.category, MAINTENANCE_CATEGORY)}</dd></div>
            <div><dt>Property</dt><dd>{request.propertyId}</dd></div>
          </dl>
          <div className="assigned-work-item__actions">
              <button type="button" className="shared-button shared-button--outline" onClick={request.onToggleDetails} aria-expanded={request.selected}>
                {request.selected ? 'Hide details' : 'View details'}
              </button>
              {request.status === 'Approved' && (
                <button type="button" className="shared-button" onClick={request.onStart} disabled={request.actionPending}>
                  {request.actionPending ? 'Starting...' : 'Start work'}
                </button>
              )}
              {request.status === 'InProgress' && (
                <button type="button" className="shared-button" onClick={request.onComplete} disabled={request.actionPending}>
                  {request.actionPending ? 'Completing...' : 'Complete work'}
                </button>
              )}
          </div>
          {request.selected && (
            <>
              <dl className="assigned-work-item__details">
                <div><dt>Request ID</dt><dd>{request.id}</dd></div>
                <div><dt>Tenant</dt><dd>{request.tenantId || 'Not provided'}</dd></div>
                <div><dt>Access notes</dt><dd>{request.tenantAccessNotes || 'None provided'}</dd></div>
                <div><dt>Assignment notes</dt><dd>{request.assignmentNotes || 'None provided'}</dd></div>
              </dl>
              <section className="assigned-work-item__estimate" aria-label="Repair estimate">
                <h4>Repair estimate</h4>
                {estimateState === 'loading' && <p role="status">Loading estimate…</p>}
                {estimateState === 'error' && <p role="alert">Unable to load the latest estimate.</p>}
                {estimate && (
                  <dl className="assigned-work-item__details">
                    <div><dt>Status</dt><dd>{maintenanceEnumLabel(estimate.status, { byValue: { 0: 'Draft', 1: 'Submitted', 2: 'RevisionRequested', 3: 'Approved', 4: 'Rejected', 5: 'Superseded' } })}</dd></div>
                    <div><dt>Total</dt><dd>{formatMoney(estimate.totalCost)}</dd></div>
                    <div><dt>Labor</dt><dd>{formatMoney(estimate.laborCost)}</dd></div>
                    <div><dt>Parts</dt><dd>{formatMoney(estimate.partsCost)}</dd></div>
                    <div><dt>Additional</dt><dd>{formatMoney(estimate.additionalCost)}</dd></div>
                    {estimate.notes && <div><dt>Notes</dt><dd>{estimate.notes}</dd></div>}
                  </dl>
                )}
                {request.status === 'EstimatePending' && (
                  <form className="assigned-work-estimate-form" onSubmit={onCreateEstimate}>
                    <label>
                      Labor cost
                      <input type="number" name="laborCost" min="0" step="0.01" value={estimateForm.laborCost} onChange={onEstimateChange} required />
                    </label>
                    <label>
                      Parts cost
                      <input type="number" name="partsCost" min="0" step="0.01" value={estimateForm.partsCost} onChange={onEstimateChange} required />
                    </label>
                    <label>
                      Additional cost
                      <input type="number" name="additionalCost" min="0" step="0.01" value={estimateForm.additionalCost} onChange={onEstimateChange} required />
                    </label>
                    <label>
                      Estimate notes
                      <textarea name="notes" value={estimateForm.notes} onChange={onEstimateChange} rows={3} />
                    </label>
                    <button type="submit" className="shared-button" disabled={estimatePending}>
                      {estimatePending ? 'Submitting…' : 'Create estimate'}
                    </button>
                  </form>
                )}
                {request.status === 'EstimateSubmitted' && estimate?.id && (
                  <button type="button" className="shared-button" onClick={onSubmitEstimate} disabled={estimatePending}>
                    {estimatePending ? 'Sending…' : 'Submit estimate for review'}
                  </button>
                )}
              </section>
            </>
          )}
        </article>
      ))}
    </div>
  }

  return <div className="assigned-work-state assigned-work-state--integration" role="status">
    <span className="assigned-work-state__icon"><Icon name="tools" size={30} /></span>
    <StatusBadge tone="warning">Integration pending</StatusBadge>
    <h3>Work queue integration required</h3>
    <p>The Maintenance API does not currently provide an authenticated collection of work assigned to the signed-in Technician.</p>
    <p>No maintenance records or totals are shown until that authorized contract is available.</p>
  </div>
}

export default function TechnicianAssignedWorkPage() {
  const { user } = useContext(AuthContext) || {}
  const userId = user?.id
  const [status, setStatus] = useState('loading')
  const [requests, setRequests] = useState([])
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [pendingRequestId, setPendingRequestId] = useState(null)
  const [selectedRequestId, setSelectedRequestId] = useState(null)
  const [selectedEstimate, setSelectedEstimate] = useState(null)
  const [estimateState, setEstimateState] = useState('idle')
  const [estimatePending, setEstimatePending] = useState(false)
  const [estimateForm, setEstimateForm] = useState(DEFAULT_ESTIMATE_FORM)

  const loadAssignedWork = useCallback(async () => {
    if (!userId) {
      setStatus('error')
      setError('Your authenticated technician account could not be identified.')
      setRequests([])
      return false
    }

    setStatus('loading')
    setError('')
    setNotice('')

    try {
      const items = await getTechnicianMaintenanceRequests(userId)
      setRequests(items)
      setSelectedRequestId((current) =>
        items.some((item) => item.id === current) ? current : null,
      )
      setStatus(items.length ? 'ready' : 'empty')
      return true
    } catch (err) {
      setStatus('error')
      setError(err.message || 'Unable to load the technician work queue.')
      return false
    }
  }, [userId])

  useEffect(() => {
    const loadTimer = window.setTimeout(() => {
      void loadAssignedWork()
    }, 0)

    return () => window.clearTimeout(loadTimer)
  }, [loadAssignedWork])

  const handleWorkAction = async (request, action) => {
    if (pendingRequestId) return
    setPendingRequestId(request.id)
    setError('')
    setNotice('')

    try {
      if (action === 'start') {
        await startWork(request.id)
      } else {
        await completeWork(request.id)
      }
      const refreshed = await loadAssignedWork()
      if (refreshed) {
        setNotice(action === 'start' ? 'Work started.' : 'Work completed.')
      }
    } catch (err) {
      setError(err.message || 'Unable to update this maintenance request.')
    } finally {
      setPendingRequestId(null)
    }
  }

  const handleToggleDetails = async (request) => {
    if (selectedRequestId === request.id) {
      setSelectedRequestId(null)
      setSelectedEstimate(null)
      setEstimateState('idle')
      return
    }
    setSelectedRequestId(request.id)
    setSelectedEstimate(null)
    setEstimateForm(DEFAULT_ESTIMATE_FORM)
    setEstimateState('loading')
    try {
      const estimate = await getLatestEstimate(request.id)
      setSelectedEstimate(estimate ?? null)
      setEstimateState(estimate ? 'success' : 'empty')
    } catch (error) {
      if (error instanceof MaintenanceApiError && error.statusCode === 404) {
        setSelectedEstimate(null)
        setEstimateState('empty')
      } else {
        setSelectedEstimate(null)
        setEstimateState('error')
      }
    }
  }

  const handleEstimateChange = (event) => {
    const { name, value } = event.target
    setEstimateForm((current) => ({ ...current, [name]: value }))
  }

  const handleCreateEstimate = async (event) => {
    event.preventDefault()
    const request = requests.find((item) => item.id === selectedRequestId)
    if (!request || estimatePending) return
    const costs = ['laborCost', 'partsCost', 'additionalCost'].map((key) => Number(estimateForm[key]))
    if (costs.some((cost) => !Number.isFinite(cost) || cost < 0)) {
      setError('Enter valid, non-negative costs for all estimate fields.')
      return
    }
    setEstimatePending(true)
    setError('')
    setNotice('')
    try {
      const estimate = await createRepairEstimate(request.id, estimateForm)
      setSelectedEstimate(estimate)
      setEstimateState('success')
      const refreshed = await loadAssignedWork()
      if (refreshed) setNotice('Estimate created. Submit it for landlord review when ready.')
    } catch (actionError) {
      setError(actionError.message || 'Unable to create the repair estimate.')
    } finally {
      setEstimatePending(false)
    }
  }

  const handleSubmitEstimate = async () => {
    const request = requests.find((item) => item.id === selectedRequestId)
    if (!request || !selectedEstimate?.id || estimatePending) return
    setEstimatePending(true)
    setError('')
    setNotice('')
    try {
      await submitEstimateForReview(request.id, selectedEstimate.id)
      const refreshed = await loadAssignedWork()
      if (refreshed) setNotice('Estimate submitted for landlord review.')
    } catch (actionError) {
      setError(actionError.message || 'Unable to submit the estimate for review.')
    } finally {
      setEstimatePending(false)
    }
  }

  const actionableRequests = requests.map((request) => ({
    ...request,
    actionPending: pendingRequestId === request.id,
    selected: selectedRequestId === request.id,
    onToggleDetails: () => handleToggleDetails(request),
    onStart: () => handleWorkAction(request, 'start'),
    onComplete: () => handleWorkAction(request, 'complete'),
  }))

  return <main className="shared-page assigned-work-page">
    <header className="assigned-work-page__header">
      <div>
        <p className="assigned-work-page__eyebrow">Technician workspace</p>
        <h1>Assigned Work</h1>
        <p>Review assigned maintenance requests and update work as it progresses.</p>
      </div>
      <div className="assigned-work-page__header-actions" aria-label="Assigned Work navigation">
        <Link className="shared-button shared-button--outline" to="/dashboard"><Icon name="home" size={18} />Back to dashboard</Link>
        <Link className="shared-button" to="/notifications" aria-label="Open notification inbox"><Icon name="bell" size={18} />Notifications</Link>
      </div>
    </header>

    <div className="assigned-work-page__layout">
      <section className="shared-card assigned-work-area" aria-labelledby="assigned-work-queue-title">
        <div className="assigned-work-area__heading">
          <div><p className="assigned-work-page__eyebrow">Work area</p><h2 id="assigned-work-queue-title">Your work queue</h2></div>
          <span className="assigned-work-area__scope"><Icon name="user" size={17} />Authenticated Technician scope</span>
        </div>
        <div className="assigned-work-area__controls">
          <button className="shared-button shared-button--outline" type="button" onClick={loadAssignedWork} disabled={status === 'loading'}>
            {status === 'loading' ? 'Refreshing...' : 'Refresh queue'}
          </button>
        </div>
        {notice && <p role="status" className="assigned-work-page__notice">{notice}</p>}
        {error && status !== 'error' && <p role="alert">{error}</p>}
        <AssignedWorkState
          status={status}
          error={error}
          onRetry={loadAssignedWork}
          requests={actionableRequests}
          estimateState={estimateState}
          estimate={selectedEstimate}
          estimateForm={estimateForm}
          estimatePending={estimatePending}
          onEstimateChange={handleEstimateChange}
          onCreateEstimate={handleCreateEstimate}
          onSubmitEstimate={handleSubmitEstimate}
        />
      </section>

      <aside className="assigned-work-page__side" aria-label="Assigned Work integration details">
        <section className="shared-card assigned-work-availability" aria-labelledby="assigned-work-availability-title">
          <div className="assigned-work-availability__heading"><span className="assigned-work-state__icon assigned-work-state__icon--small"><Icon name="info" size={21} /></span><div><p className="assigned-work-page__eyebrow">Availability</p><h2 id="assigned-work-availability-title">Workflow status</h2></div></div>
          <dl>
            <div><dt>Assigned-work list</dt><dd><StatusBadge tone={status === 'ready' ? 'success' : 'info'}>{status === 'ready' ? 'Connected' : 'Live contract'}</StatusBadge></dd></div>
            <div><dt>Record details</dt><dd>{status === 'ready' ? 'Available for the current technician queue' : status === 'empty' ? 'No requests are currently assigned' : 'Loaded when assigned work is available'}</dd></div>
            <div><dt>Work actions</dt><dd>Start and complete actions are enabled only for requests in the matching backend status.</dd></div>
          </dl>
        </section>

        <section className="shared-card assigned-work-tools" aria-labelledby="assigned-work-tools-title">
          <div><p className="assigned-work-page__eyebrow">Shared tools</p><h2 id="assigned-work-tools-title">Account access</h2></div>
          <Link to="/notifications" aria-label="Open notifications from Assigned Work"><span className="assigned-work-state__icon assigned-work-state__icon--small"><Icon name="bell" size={20} /></span><span><strong>Notifications</strong><small>Review updates for your account</small></span><Icon name="arrow" size={17} /></Link>
          <Link to="/profile"><span className="assigned-work-state__icon assigned-work-state__icon--small"><Icon name="user" size={20} /></span><span><strong>Profile</strong><small>View account details and sign out</small></span><Icon name="arrow" size={17} /></Link>
        </section>
      </aside>
    </div>
  </main>
}
