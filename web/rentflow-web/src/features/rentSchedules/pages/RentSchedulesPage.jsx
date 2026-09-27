import { useEffect, useRef, useState } from 'react'
import { ApiError } from '../../../core/api/apiClient.js'
import { getLandlordLeases } from '../../leaseAgreements/services/leaseAgreementApiService.js'
import PricingLeaseNavigation from '../../rentalOffers/PricingLeaseNavigation.jsx'
import { AppCard, PageHeader, StatusBadge } from '../../../shared/ui/States.jsx'
import { generateRentSchedule, getRentScheduleByLease, getRentScheduleItem } from '../services/rentScheduleApiService.js'
import '../rentSchedules.css'

const leaseStatuses = ['Pending', 'Active', 'Terminated', 'Completed']
const scheduleStatuses = ['Pending', 'Paid', 'Overdue']
const missing = '—'

function safeError(error, fallback) {
  if (!(error instanceof ApiError)) return fallback
  if (error.statusCode === 401) return 'Your session has expired. Please sign in again.'
  if (error.statusCode === 403) return 'You do not have permission to access this resource.'
  if (error.statusCode === 404) return 'The lease agreement or rent schedule item could not be found.'
  if (error.statusCode === 409) return 'The lease is no longer eligible or a rent schedule already exists. Refresh and try again.'
  if (error.statusCode === 400) return error.message
  return fallback
}

function dateOnly(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return missing
  const parsed = new Date(`${value}T00:00:00Z`)
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value ? value : missing
}

function dateTime(value) {
  if (!value) return missing
  const parsed = new Date(value)
  return Number.isNaN(parsed.getTime()) ? missing : parsed.toLocaleString()
}

