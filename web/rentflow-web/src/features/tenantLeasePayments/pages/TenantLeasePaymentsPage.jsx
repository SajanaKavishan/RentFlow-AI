import { useEffect, useRef, useState } from 'react'
import { ApiError } from '../../../core/api/apiClient.js'
import { AppCard, PageHeader, StatusBadge } from '../../../shared/ui/States.jsx'
import {
  createPayment, getLease, getMyLeases, getMyOffers, getMyPayments,
  getOffer, getPayment, getScheduleByLease, getScheduleItem, respondToOffer,
} from '../services/tenantLeasePaymentsApi.js'
import '../tenantLeasePayments.css'

const tabs = ['Rental Offers', 'My Leases', 'Rent Schedule', 'Payments']
const offerStatuses = ['Pending', 'Accepted', 'Rejected', 'Withdrawn', 'Expired']
const leaseStatuses = ['Pending', 'Active', 'Terminated', 'Completed']
const scheduleStatuses = ['Pending', 'Paid', 'Overdue']
const paymentStatuses = ['Pending', 'Completed', 'Failed']
const empty = '—'

function safeError(error, fallback) {
  if (!(error instanceof ApiError)) return fallback
  if (error.statusCode === 401) return 'Your session has expired. Please sign in again.'
  if (error.statusCode === 403) return 'You do not have permission to access this resource.'
  if (error.statusCode === 404) return 'The requested item could not be found. Refresh and try again.'
  if (error.statusCode === 409) return 'This action is no longer available. Refresh and try again.'
  if (error.statusCode === 400) return error.message
  return fallback
}

