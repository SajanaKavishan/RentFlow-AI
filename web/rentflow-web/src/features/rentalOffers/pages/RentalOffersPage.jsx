import { useEffect, useRef, useState } from 'react'
import { ApiError } from '../../../core/api/apiClient.js'
import { getMyProperties } from '../../properties/services/propertyApiService.js'
import { getApplicationsByProperty, RENTAL_APPLICATION_STATUS } from '../../rentalApplications/services/rentalApplicationApiService.js'
import { AppCard, PageHeader, StatusBadge } from '../../../shared/ui/States.jsx'
import PricingLeaseNavigation from '../PricingLeaseNavigation.jsx'
import { createRentalOffer, getLandlordOffers, getRentalOffer, withdrawRentalOffer } from '../services/rentalOfferApiService.js'
import '../rentalOffers.css'

const statuses = ['Pending', 'Accepted', 'Rejected', 'Withdrawn', 'Expired']
const blankForm = { rentalApplicationId: '', monthlyRent: '', securityDeposit: '', proposedStartDate: '', proposedEndDate: '', expiresAt: '', landlordNote: '' }

function safeError(error, fallback) {
  if (!(error instanceof ApiError)) return fallback
  if (error.statusCode === 401) return 'Your session has expired. Please sign in again.'
  if (error.statusCode === 403) return 'You do not have permission to access this resource.'
  if (error.statusCode === 404) return 'This rental offer or application could not be found.'
  if (error.statusCode === 409) return 'The offer state has changed or conflicts with an existing offer. Refresh and try again.'
  if (error.statusCode === 400) return error.message
  return fallback
}

function dateTime(value) {
  if (!value) return '—'
  const valueDate = new Date(value)
  return Number.isNaN(valueDate.getTime()) ? '—' : valueDate.toLocaleString()
}

function dateOnly(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(`${value}T00:00:00Z`)) ? value : '—'
}

function number(value) {
  return value == null || !Number.isFinite(Number(value)) ? '—' : new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(value)
}

function validate(form) {
  if (!form.rentalApplicationId) return 'Select an approved rental application.'
  if (form.monthlyRent === '' || !Number.isFinite(Number(form.monthlyRent)) || Number(form.monthlyRent) <= 0) return 'Monthly rent must be greater than zero.'
  if (form.securityDeposit === '' || !Number.isFinite(Number(form.securityDeposit)) || Number(form.securityDeposit) < 0) return 'Security deposit cannot be negative.'
  if (!form.proposedStartDate || !form.proposedEndDate || form.proposedEndDate <= form.proposedStartDate) return 'Proposed end date must be after the start date.'
  if (!form.expiresAt || Number.isNaN(Date.parse(form.expiresAt)) || new Date(form.expiresAt) <= new Date()) return 'Offer expiry must be in the future.'
  if (form.landlordNote.length > 1000) return 'Landlord note must be 1000 characters or fewer.'
  return ''
}

function OfferDetails({ offer, propertyName, onWithdraw, withdrawing }) {
  return <AppCard className="rental-offer-details">
    <div className="rental-offer-heading"><h2>Offer details</h2><StatusBadge tone={offer.status === 0 ? 'progress' : offer.status === 1 ? 'success' : 'neutral'}>{statuses[offer.status] ?? 'Unknown'}</StatusBadge></div>
    <dl className="rental-offer-facts">
      <div><dt>Property</dt><dd>{propertyName || offer.propertyId}</dd></div>
      <div><dt>Tenant</dt><dd>{offer.tenantId}</dd></div>
      <div><dt>Application</dt><dd>{offer.rentalApplicationId}</dd></div>
      <div><dt>Monthly rent</dt><dd>{number(offer.monthlyRent)}</dd></div>
      <div><dt>Security deposit</dt><dd>{number(offer.securityDeposit)}</dd></div>
      <div><dt>Proposed start</dt><dd>{dateOnly(offer.proposedStartDate)}</dd></div>
      <div><dt>Proposed end</dt><dd>{dateOnly(offer.proposedEndDate)}</dd></div>
      <div><dt>Expires</dt><dd>{dateTime(offer.expiresAt)}</dd></div>
      <div><dt>Created</dt><dd>{dateTime(offer.createdAt)}</dd></div>
      <div><dt>Updated</dt><dd>{dateTime(offer.updatedAt)}</dd></div>
    </dl>
    {offer.landlordNote && <div className="rental-offer-note"><h3>Landlord note</h3><p>{offer.landlordNote}</p></div>}
    {offer.status === 0 && <button className="shared-button shared-button--outline shared-button--danger" type="button" onClick={onWithdraw} disabled={withdrawing}>{withdrawing ? 'Withdrawing…' : 'Withdraw offer'}</button>}
  </AppCard>
}

