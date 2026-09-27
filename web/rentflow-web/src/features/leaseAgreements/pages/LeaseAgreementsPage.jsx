import { useEffect, useRef, useState } from 'react'
import { ApiError } from '../../../core/api/apiClient.js'
import { getMyProperties } from '../../properties/services/propertyApiService.js'
import { getLandlordOffers } from '../../rentalOffers/services/rentalOfferApiService.js'
import PricingLeaseNavigation from '../../rentalOffers/PricingLeaseNavigation.jsx'
import { AppCard, PageHeader, StatusBadge } from '../../../shared/ui/States.jsx'
import { changeLeaseStatus, createLeaseAgreement, getLandlordLeases, getLeaseAgreement } from '../services/leaseAgreementApiService.js'
import '../leaseAgreements.css'

const statuses = ['Pending', 'Active', 'Terminated', 'Completed']

function safeError(error, fallback) {
  if (!(error instanceof ApiError)) return fallback
  if (error.statusCode === 401) return 'Your session has expired. Please sign in again.'
  if (error.statusCode === 403) return 'You do not have permission to access this resource.'
  if (error.statusCode === 404) return 'This lease agreement or rental offer could not be found.'
  if (error.statusCode === 409) return 'The lease state has changed or a lease already exists for this offer. Refresh and try again.'
  if (error.statusCode === 400) return error.message
  return fallback
}

function dateTime(value) {
  if (!value) return '—'
  const parsed = new Date(value)
  return Number.isNaN(parsed.getTime()) ? '—' : parsed.toLocaleString()
}

function dateOnly(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(`${value}T00:00:00Z`)) ? value : '—'
}

function number(value) {
  return value == null || !Number.isFinite(Number(value)) ? '—' : new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(value)
}

function LeaseDetails({ lease, propertyName, acting, onAction }) {
  return <AppCard className="lease-details">
    <div className="lease-heading"><h2>Lease details</h2><StatusBadge tone={lease.status === 1 ? 'success' : lease.status === 0 ? 'progress' : 'neutral'}>{statuses[lease.status] ?? 'Unknown'}</StatusBadge></div>
    <dl className="lease-facts">
      <div><dt>Lease ID</dt><dd>{lease.id}</dd></div>
      <div><dt>Rental offer</dt><dd>{lease.rentalOfferId}</dd></div>
      <div><dt>Property</dt><dd>{propertyName || lease.propertyId}</dd></div>
      <div><dt>Tenant</dt><dd>{lease.tenantId}</dd></div>
      <div><dt>Monthly rent</dt><dd>{number(lease.monthlyRent)}</dd></div>
      <div><dt>Security deposit</dt><dd>{number(lease.securityDeposit)}</dd></div>
      <div><dt>Start date</dt><dd>{dateOnly(lease.startDate)}</dd></div>
      <div><dt>End date</dt><dd>{dateOnly(lease.endDate)}</dd></div>
      <div><dt>Created</dt><dd>{dateTime(lease.createdAt)}</dd></div>
      <div><dt>Updated</dt><dd>{dateTime(lease.updatedAt)}</dd></div>
    </dl>
    {lease.status === 0 && <button className="shared-button" type="button" disabled={Boolean(acting)} onClick={() => onAction('activate')}>{acting === 'activate' ? 'Activating…' : 'Activate lease'}</button>}
    {lease.status === 1 && <div className="lease-actions"><button className="shared-button shared-button--outline shared-button--danger" type="button" disabled={Boolean(acting)} onClick={() => onAction('terminate')}>{acting === 'terminate' ? 'Terminating…' : 'Terminate lease'}</button><button className="shared-button" type="button" disabled={Boolean(acting)} onClick={() => onAction('complete')}>{acting === 'complete' ? 'Completing…' : 'Complete lease'}</button></div>}
  </AppCard>
}

