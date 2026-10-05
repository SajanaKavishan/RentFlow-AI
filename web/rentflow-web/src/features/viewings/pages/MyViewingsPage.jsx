import { useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useAuth } from '../../auth/useAuth.js'
import PropertyWorkflowHandoff from '../../properties/components/PropertyWorkflowHandoff.jsx'
import { AppCard, PageHeader } from '../../../shared/ui/States.jsx'
import Icon from '../../../shared/ui/Icons.jsx'
import ViewingStatusBadge from '../components/ViewingStatusBadge.jsx'
import { getMyViewings, ViewingApiError } from '../services/viewingApiService.js'
import '../viewings.css'
import './my-viewings.css'

const dateTimeFormatter = new Intl.DateTimeFormat(undefined, { dateStyle: 'full', timeStyle: 'short' })

function validateViewings(viewings, tenantId) {
  if (!Array.isArray(viewings) || viewings.some((viewing) =>
    !viewing || typeof viewing.id !== 'string' || typeof viewing.propertyId !== 'string'
    || typeof viewing.tenantId !== 'string' || viewing.tenantId.toLowerCase() !== tenantId.toLowerCase()
    || !Number.isInteger(viewing.status) || typeof viewing.requestedDateTime !== 'string'
    || Number.isNaN(Date.parse(viewing.requestedDateTime))
    || (viewing.propertyTitle != null && typeof viewing.propertyTitle !== 'string')
    || (viewing.landlordResponse != null && typeof viewing.landlordResponse !== 'string')
  )) throw new TypeError('Invalid tenant viewing response')
  return viewings
}

export default function MyViewingsPage() {
  const { user } = useAuth()
  const [searchParams] = useSearchParams()
  const propertyId = searchParams.get('propertyId')?.trim() || null
  const [attempt, setAttempt] = useState(0)
  const [state, setState] = useState({ status: 'loading', viewings: [], error: '' })

  useEffect(() => {
    let active = true
    getMyViewings().then((viewings) => {
      if (active) setState({ status: 'ready', viewings: validateViewings(viewings, user.id), error: '' })
    }).catch((error) => {
      if (active) setState({ status: 'error', viewings: [], error: error instanceof ViewingApiError
        ? error.message : 'Your viewings could not be loaded. Please try again.' })
    })
    return () => { active = false }
  }, [attempt, user.id])

  function reload() {
    setState({ status: 'loading', viewings: [], error: '' })
    setAttempt((value) => value + 1)
  }

  const selectedPropertyViewings = propertyId
    ? state.viewings.filter((viewing) => viewing.propertyId.toLowerCase() === propertyId.toLowerCase()).length
    : 0

  return <main className="shared-page my-viewings-page">
    <div className="my-viewings-page__heading">
      <PageHeader eyebrow="Viewing journey" title="Your requests">
        <p>Review your viewing requests and landlord responses. Use the mobile app to book or cancel a viewing.</p>
      </PageHeader>
    </div>
    {propertyId && (
      <PropertyWorkflowHandoff
        propertyId={propertyId}
        workflow="viewing"
        existingCount={selectedPropertyViewings}
      />
    )}
    {state.status === 'loading' && <div className="my-viewings-state" role="status"><span className="shared-spinner" aria-hidden="true" />Loading your viewings&hellip;</div>}
    {state.status === 'error' && <div className="my-viewings-state" role="alert"><h2>Viewings could not be loaded</h2><p>{state.error}</p><button className="shared-button" type="button" onClick={reload}>Try again</button></div>}
    {state.status === 'ready' && state.viewings.length === 0 && <AppCard className="my-viewings-state"><Icon name="calendar" size={28} /><h2>No viewing requests yet</h2><p>Your viewing requests will appear here after you book them in the mobile app.</p></AppCard>}
    {state.status === 'ready' && state.viewings.length > 0 && <section className="my-viewings-list" aria-label="Your viewing requests">
      {state.viewings.map((viewing) => <AppCard key={viewing.id} className="my-viewing-card">
        <div className="my-viewing-card__top"><h2>Viewing request</h2><ViewingStatusBadge status={viewing.status} /></div>
        <dl className="my-viewing-card__details">
          <div><dt>Property</dt><dd>{viewing.propertyTitle?.trim() || 'Property unavailable'}</dd></div>
          <div><dt>Requested date and time</dt><dd><time dateTime={viewing.requestedDateTime}>{(viewing.timeZoneId
            ? new Intl.DateTimeFormat(undefined, { dateStyle: 'full', timeStyle: 'short', timeZone: viewing.timeZoneId })
            : dateTimeFormatter).format(new Date(viewing.requestedDateTime))}</time>{viewing.timeZoneId && ` (${viewing.timeZoneId})`}</dd></div>
        </dl>
        {viewing.landlordResponse?.trim() && <div className="my-viewing-card__response"><h3>Landlord response</h3><p>{viewing.landlordResponse}</p></div>}
      </AppCard>)}
    </section>}
  </main>
}