export default function RentalOffersPage() {
  const [offersState, setOffersState] = useState({ status: 'loading', items: [], error: '' })
  const [propertiesState, setPropertiesState] = useState({ status: 'loading', items: [], error: '' })
  const [propertyId, setPropertyId] = useState('')
  const [applicationsState, setApplicationsState] = useState({ propertyId: '', status: 'idle', items: [], error: '' })
  const [form, setForm] = useState(blankForm)
  const [formError, setFormError] = useState('')
  const [notice, setNotice] = useState('')
  const [saving, setSaving] = useState(false)
  const [withdrawing, setWithdrawing] = useState(false)
  const [detailState, setDetailState] = useState({ status: 'idle', offer: null, error: '' })
  const detailRequest = useRef(0)
  const [offersReload, setOffersReload] = useState(0)
  const [propertiesReload, setPropertiesReload] = useState(0)

  useEffect(() => {
    let active = true
    getLandlordOffers().then((items) => {
      if (active) setOffersState({ status: 'ready', items, error: '' })
    }).catch((error) => {
      if (active) setOffersState({ status: 'error', items: [], error: safeError(error, 'Unable to load rental offers.') })
    })
    return () => { active = false }
  }, [offersReload])

  useEffect(() => {
    let active = true
    getMyProperties().then((items) => {
      if (active) setPropertiesState({ status: 'ready', items, error: '' })
    }).catch((error) => {
      if (active) setPropertiesState({ status: 'error', items: [], error: safeError(error, 'Unable to load your properties.') })
    })
    return () => { active = false }
  }, [propertiesReload])

  useEffect(() => {
    if (!propertyId) return undefined
    let active = true
    getApplicationsByProperty(propertyId).then((items) => {
      if (active) setApplicationsState({ propertyId, status: 'ready', items: items.filter((item) => item.status === RENTAL_APPLICATION_STATUS.APPROVED), error: '' })
    }).catch((error) => {
      if (active) setApplicationsState({ propertyId, status: 'error', items: [], error: safeError(error, 'Unable to load approved applications.') })
    })
    return () => { active = false }
  }, [propertyId])

  async function openOffer(id) {
    const request = ++detailRequest.current
    setDetailState({ status: 'loading', offer: null, error: '' })
    try {
      const offer = await getRentalOffer(id)
      if (request === detailRequest.current) setDetailState({ status: 'ready', offer, error: '' })
    } catch (error) {
      if (request === detailRequest.current) setDetailState({ status: 'error', offer: null, error: safeError(error, 'Unable to load the rental offer.') })
    }
  }

  async function submit(event) {
    event.preventDefault()
    if (saving) return
    const error = validate(form)
    if (error) { setFormError(error); return }
    setSaving(true)
    setFormError('')
    setNotice('')
    try {
      const offer = await createRentalOffer({
        rentalApplicationId: form.rentalApplicationId,
        monthlyRent: Number(form.monthlyRent),
        securityDeposit: Number(form.securityDeposit),
        proposedStartDate: form.proposedStartDate,
        proposedEndDate: form.proposedEndDate,
        expiresAt: new Date(form.expiresAt).toISOString(),
        landlordNote: form.landlordNote.trim() || null,
      })
      ++detailRequest.current
      setDetailState({ status: 'ready', offer, error: '' })
      setNotice('Rental offer created successfully.')
      setForm(blankForm)
      setOffersState((current) => ({ ...current, status: 'loading' }))
      setOffersReload((value) => value + 1)
    } catch (requestError) {
      setFormError(safeError(requestError, 'Unable to create the rental offer.'))
    } finally {
      setSaving(false)
    }
  }

  async function withdraw() {
    if (withdrawing || detailState.status !== 'ready' || detailState.offer.status !== 0) return
    const id = detailState.offer.id
    setWithdrawing(true)
    setNotice('')
    setDetailState((current) => ({ ...current, error: '' }))
    try {
      const offer = await withdrawRentalOffer(id)
      setDetailState((current) => current.offer?.id === id ? { status: 'ready', offer, error: '' } : current)
      setNotice('Rental offer withdrawn.')
      setOffersState((current) => ({ ...current, status: 'loading' }))
      setOffersReload((value) => value + 1)
    } catch (error) {
      setDetailState((current) => ({ ...current, error: safeError(error, 'Unable to withdraw the rental offer.') }))
    } finally {
      setWithdrawing(false)
    }
  }

  const applications = applicationsState.propertyId === propertyId ? applicationsState : { status: propertyId ? 'loading' : 'idle', items: [] }
  const selectedProperty = propertiesState.items.find((item) => item.id === propertyId)
  const propertyName = (id) => propertiesState.items.find((item) => item.id === id)?.title

  return <main className="shared-page rental-offers-page">
    <PageHeader eyebrow="Pricing / Lease" title="Rental Offers"><p>Create offers for approved applications and review offers for your properties.</p></PageHeader>
    <PricingLeaseNavigation />
    {notice && <p className="shared-notice" role="status">{notice}</p>}
    <div className="rental-offers-layout">
      <section aria-label="Rental offer list"><AppCard>
        <div className="rental-offer-heading"><h2>Your offers</h2><button className="shared-button shared-button--outline" type="button" onClick={() => { setOffersState((current) => ({ ...current, status: 'loading' })); setOffersReload((value) => value + 1) }} disabled={offersState.status === 'loading'}>Refresh</button></div>
        {offersState.status === 'loading' && <p role="status">Loading rental offers…</p>}
        {offersState.status === 'error' && <div role="alert"><p>{offersState.error}</p><button className="shared-button shared-button--outline" type="button" onClick={() => { setOffersState((current) => ({ ...current, status: 'loading' })); setOffersReload((value) => value + 1) }}>Try again</button></div>}
        {offersState.status === 'ready' && (offersState.items.length === 0 ? <p>No rental offers yet.</p> : <ul className="rental-offer-list">{offersState.items.map((offer) => <li key={offer.id}><div><strong>{propertyName(offer.propertyId) || offer.propertyId}</strong><span>{statuses[offer.status] ?? 'Unknown'} · Monthly rent {number(offer.monthlyRent)}</span><small>Created {dateTime(offer.createdAt)}</small></div><button className="shared-button shared-button--outline" type="button" onClick={() => openOffer(offer.id)} disabled={saving || withdrawing || detailState.status === 'loading'}>View details</button></li>)}</ul>)}
      </AppCard></section>
      <section aria-label="Create rental offer"><AppCard><h2>Create rental offer</h2>
        {propertiesState.status === 'loading' && <p role="status">Loading your properties…</p>}
        {propertiesState.status === 'error' && <div role="alert"><p>{propertiesState.error}</p><button className="shared-button shared-button--outline" type="button" onClick={() => { setPropertiesState((current) => ({ ...current, status: 'loading' })); setPropertiesReload((value) => value + 1) }}>Try again</button></div>}
        {propertiesState.status === 'ready' && (propertiesState.items.length === 0 ? <p>Add a property before creating an offer.</p> : <form className="rental-offer-form" onSubmit={submit} noValidate>
          <label>Property<select value={propertyId} disabled={saving} onChange={(event) => { setPropertyId(event.target.value); setForm((current) => ({ ...current, rentalApplicationId: '' })); setFormError('') }}><option value="">Select a property</option>{propertiesState.items.map((property) => <option key={property.id} value={property.id}>{property.title} — {property.city}</option>)}</select></label>
          {!propertyId && <p>Select a property to load approved applications.</p>}
          {applications.status === 'loading' && <p role="status">Loading approved applications…</p>}
          {applications.status === 'error' && <p className="shared-notice shared-notice--error" role="alert">{applications.error}</p>}
          {applications.status === 'ready' && applications.items.length === 0 && <p>No approved applications for this property.</p>}
          <label>Approved application<select value={form.rentalApplicationId} disabled={saving || applications.status !== 'ready' || applications.items.length === 0} onChange={(event) => setForm((current) => ({ ...current, rentalApplicationId: event.target.value }))}><option value="">Select an application</option>{applications.items.map((application) => <option key={application.id} value={application.id}>{application.id} — Tenant {application.tenantId}</option>)}</select></label>
          {selectedProperty && <p className="rental-offer-form__context">Creating an offer for {selectedProperty.title}.</p>}
          <div className="rental-offer-form__two"><label>Monthly rent<input type="number" min="0.01" step="0.01" value={form.monthlyRent} disabled={saving} onChange={(event) => setForm((current) => ({ ...current, monthlyRent: event.target.value }))} /></label><label>Security deposit<input type="number" min="0" step="0.01" value={form.securityDeposit} disabled={saving} onChange={(event) => setForm((current) => ({ ...current, securityDeposit: event.target.value }))} /></label></div>
          <div className="rental-offer-form__two"><label>Proposed start date<input type="date" value={form.proposedStartDate} disabled={saving} onChange={(event) => setForm((current) => ({ ...current, proposedStartDate: event.target.value }))} /></label><label>Proposed end date<input type="date" value={form.proposedEndDate} disabled={saving} onChange={(event) => setForm((current) => ({ ...current, proposedEndDate: event.target.value }))} /></label></div>
          <label>Offer expiry<input type="datetime-local" value={form.expiresAt} disabled={saving} onChange={(event) => setForm((current) => ({ ...current, expiresAt: event.target.value }))} /></label>
          <label>Landlord note<textarea maxLength={1000} value={form.landlordNote} disabled={saving} onChange={(event) => setForm((current) => ({ ...current, landlordNote: event.target.value }))} /></label>
          {formError && <p className="shared-notice shared-notice--error" role="alert">{formError}</p>}
          <button className="shared-button" type="submit" disabled={saving || applications.status !== 'ready' || applications.items.length === 0}>{saving ? 'Creating…' : 'Create offer'}</button>
        </form>)}
      </AppCard></section>
    </div>
    <section className="rental-offer-selected" aria-label="Selected rental offer">
      {detailState.status === 'loading' && <AppCard><p role="status">Loading offer details…</p></AppCard>}
      {detailState.status === 'error' && <AppCard><p className="shared-notice shared-notice--error" role="alert">{detailState.error}</p></AppCard>}
      {detailState.status === 'ready' && <><OfferDetails offer={detailState.offer} propertyName={propertyName(detailState.offer.propertyId)} onWithdraw={withdraw} withdrawing={withdrawing} />{detailState.error && <p className="shared-notice shared-notice--error" role="alert">{detailState.error}</p>}</>}
    </section>
  </main>
}