export default function LeaseAgreementsPage() {
  const [leasesState, setLeasesState] = useState({ status: 'loading', items: [], error: '' })
  const [offersState, setOffersState] = useState({ status: 'loading', items: [], error: '' })
  const [properties, setProperties] = useState([])
  const [leaseReload, setLeaseReload] = useState(0)
  const [offerReload, setOfferReload] = useState(0)
  const [rentalOfferId, setRentalOfferId] = useState('')
  const [formError, setFormError] = useState('')
  const [notice, setNotice] = useState('')
  const [creating, setCreating] = useState(false)
  const [acting, setActing] = useState('')
  const [detailState, setDetailState] = useState({ status: 'idle', lease: null, error: '' })
  const detailRequest = useRef(0)

  useEffect(() => {
    let active = true
    getLandlordLeases().then((items) => {
      if (active) setLeasesState({ status: 'ready', items, error: '' })
    }).catch((error) => {
      if (active) setLeasesState({ status: 'error', items: [], error: safeError(error, 'Unable to load lease agreements.') })
    })
    return () => { active = false }
  }, [leaseReload])

  useEffect(() => {
    let active = true
    getLandlordOffers().then((items) => {
      if (active) setOffersState({ status: 'ready', items, error: '' })
    }).catch((error) => {
      if (active) setOffersState({ status: 'error', items: [], error: safeError(error, 'Unable to load rental offers.') })
    })
    return () => { active = false }
  }, [offerReload])

  useEffect(() => {
    let active = true
    getMyProperties().then((items) => { if (active) setProperties(items) }).catch(() => {})
    return () => { active = false }
  }, [])

  function refreshLeases() {
    setLeasesState((current) => ({ ...current, status: 'loading' }))
    setLeaseReload((value) => value + 1)
  }

  function refreshOffers() {
    setOffersState((current) => ({ ...current, status: 'loading' }))
    setOfferReload((value) => value + 1)
  }

  async function openLease(id) {
    const request = ++detailRequest.current
    setDetailState({ status: 'loading', lease: null, error: '' })
    try {
      const lease = await getLeaseAgreement(id)
      if (request === detailRequest.current) setDetailState({ status: 'ready', lease, error: '' })
    } catch (error) {
      if (request === detailRequest.current) setDetailState({ status: 'error', lease: null, error: safeError(error, 'Unable to load the lease agreement.') })
    }
  }

  async function create(event) {
    event.preventDefault()
    if (creating) return
    if (!rentalOfferId || !eligibleOffers.some((offer) => offer.id === rentalOfferId)) {
      setFormError('Select an accepted rental offer without a lease.')
      return
    }
    setCreating(true)
    setFormError('')
    setNotice('')
    try {
      const lease = await createLeaseAgreement(rentalOfferId)
      ++detailRequest.current
      setDetailState({ status: 'ready', lease, error: '' })
      setRentalOfferId('')
      setNotice('Lease agreement created successfully.')
      refreshLeases()
    } catch (error) {
      setFormError(safeError(error, 'Unable to create the lease agreement.'))
    } finally {
      setCreating(false)
    }
  }

  async function changeStatus(action) {
    if (acting || detailState.status !== 'ready') return
    const lease = detailState.lease
    if (lease.status !== 0 && lease.status !== 1) return
    if (lease.status === 0 && action !== 'activate') return
    if (lease.status === 1 && !['terminate', 'complete'].includes(action)) return
    setActing(action)
    setNotice('')
    setDetailState((current) => ({ ...current, error: '' }))
    try {
      const updated = await changeLeaseStatus(lease.id, action)
      setDetailState((current) => current.lease?.id === lease.id ? { status: 'ready', lease: updated, error: '' } : current)
      setNotice(`Lease agreement ${action === 'activate' ? 'activated' : action === 'terminate' ? 'terminated' : 'completed'}.`)
      refreshLeases()
    } catch (error) {
      setDetailState((current) => ({ ...current, error: safeError(error, 'Unable to update the lease agreement.') }))
    } finally {
      setActing('')
    }
  }

  const propertyName = (id) => properties.find((property) => property.id === id)?.title
  const eligibleOffers = offersState.status === 'ready' && leasesState.status === 'ready'
    ? offersState.items.filter((offer) => offer.status === 1 && !leasesState.items.some((lease) => lease.rentalOfferId === offer.id))
    : []

  return <main className="shared-page lease-page">
    <PageHeader eyebrow="Pricing / Lease" title="Lease Agreements"><p>Create leases from accepted rental offers and manage their status.</p></PageHeader>
    <PricingLeaseNavigation />
    {notice && <p className="shared-notice" role="status">{notice}</p>}
    <div className="lease-layout">
      <section aria-label="Lease agreement list"><AppCard>
        <div className="lease-heading"><h2>Your leases</h2><button className="shared-button shared-button--outline" type="button" onClick={refreshLeases} disabled={leasesState.status === 'loading'}>Refresh</button></div>
        {leasesState.status === 'loading' && <p role="status">Loading lease agreements…</p>}
        {leasesState.status === 'error' && <div role="alert"><p>{leasesState.error}</p><button className="shared-button shared-button--outline" type="button" onClick={refreshLeases}>Try again</button></div>}
        {leasesState.status === 'ready' && (leasesState.items.length === 0 ? <p>No lease agreements yet.</p> : <ul className="lease-list">{leasesState.items.map((lease) => <li key={lease.id}><div><strong>{propertyName(lease.propertyId) || lease.propertyId}</strong><span>{statuses[lease.status] ?? 'Unknown'} · Monthly rent {number(lease.monthlyRent)}</span><small>Created {dateTime(lease.createdAt)}</small></div><button className="shared-button shared-button--outline" type="button" onClick={() => openLease(lease.id)} disabled={creating || Boolean(acting) || detailState.status === 'loading'}>View details</button></li>)}</ul>)}
      </AppCard></section>
      <section aria-label="Create lease agreement"><AppCard><h2>Create lease agreement</h2>
        {offersState.status === 'loading' && <p role="status">Loading accepted rental offers…</p>}
        {offersState.status === 'error' && <div role="alert"><p>{offersState.error}</p><button className="shared-button shared-button--outline" type="button" onClick={refreshOffers}>Try again</button></div>}
        {offersState.status === 'ready' && leasesState.status === 'ready' && (eligibleOffers.length === 0 ? <p>No accepted rental offers without a lease are available.</p> : <form className="lease-form" onSubmit={create} noValidate><label>Accepted rental offer<select value={rentalOfferId} disabled={creating} onChange={(event) => { setRentalOfferId(event.target.value); setFormError('') }}><option value="">Select an offer</option>{eligibleOffers.map((offer) => <option key={offer.id} value={offer.id}>{propertyName(offer.propertyId) || offer.propertyId} · Tenant {offer.tenantId} · Rent {number(offer.monthlyRent)} · {dateOnly(offer.proposedStartDate)} to {dateOnly(offer.proposedEndDate)}</option>)}</select></label>{formError && <p className="shared-notice shared-notice--error" role="alert">{formError}</p>}<button className="shared-button" type="submit" disabled={creating}>{creating ? 'Creating…' : 'Create lease'}</button></form>)}
      </AppCard></section>
    </div>
    <section className="lease-selected" aria-label="Selected lease agreement">
      {detailState.status === 'loading' && <AppCard><p role="status">Loading lease details…</p></AppCard>}
      {detailState.status === 'error' && <AppCard><p className="shared-notice shared-notice--error" role="alert">{detailState.error}</p></AppCard>}
      {detailState.status === 'ready' && <><LeaseDetails lease={detailState.lease} propertyName={propertyName(detailState.lease.propertyId)} acting={acting} onAction={changeStatus} />{detailState.error && <p className="shared-notice shared-notice--error" role="alert">{detailState.error}</p>}</>}
    </section>
  </main>
}