function money(value) {
  return value == null || !Number.isFinite(Number(value)) ? empty
    : new Intl.NumberFormat(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(value)
}

function dateTime(value) {
  if (!value) return empty
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? empty : date.toLocaleString()
}

function Facts({ rows }) {
  return <dl className="tenant-lease-facts">{rows.map(([label, value]) =>
    <div key={label}><dt>{label}</dt><dd>{value ?? empty}</dd></div>)}</dl>
}

function useCollection(loader, fallback) {
  const [state, setState] = useState({ status: 'loading', items: [], error: '' })
  const [reload, setReload] = useState(0)
  useEffect(() => {
    let active = true
    loader().then((items) => {
      if (active) setState({ status: 'ready', items, error: '' })
    }).catch((error) => {
      if (active) setState({ status: 'error', items: [], error: safeError(error, fallback) })
    })
    return () => { active = false }
  }, [loader, fallback, reload])
  function refresh() {
    setState((current) => ({ ...current, status: 'loading' }))
    setReload((value) => value + 1)
  }
  return { ...state, refresh }
}

function CollectionState({ collection, loading, emptyMessage }) {
  if (collection.status === 'loading') return <p role="status">{loading}</p>
  if (collection.status === 'error') return <div role="alert"><p>{collection.error}</p><button className="shared-button shared-button--outline" type="button" onClick={collection.refresh}>Try again</button></div>
  if (collection.items.length === 0) return <p>{emptyMessage}</p>
  return null
}

export default function TenantLeasePaymentsPage() {
  const [tab, setTab] = useState(tabs[0])
  const offers = useCollection(getMyOffers, 'Unable to load your rental offers.')
  const leases = useCollection(getMyLeases, 'Unable to load your leases.')
  const payments = useCollection(getMyPayments, 'Unable to load your payments.')
  const [leaseId, setLeaseId] = useState('')
  const [scheduleState, setScheduleState] = useState({ leaseId: '', status: 'idle', items: [], error: '' })
  const [scheduleReload, setScheduleReload] = useState(0)
  const [detail, setDetail] = useState({ kind: '', status: 'idle', item: null, error: '' })
  const detailRequest = useRef(0)
  const actionInFlight = useRef(false)
  const [action, setAction] = useState('')
  const [actionError, setActionError] = useState('')
  const [notice, setNotice] = useState('')
  const [selectedItemId, setSelectedItemId] = useState('')
  const [paymentMethod, setPaymentMethod] = useState('')
  const [transactionReference, setTransactionReference] = useState('')

  useEffect(() => {
    if (!leaseId) return undefined
    let active = true
    getScheduleByLease(leaseId).then((items) => {
      if (active) setScheduleState({ leaseId, status: 'ready', items, error: '' })
    }).catch((error) => {
      if (active) setScheduleState({ leaseId, status: 'error', items: [], error: safeError(error, 'Unable to load the rent schedule.') })
    })
    return () => { active = false }
  }, [leaseId, scheduleReload])

  const schedule = leaseId && scheduleState.leaseId === leaseId
    ? scheduleState : { leaseId, status: leaseId ? 'loading' : 'idle', items: [], error: '' }
  const eligibleItems = schedule.items.filter((item) => item.status === 0 || item.status === 2)
  const selectedItem = eligibleItems.find((item) => item.id === selectedItemId)

  function refreshSchedule() {
    if (!leaseId) return
    setScheduleState({ leaseId, status: 'loading', items: [], error: '' })
    setScheduleReload((value) => value + 1)
  }

  function switchTab(next) {
    ++detailRequest.current
    setTab(next)
    setDetail({ kind: '', status: 'idle', item: null, error: '' })
    setActionError('')
    setNotice('')
  }

  async function openDetail(kind, id, loader) {
    const request = ++detailRequest.current
    setDetail({ kind, status: 'loading', item: null, error: '' })
    setActionError('')
    try {
      const item = await loader(id)
      if (request === detailRequest.current) setDetail({ kind, status: 'ready', item, error: '' })
    } catch (error) {
      if (request === detailRequest.current) setDetail({ kind, status: 'error', item: null, error: safeError(error, 'Unable to load details.') })
    }
  }

  async function actOnOffer(id, verb) {
    if (actionInFlight.current) return
    actionInFlight.current = true
    setAction(verb)
    setActionError('')
    setNotice('')
    try {
      const updated = await respondToOffer(id, verb)
      setDetail((current) => current.kind === 'offer' && current.item?.id === id
        ? { kind: 'offer', status: 'ready', item: updated, error: '' } : current)
      setNotice(`Rental offer ${verb === 'accept' ? 'accepted' : 'rejected'}. A lease is created later by the landlord.`)
      offers.refresh()
    } catch (error) {
      setActionError(safeError(error, 'Unable to update the rental offer.'))
    } finally {
      actionInFlight.current = false
      setAction('')
    }
  }

  async function submitPayment(event) {
    event.preventDefault()
    if (actionInFlight.current) return
    if (!selectedItem || !paymentMethod.trim()) {
      setActionError('Select an unpaid schedule item and enter a payment method.')
      return
    }
    if (paymentMethod.trim().length > 100 || transactionReference.trim().length > 200) {
      setActionError('Payment method must be at most 100 characters and transaction reference at most 200 characters.')
      return
    }
    actionInFlight.current = true
    setAction('payment')
    setActionError('')
    setNotice('')
    try {
      const created = await createPayment({
        rentScheduleItemId: selectedItem.id,
        paymentMethod: paymentMethod.trim(),
        transactionReference: transactionReference.trim() || null,
      })
      ++detailRequest.current
      setDetail({ kind: 'payment', status: 'ready', item: created, error: '' })
      setNotice('Payment created as Pending. The landlord will update its status later.')
      setPaymentMethod('')
      setTransactionReference('')
      payments.refresh()
      refreshSchedule()
    } catch (error) {
      setActionError(safeError(error, 'Unable to create the payment.'))
    } finally {
      actionInFlight.current = false
      setAction('')
    }
  }

  const detailFor = (kind) => detail.kind === kind && detail.status !== 'idle'

  return <main className="shared-page tenant-lease-page">
    <PageHeader eyebrow="Your rental journey" title="My Lease & Payments"><p>Review offers, lease terms, rent schedules and payment activity in one place.</p></PageHeader>
    <nav className="tenant-lease-tabs" aria-label="Lease and payment sections">
      {tabs.map((name) => <button key={name} type="button" className={tab === name ? 'tenant-lease-tabs__active' : ''} aria-current={tab === name ? 'page' : undefined} onClick={() => switchTab(name)}>{name}</button>)}
    </nav>
    {notice && <p className="shared-notice" role="status">{notice}</p>}

    {tab === 'Rental Offers' && <section aria-label="Rental Offers"><AppCard>
      <div className="tenant-lease-heading"><h2>Rental Offers</h2></div>
      <CollectionState collection={offers} loading="Loading rental offers…" emptyMessage="No rental offers yet." />
      {offers.status === 'ready' && offers.items.length > 0 && <ul className="tenant-lease-list">{offers.items.map((offer) => <li key={offer.id}><div><strong>Property {offer.propertyId}</strong><span>{offerStatuses[offer.status] ?? 'Unknown'} · Monthly rent {money(offer.monthlyRent)}</span><small>Expires {dateTime(offer.expiresAt)}</small></div><button type="button" className="shared-button shared-button--outline" onClick={() => openDetail('offer', offer.id, getOffer)}>View details</button></li>)}</ul>}
    </AppCard>
      {detailFor('offer') && <AppCard className="tenant-lease-detail">
        {detail.status === 'loading' && <p role="status">Loading offer details…</p>}
        {detail.status === 'error' && <p role="alert">{detail.error}</p>}
        {detail.status === 'ready' && <><div className="tenant-lease-heading"><h2>Offer details</h2><StatusBadge tone={detail.item.status === 1 ? 'success' : 'neutral'}>{offerStatuses[detail.item.status] ?? 'Unknown'}</StatusBadge></div>
          <Facts rows={[
            ['Property ID', detail.item.propertyId], ['Application ID', detail.item.rentalApplicationId],
            ['Monthly rent', money(detail.item.monthlyRent)], ['Security deposit', money(detail.item.securityDeposit)],
            ['Proposed start', detail.item.proposedStartDate], ['Proposed end', detail.item.proposedEndDate],
            ['Expires', dateTime(detail.item.expiresAt)], ['Landlord note', detail.item.landlordNote],
            ['Created', dateTime(detail.item.createdAt)], ['Updated', dateTime(detail.item.updatedAt)],
          ]} />
          {detail.item.status === 0 && <div className="tenant-lease-actions"><button className="shared-button" type="button" disabled={Boolean(action)} onClick={() => actOnOffer(detail.item.id, 'accept')}>{action === 'accept' ? 'Accepting…' : 'Accept offer'}</button><button className="shared-button shared-button--outline" type="button" disabled={Boolean(action)} onClick={() => actOnOffer(detail.item.id, 'reject')}>{action === 'reject' ? 'Rejecting…' : 'Reject offer'}</button></div>}
          {actionError && <p className="shared-notice shared-notice--error" role="alert">{actionError}</p>}
        </>}
      </AppCard>}
    </section>}

    {tab === 'My Leases' && <section aria-label="My Leases"><AppCard>
      <div className="tenant-lease-heading"><h2>My Leases</h2></div>
      <CollectionState collection={leases} loading="Loading leases…" emptyMessage="No leases yet. An accepted offer becomes a lease when the landlord creates one." />
      {leases.status === 'ready' && leases.items.length > 0 && <ul className="tenant-lease-list">{leases.items.map((lease) => <li key={lease.id}><div><strong>Property {lease.propertyId}</strong><span>{leaseStatuses[lease.status] ?? 'Unknown'} · Monthly rent {money(lease.monthlyRent)}</span><small>{lease.startDate} to {lease.endDate}</small></div><button type="button" className="shared-button shared-button--outline" onClick={() => openDetail('lease', lease.id, getLease)}>View details</button></li>)}</ul>}
    </AppCard>
      {detailFor('lease') && <AppCard className="tenant-lease-detail">
        {detail.status === 'loading' && <p role="status">Loading lease details…</p>}
        {detail.status === 'error' && <p role="alert">{detail.error}</p>}
        {detail.status === 'ready' && <><div className="tenant-lease-heading"><h2>Lease details</h2><StatusBadge tone={detail.item.status === 1 ? 'success' : 'neutral'}>{leaseStatuses[detail.item.status] ?? 'Unknown'}</StatusBadge></div><Facts rows={[
          ['Property ID', detail.item.propertyId], ['Rental offer ID', detail.item.rentalOfferId],
          ['Monthly rent', money(detail.item.monthlyRent)], ['Security deposit', money(detail.item.securityDeposit)],
          ['Start date', detail.item.startDate], ['End date', detail.item.endDate],
          ['Created', dateTime(detail.item.createdAt)], ['Updated', dateTime(detail.item.updatedAt)],
        ]} /></>}
      </AppCard>}
    </section>}

    {(tab === 'Rent Schedule' || tab === 'Payments') && <AppCard className="tenant-lease-selector">
      <label htmlFor="tenant-lease-select">Lease</label>
      {leases.status === 'loading' && <p role="status">Loading leases…</p>}
      {leases.status === 'error' && <p role="alert">{leases.error} <button type="button" className="shared-button shared-button--outline" onClick={leases.refresh}>Try again</button></p>}
      {leases.status === 'ready' && leases.items.length === 0 && <p>No leases available. Your schedule will appear after the landlord creates a lease and generates its schedule.</p>}
      {leases.status === 'ready' && leases.items.length > 0 && <select id="tenant-lease-select" value={leaseId} onChange={(event) => { const id = event.target.value; setLeaseId(id); setScheduleState({ leaseId: id, status: id ? 'loading' : 'idle', items: [], error: '' }); setSelectedItemId(''); ++detailRequest.current; setDetail({ kind: '', status: 'idle', item: null, error: '' }) }}><option value="">Select a lease</option>{leases.items.map((lease) => <option key={lease.id} value={lease.id}>Property {lease.propertyId} · {leaseStatuses[lease.status] ?? 'Unknown'} · {lease.startDate}</option>)}</select>}
    </AppCard>}

    {tab === 'Rent Schedule' && <section aria-label="Rent Schedule"><AppCard>
      <div className="tenant-lease-heading"><h2>Rent Schedule</h2></div>
      {!leaseId && <p>Select a lease to view its rent schedule.</p>}
      {leaseId && schedule.status === 'loading' && <p role="status">Loading rent schedule…</p>}
      {leaseId && schedule.status === 'error' && <div role="alert"><p>{schedule.error}</p><button className="shared-button shared-button--outline" type="button" onClick={refreshSchedule}>Try again</button></div>}
      {leaseId && schedule.status === 'ready' && (schedule.items.length === 0 ? <p>No rent schedule has been generated for this lease yet.</p> : <ul className="tenant-lease-list">{schedule.items.map((item) => <li key={item.id}><div><strong>Due {item.dueDate}</strong><span>{scheduleStatuses[item.status] ?? 'Unknown'} · {money(item.amount)}</span></div><button type="button" className="shared-button shared-button--outline" onClick={() => openDetail('schedule', item.id, getScheduleItem)}>View details</button></li>)}</ul>)}
    </AppCard>
      {detailFor('schedule') && <AppCard className="tenant-lease-detail">
        {detail.status === 'loading' && <p role="status">Loading schedule item…</p>}
        {detail.status === 'error' && <p role="alert">{detail.error}</p>}
        {detail.status === 'ready' && <><h2>Schedule item details</h2><Facts rows={[
          ['Lease ID', detail.item.leaseAgreementId], ['Due date', detail.item.dueDate],
          ['Amount', money(detail.item.amount)], ['Status', scheduleStatuses[detail.item.status] ?? 'Unknown'],
          ['Created', dateTime(detail.item.createdAt)], ['Updated', dateTime(detail.item.updatedAt)],
        ]} /></>}
      </AppCard>}
    </section>}

    {tab === 'Payments' && <section aria-label="Payments">
      <AppCard><div className="tenant-lease-heading"><h2>Payments</h2></div>
        <CollectionState collection={payments} loading="Loading payments…" emptyMessage="No payments yet." />
        {payments.status === 'ready' && payments.items.length > 0 && <ul className="tenant-lease-list">{payments.items.map((payment) => <li key={payment.id}><div><strong>{money(payment.amount)} · {paymentStatuses[payment.status] ?? 'Unknown'}</strong><span>{payment.paymentMethod}</span><small>Created {dateTime(payment.createdAt)}</small></div><button type="button" className="shared-button shared-button--outline" onClick={() => openDetail('payment', payment.id, getPayment)}>View details</button></li>)}</ul>}
      </AppCard>
      <AppCard><h2>Create payment</h2>
        {!leaseId && <p>Select a lease above to choose a rent schedule item.</p>}
        {leaseId && schedule.status === 'loading' && <p role="status">Loading eligible schedule items…</p>}
        {leaseId && schedule.status === 'error' && <p role="alert">{schedule.error}</p>}
        {leaseId && schedule.status === 'ready' && eligibleItems.length === 0 && <p>No unpaid schedule items for this lease. The landlord may need to generate a schedule.</p>}
        {leaseId && schedule.status === 'ready' && eligibleItems.length > 0 && <form className="tenant-lease-form" onSubmit={submitPayment} noValidate>
          <label>Rent schedule item<select value={selectedItemId} disabled={Boolean(action)} onChange={(event) => { setSelectedItemId(event.target.value); setActionError('') }}><option value="">Select a due item</option>{eligibleItems.map((item) => <option key={item.id} value={item.id}>{item.dueDate} · {money(item.amount)} · {scheduleStatuses[item.status]}</option>)}</select></label>
          {selectedItem && <p>Due {selectedItem.dueDate} · {money(selectedItem.amount)} · {scheduleStatuses[selectedItem.status]}. The backend sets the payment amount.</p>}
          <label>Payment method<input value={paymentMethod} maxLength={100} disabled={Boolean(action)} onChange={(event) => setPaymentMethod(event.target.value)} /></label>
          <label>Transaction reference (optional)<input value={transactionReference} maxLength={200} disabled={Boolean(action)} onChange={(event) => setTransactionReference(event.target.value)} /></label>
          {actionError && <p className="shared-notice shared-notice--error" role="alert">{actionError}</p>}
          <button type="submit" className="shared-button" disabled={Boolean(action)}>{action === 'payment' ? 'Creating…' : 'Create payment'}</button>
        </form>}
      </AppCard>
      {detailFor('payment') && <AppCard className="tenant-lease-detail">
        {detail.status === 'loading' && <p role="status">Loading payment details…</p>}
        {detail.status === 'error' && <p role="alert">{detail.error}</p>}
        {detail.status === 'ready' && <><div className="tenant-lease-heading"><h2>Payment details</h2><StatusBadge tone={detail.item.status === 1 ? 'success' : 'neutral'}>{paymentStatuses[detail.item.status] ?? 'Unknown'}</StatusBadge></div><Facts rows={[
          ['Schedule item ID', detail.item.rentScheduleItemId], ['Amount', money(detail.item.amount)],
          ['Payment method', detail.item.paymentMethod], ['Transaction reference', detail.item.transactionReference],
          ['Paid at', dateTime(detail.item.paidAt)], ['Created', dateTime(detail.item.createdAt)],
          ['Updated', dateTime(detail.item.updatedAt)],
        ]} /></>}
      </AppCard>}
    </section>}
  </main>
}