function amount(value) {
  return value == null || !Number.isFinite(Number(value))
    ? missing
    : new Intl.NumberFormat(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(value)
}

function statusLabel(value, labels) { return labels[value] ?? 'Unknown' }

function ScheduleItemDetails({ item }) {
  return <AppCard className="rent-schedule-details">
    <h2>Schedule item details</h2>
    <dl className="rent-schedule-facts">
      <div><dt>Schedule item ID</dt><dd>{item.id}</dd></div>
      <div><dt>Lease ID</dt><dd>{item.leaseAgreementId}</dd></div>
      <div><dt>Due date</dt><dd>{dateOnly(item.dueDate)}</dd></div>
      <div><dt>Rent amount</dt><dd>{amount(item.amount)}</dd></div>
      <div><dt>Status</dt><dd>{statusLabel(item.status, scheduleStatuses)}</dd></div>
      <div><dt>Created</dt><dd>{dateTime(item.createdAt)}</dd></div>
      <div><dt>Updated</dt><dd>{dateTime(item.updatedAt)}</dd></div>
    </dl>
  </AppCard>
}

export default function RentSchedulesPage() {
  const [leasesState, setLeasesState] = useState({ status: 'loading', items: [], error: '' })
  const [leasesReload, setLeasesReload] = useState(0)
  const [selectedLeaseId, setSelectedLeaseId] = useState('')
  const [scheduleState, setScheduleState] = useState({ status: 'idle', items: [], error: '' })
  const [scheduleReload, setScheduleReload] = useState(0)
  const [detailState, setDetailState] = useState({ status: 'idle', item: null, error: '' })
  const [generating, setGenerating] = useState(false)
  const [actionError, setActionError] = useState('')
  const [notice, setNotice] = useState('')
  const detailRequest = useRef(0)

  useEffect(() => {
    let active = true
    getLandlordLeases().then((items) => {
      if (active) setLeasesState({ status: 'ready', items, error: '' })
    }).catch((error) => {
      if (active) setLeasesState({ status: 'error', items: [], error: safeError(error, 'Unable to load lease agreements.') })
    })
    return () => { active = false }
  }, [leasesReload])

  useEffect(() => {
    if (!selectedLeaseId) return
    let active = true
    getRentScheduleByLease(selectedLeaseId).then((items) => {
      if (active) setScheduleState({ status: 'ready', items, error: '' })
    }).catch((error) => {
      if (active) setScheduleState({ status: 'error', items: [], error: safeError(error, 'Unable to load the rent schedule.') })
    })
    return () => { active = false }
  }, [selectedLeaseId, scheduleReload])

  const selectedLease = leasesState.items.find((lease) => lease.id === selectedLeaseId)

  function refreshLeases() {
    setLeasesState((current) => ({ ...current, status: 'loading' }))
    setLeasesReload((value) => value + 1)
  }

  function selectLease(id) {
    ++detailRequest.current
    setSelectedLeaseId(id)
    setScheduleState({ status: id ? 'loading' : 'idle', items: [], error: '' })
    setDetailState({ status: 'idle', item: null, error: '' })
    setActionError('')
    setNotice('')
  }

  function refreshSchedule() {
    ++detailRequest.current
    setDetailState({ status: 'idle', item: null, error: '' })
    setScheduleState({ status: 'loading', items: [], error: '' })
    setScheduleReload((value) => value + 1)
  }

  async function openItem(id) {
    const request = ++detailRequest.current
    setDetailState({ status: 'loading', item: null, error: '' })
    try {
      const item = await getRentScheduleItem(id)
      if (request === detailRequest.current) setDetailState({ status: 'ready', item, error: '' })
    } catch (error) {
      if (request === detailRequest.current) setDetailState({ status: 'error', item: null, error: safeError(error, 'Unable to load the rent schedule item.') })
    }
  }

  async function generate() {
    if (generating || !selectedLease || selectedLease.status !== 1 || scheduleState.status !== 'ready' || scheduleState.items.length) {
      setActionError('Select an active lease without a rent schedule.')
      return
    }
    const leaseId = selectedLease.id
    setGenerating(true)
    setActionError('')
    setNotice('')
    try {
      const items = await generateRentSchedule(leaseId)
      if (leaseId === selectedLeaseId) {
        setScheduleState({ status: 'ready', items, error: '' })
        setNotice('Rent schedule generated successfully.')
      }
    } catch (error) {
      if (leaseId === selectedLeaseId) setActionError(safeError(error, 'Unable to generate the rent schedule.'))
    } finally {
      setGenerating(false)
    }
  }

  return <main className="shared-page rent-schedules-page">
    <PageHeader eyebrow="Pricing / Lease" title="Rent Schedules"><p>View scheduled rent for your leases and generate a schedule for an active lease.</p></PageHeader>
    <PricingLeaseNavigation />
    {notice && <p className="shared-notice" role="status">{notice}</p>}
    <AppCard>
      <div className="rent-schedule-heading"><h2>Select a lease</h2><button className="shared-button shared-button--outline" type="button" onClick={refreshLeases} disabled={leasesState.status === 'loading' || generating}>Refresh leases</button></div>
      {leasesState.status === 'loading' && <p role="status">Loading lease agreements…</p>}
      {leasesState.status === 'error' && <div role="alert"><p>{leasesState.error}</p><button className="shared-button shared-button--outline" type="button" onClick={refreshLeases}>Try again</button></div>}
      {leasesState.status === 'ready' && (leasesState.items.length === 0 ? <p>No lease agreements yet.</p> : <label className="rent-schedule-selector">Lease agreement
        <select value={selectedLeaseId} disabled={generating} onChange={(event) => selectLease(event.target.value)}>
          <option value="">Select a lease</option>
          {leasesState.items.map((lease) => <option key={lease.id} value={lease.id}>{lease.propertyId} · Tenant {lease.tenantId} · {statusLabel(lease.status, leaseStatuses)} · {dateOnly(lease.startDate)} to {dateOnly(lease.endDate)}</option>)}
        </select>
      </label>)}
    </AppCard>
    {leasesState.status === 'ready' && leasesState.items.length > 0 && !selectedLease && <AppCard><p>Select a lease to view its rent schedule.</p></AppCard>}
    {selectedLease && <>
      <AppCard>
        <h2>Selected lease</h2>
        <dl className="rent-schedule-facts">
          <div><dt>Lease ID</dt><dd>{selectedLease.id}</dd></div>
          <div><dt>Property ID</dt><dd>{selectedLease.propertyId}</dd></div>
          <div><dt>Tenant ID</dt><dd>{selectedLease.tenantId}</dd></div>
          <div><dt>Status</dt><dd>{statusLabel(selectedLease.status, leaseStatuses)}</dd></div>
          <div><dt>Monthly rent</dt><dd>{amount(selectedLease.monthlyRent)}</dd></div>
          <div><dt>Lease dates</dt><dd>{dateOnly(selectedLease.startDate)} to {dateOnly(selectedLease.endDate)}</dd></div>
        </dl>
      </AppCard>
      <AppCard>
        <div className="rent-schedule-heading"><h2>Rent schedule</h2><button className="shared-button shared-button--outline" type="button" disabled={scheduleState.status === 'loading' || generating} onClick={refreshSchedule}>Refresh schedule</button></div>
        {scheduleState.status === 'loading' && <p role="status">Loading rent schedule…</p>}
        {scheduleState.status === 'error' && <div role="alert"><p>{scheduleState.error}</p><button className="shared-button shared-button--outline" type="button" onClick={refreshSchedule}>Try again</button></div>}
        {scheduleState.status === 'ready' && (scheduleState.items.length === 0 ? <>
          <p>No rent schedule has been generated for this lease.</p>
          {selectedLease.status === 1 ? <button className="shared-button" type="button" disabled={generating} onClick={generate}>{generating ? 'Generating…' : 'Generate rent schedule'}</button> : <p>Only an active lease can have a schedule generated.</p>}
        </> : <div className="rent-schedule-table-wrap"><table className="rent-schedule-table"><thead><tr><th scope="col">Due date</th><th scope="col">Rent amount</th><th scope="col">Status</th><th scope="col">Details</th></tr></thead><tbody>{scheduleState.items.map((item) => <tr key={item.id}><td>{dateOnly(item.dueDate)}</td><td>{amount(item.amount)}</td><td><StatusBadge tone={item.status === 1 ? 'success' : item.status === 2 ? 'warning' : 'progress'}>{statusLabel(item.status, scheduleStatuses)}</StatusBadge></td><td><button className="shared-button shared-button--outline" type="button" disabled={detailState.status === 'loading'} onClick={() => openItem(item.id)}>View details</button></td></tr>)}</tbody></table></div>)}
        {actionError && <p className="shared-notice shared-notice--error" role="alert">{actionError}</p>}
      </AppCard>
      {detailState.status === 'loading' && <AppCard><p role="status">Loading schedule item details…</p></AppCard>}
      {detailState.status === 'error' && <AppCard><p role="alert">{detailState.error}</p></AppCard>}
      {detailState.status === 'ready' && <ScheduleItemDetails item={detailState.item} />}
    </>}
  </main>
}
