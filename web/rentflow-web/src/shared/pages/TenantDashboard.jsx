import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { getNotifications } from '../../features/notifications/notificationsApi.js'
import { notificationTime } from '../../features/notifications/notificationFormat.js'
import {
  getMatchPreferences,
  getProperties,
  getProperty,
  getPropertyImages,
  getPropertyImageUrl,
  getSavedPropertyMatches,
} from '../../features/properties/services/propertyApiService.js'
import RentalApplicationStatusBadge from '../../features/rentalApplications/components/RentalApplicationStatusBadge.jsx'
import { getMyApplications, RENTAL_APPLICATION_STATUS } from '../../features/rentalApplications/services/rentalApplicationApiService.js'
import { getMyLeases, getScheduleByLease } from '../../features/tenantLeasePayments/services/tenantLeasePaymentsApi.js'
import ViewingStatusBadge from '../../features/viewings/components/ViewingStatusBadge.jsx'
import { getMyViewings, VIEWING_STATUS } from '../../features/viewings/services/viewingApiService.js'
import { StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import useTenantSummary from './useTenantSummary.js'
import './tenant-dashboard.css'

const dateFormatter = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' })
const viewingFormatter = new Intl.DateTimeFormat(undefined, {
  dateStyle: 'full',
  timeStyle: 'short',
})
const moneyFormatter = new Intl.NumberFormat(undefined, {
  minimumFractionDigits: 0,
  maximumFractionDigits: 2,
})

function validDate(value) {
  return typeof value === 'string' && Number.isFinite(Date.parse(value))
}

function formatDate(value, fallback = 'Not submitted') {
  return validDate(value) ? dateFormatter.format(new Date(value)) : fallback
}

function propertyLocation(property) {
  if (!property) return 'Location unavailable'
  return [property.address, property.city].filter(Boolean).join(', ') || 'Location unavailable'
}

function applicationTimestamp(application) {
  return application.submittedAt || application.createdAt || ''
}

function useNotificationsSummary(userId) {
  const [attempt, setAttempt] = useState(0)
  const [state, setState] = useState({ status: 'loading', data: [] })

  useEffect(() => {
    let active = true
    getNotifications(1, 5).then((response) => {
      if (active) setState({ status: 'ready', data: response.items })
    }).catch((error) => {
      if (active) setState({ status: 'error', data: [], message: error.message })
    })
    return () => { active = false }
  }, [attempt, userId])

  return {
    ...state,
    retry() {
      setState({ status: 'loading', data: [] })
      setAttempt((value) => value + 1)
    },
  }
}

function useNextPayment(userId) {
  const [attempt, setAttempt] = useState(0)
  const [state, setState] = useState({ status: 'loading', item: null })

  useEffect(() => {
    let active = true

    async function loadNextPayment() {
      try {
        const leases = await getMyLeases()
        if (!Array.isArray(leases)) throw new TypeError('The lease service returned an invalid response.')
        const activeLeases = leases.filter((lease) => lease?.status === 1 && typeof lease.id === 'string')
        if (activeLeases.length === 0) {
          if (active) setState({ status: 'ready', item: null })
          return
        }

        const scheduleResults = await Promise.allSettled(activeLeases.map(async (lease) => {
          const items = await getScheduleByLease(lease.id)
          if (!Array.isArray(items)) throw new TypeError('The rent schedule service returned an invalid response.')
          return items
        }))
        const successful = scheduleResults.filter((result) => result.status === 'fulfilled')
        if (successful.length === 0) throw scheduleResults[0].reason

        const outstanding = successful.flatMap((result) => result.value)
          .filter((item) => item && (item.status === 0 || item.status === 2)
            && validDate(item.dueDate) && Number.isFinite(Number(item.amount)))
          .sort((a, b) => Date.parse(a.dueDate) - Date.parse(b.dueDate))
        if (outstanding.length === 0 && successful.length !== scheduleResults.length) {
          throw new Error('Some rent schedules could not be loaded. Open Lease & Payments for the latest details.')
        }
        if (active) setState({ status: 'ready', item: outstanding[0] || null })
      } catch (error) {
        if (active) setState({ status: 'error', item: null, message: error.message || 'Unable to load the next payment.' })
      }
    }

    loadNextPayment()
    return () => { active = false }
  }, [attempt, userId])

  return {
    ...state,
    retry() {
      setState({ status: 'loading', item: null })
      setAttempt((value) => value + 1)
    },
  }
}

function usePropertyDirectory(propertyIds) {
  const [directory, setDirectory] = useState({})

  useEffect(() => {
    let active = true
    if (propertyIds.length === 0) {
      return () => { active = false }
    }

    Promise.all(propertyIds.map(async (id) => {
      try {
        const property = await getProperty(id)
        return [id, property?.id === id ? property : null]
      } catch {
        return [id, null]
      }
    })).then((entries) => {
      if (active) setDirectory(Object.fromEntries(entries))
    })

    return () => { active = false }
  }, [propertyIds])

  return directory
}

function SummaryCard({ title, ariaLabel = title, icon, summary, children, pending }) {
  return <section className="tenant-summary" aria-label={ariaLabel} aria-busy={summary?.status === 'loading'}>
    <span className="tenant-summary__icon"><Icon name={icon} size={21} /></span>
    {pending && <><strong className="tenant-summary__pending">Unavailable</strong><StatusBadge tone="warning">Integration pending</StatusBadge>{children}</>}
    {summary?.status === 'loading' && <p className="tenant-summary__state" role="status">Loading summary&hellip;</p>}
    {summary?.status === 'error' && <div className="tenant-summary__state" role="alert"><p>{summary.message || 'Unable to load this summary.'}</p><button className="tenant-retry" type="button" onClick={summary.retry}>Retry {title.toLowerCase()}</button></div>}
    {summary?.status === 'ready' && children}
    <span className="tenant-summary__label">{title}</span>
  </section>
}

function NotificationIcon({ type }) {
  const icon = type.startsWith('viewing.') ? 'calendar'
    : type.startsWith('rental_application.') ? 'document'
      : type.startsWith('maintenance') ? 'tools' : 'bell'
  return <span className="tenant-activity__icon"><Icon name={icon} size={18} /></span>
}

function RecommendedSection({ userId }) {
  const [state, setState] = useState({ status: 'loading', items: [], configured: false, message: '' })
  const [attempt, setAttempt] = useState(0)

  useEffect(() => {
    let active = true
    async function loadRecommendations() {
      setState({ status: 'loading', items: [], configured: false, message: '' })
      try {
        const preferences = await getMatchPreferences()
        if (!preferences.isConfigured) {
          if (active) setState({ status: 'ready', items: [], configured: false, message: '' })
          return
        }
        const [matches, properties] = await Promise.all([
          getSavedPropertyMatches(),
          getProperties({ isAvailable: true }),
        ])
        const propertyById = new Map(properties.map((property) => [property.id, property]))
        const ranked = (matches.matches || []).slice(0, 3).map((match) => ({
          ...propertyById.get(match.propertyId),
          ...match,
          id: match.propertyId,
        })).filter((property) => property.title)
        const withImages = await Promise.all(ranked.map(async (property) => {
          try {
            const images = await getPropertyImages(property.id)
            if (!images?.length) return property
            const image = await getPropertyImageUrl(property.id, images[0].id)
            return { ...property, imageUrl: image?.url || null }
          } catch {
            return property
          }
        }))
        if (active) setState({ status: 'ready', items: withImages, configured: true, message: '' })
      } catch (error) {
        if (active) setState({ status: 'error', items: [], configured: false, message: error.message || 'Unable to load recommendations.' })
      }
    }
    loadRecommendations()
    return () => { active = false }
  }, [attempt, userId])

  return <section className="tenant-dashboard__section" aria-labelledby="tenant-recommended-title">
    <div className="tenant-section-heading">
      <h2 id="tenant-recommended-title">Recommended for You</h2>
      <Link to="/modules/properties">View all <Icon name="arrow" size={16} /></Link>
    </div>
    {state.status === 'loading' && <div className="tenant-recommendations-empty" role="status"><span className="shared-spinner" aria-hidden="true" /><h3>Finding your best matches</h3><p>Ranking currently available properties from your saved preferences.</p></div>}
    {state.status === 'error' && <div className="tenant-recommendations-empty" role="alert"><span className="tenant-recommendations-empty__icon"><Icon name="building" size={32} /></span><h3>Recommendations could not be loaded</h3><p>{state.message}</p><button className="shared-button shared-button--outline" type="button" onClick={() => setAttempt((value) => value + 1)}>Retry</button></div>}
    {state.status === 'ready' && !state.configured && <div className="tenant-recommendations-empty">
      <span className="tenant-recommendations-empty__icon"><Icon name="building" size={32} /></span>
      <h3>Get personalized property recommendations</h3>
      <p>Set your preferences to see real available properties ranked for you.</p>
      <div className="tenant-recommendations-empty__actions">
        <Link className="shared-button" to="/modules/properties?preferences=edit">Set match preferences</Link>
        <Link className="shared-button shared-button--outline" to="/modules/properties">Browse properties</Link>
      </div>
    </div>}
    {state.status === 'ready' && state.configured && state.items.length === 0 && <div className="tenant-recommendations-empty"><span className="tenant-recommendations-empty__icon"><Icon name="building" size={32} /></span><h3>No available matches right now</h3><p>New recommendations will appear as suitable properties become available.</p><Link className="shared-button shared-button--outline" to="/modules/properties?preferences=edit">Adjust preferences</Link></div>}
    {state.status === 'ready' && state.items.length > 0 && <div className="tenant-recommendation-grid">{state.items.map((property) => <article className="tenant-recommendation-card" key={property.id}>
      <Link className="tenant-recommendation-card__image" to={`/properties/${property.id}`} aria-label={`View ${property.title}`}>{property.imageUrl ? <img src={property.imageUrl} alt="" /> : <span><Icon name="home" size={28} />No property photo</span>}<strong aria-label={`${property.matchScore} percent match`}>{property.matchScore}% Match</strong></Link>
      <div><p><Icon name="location" size={14} />{property.city}</p><h3>{property.title}</h3><dl><div><dt className="sr-only">Rent</dt><dd>Rs. {moneyFormatter.format(Number(property.monthlyRent))}/month</dd></div><div><dt className="sr-only">Bedrooms and bathrooms</dt><dd>{property.bedrooms} bed · {property.bathrooms} bath</dd></div></dl><Link to={`/properties/${property.id}`}>View property <Icon name="arrow" size={14} /></Link></div>
    </article>)}</div>}
  </section>
}

function RecentActivity({ activity }) {
  return <section className="tenant-dashboard__section" aria-labelledby="tenant-activity-title">
    <div className="tenant-section-heading">
      <h2 id="tenant-activity-title">Recent Activity</h2>
      <Link to="/notifications">View all <Icon name="arrow" size={16} /></Link>
    </div>
    <div className="tenant-activity-card" aria-busy={activity.status === 'loading'}>
      {activity.status === 'loading' && <div className="tenant-panel-state" role="status"><span className="shared-spinner" aria-hidden="true" />Loading recent activity&hellip;</div>}
      {activity.status === 'error' && <div className="tenant-panel-state" role="alert"><strong>Activity could not be loaded</strong><p>{activity.message}</p><button className="tenant-retry" type="button" onClick={activity.retry}>Retry activity</button></div>}
      {activity.status === 'ready' && activity.data.length === 0 && <div className="tenant-panel-state"><span className="tenant-panel-state__icon"><Icon name="bell" size={24} /></span><strong>No recent activity</strong><p>Verified account updates will appear here.</p></div>}
      {activity.status === 'ready' && activity.data.length > 0 && <ol className="tenant-activity-list">
        {activity.data.map((item) => <li key={item.id}>
          <NotificationIcon type={item.eventType} />
          <div><strong>{item.title}</strong><p>{item.message}</p></div>
          <div className="tenant-activity__meta"><time dateTime={item.createdAt}>{notificationTime(item.createdAt)}</time>{!item.isRead && <span className="tenant-activity__unread" aria-label="Unread" />}</div>
        </li>)}
      </ol>}
    </div>
  </section>
}

function UpcomingViewing({ summary, viewing, property }) {
  return <section className="tenant-viewing-highlight" aria-labelledby="tenant-next-viewing-title" aria-busy={summary.status === 'loading'}>
    <div className="tenant-viewing-highlight__decoration" aria-hidden="true"><Icon name="calendar" size={118} /></div>
    <div className="tenant-viewing-highlight__heading">
      <span className="tenant-viewing-highlight__icon"><Icon name="calendar" size={23} /></span>
      <div><p>Next appointment</p><h2 id="tenant-next-viewing-title">Upcoming Viewing</h2></div>
    </div>
    {summary.status === 'loading' && <p role="status">Loading your next viewing&hellip;</p>}
    {summary.status === 'error' && <div role="alert"><p>{summary.message}</p><button className="tenant-viewing-highlight__retry" type="button" onClick={summary.retry}>Retry viewings</button></div>}
    {summary.status === 'ready' && !viewing && <div className="tenant-viewing-highlight__empty"><h3>No upcoming viewing scheduled</h3><p>Approved and pending future viewing requests will appear here.</p><Link to="/modules/properties">Browse available properties <Icon name="arrow" size={16} /></Link></div>}
    {summary.status === 'ready' && viewing && <div className="tenant-viewing-highlight__details">
      <div>
        <ViewingStatusBadge status={viewing.status} />
        <h3>{property?.title || `Property ${viewing.propertyId}`}</h3>
        <p><Icon name="pin" size={17} />{propertyLocation(property)}</p>
      </div>
      <div className="tenant-viewing-highlight__date">
        <span>Date &amp; time</span>
        <time dateTime={viewing.requestedDateTime}>{viewingFormatter.format(new Date(viewing.requestedDateTime))}</time>
      </div>
      <Link className="tenant-viewing-highlight__link" to="/modules/my-viewings">View request <Icon name="arrow" size={17} /></Link>
    </div>}
  </section>
}

function ApplicationsSection({ summary, applications, properties }) {
  return <section className="tenant-dashboard__applications" aria-labelledby="tenant-applications-title">
    <div className="tenant-section-heading">
      <h2 id="tenant-applications-title">My Applications</h2>
      <Link to="/modules/my-applications">View all <Icon name="arrow" size={16} /></Link>
    </div>
    <div className="tenant-applications-card" aria-busy={summary.status === 'loading'}>
      {summary.status === 'loading' && <div className="tenant-panel-state" role="status"><span className="shared-spinner" aria-hidden="true" />Loading your applications&hellip;</div>}
      {summary.status === 'error' && <div className="tenant-panel-state" role="alert"><strong>Applications could not be loaded</strong><p>{summary.message}</p><button className="tenant-retry" type="button" onClick={summary.retry}>Retry applications</button></div>}
      {summary.status === 'ready' && applications.length === 0 && <div className="tenant-panel-state"><span className="tenant-panel-state__icon"><Icon name="document" size={24} /></span><strong>No applications yet</strong><p>Applications created through the supported workflow will appear here.</p></div>}
      {summary.status === 'ready' && applications.length > 0 && <div className="tenant-applications-table-wrap">
        <table className="tenant-applications-table">
          <thead><tr><th scope="col">Property</th><th scope="col">Submitted</th><th scope="col">Status</th><th scope="col"><span className="sr-only">Action</span></th></tr></thead>
          <tbody>{applications.map((application) => {
            const property = properties[application.propertyId]
            const submitted = applicationTimestamp(application)
            return <tr key={application.id}>
              <td data-label="Property"><strong>{property?.title || (application.propertyId ? `Property ${application.propertyId}` : 'Property details unavailable')}</strong><span>{propertyLocation(property)}</span></td>
              <td data-label="Submitted">{submitted ? <time dateTime={submitted}>{formatDate(submitted, 'Date unavailable')}</time> : 'Not submitted'}</td>
              <td data-label="Status"><RentalApplicationStatusBadge status={application.status} /></td>
              <td data-label="Action"><Link to={`/notifications/rental-application/${encodeURIComponent(application.id)}`}>View <Icon name="arrow" size={15} /></Link></td>
            </tr>
          })}</tbody>
        </table>
      </div>}
    </div>
  </section>
}

export default function TenantDashboard({ user }) {
  const applications = useTenantSummary(getMyApplications)
  const viewings = useTenantSummary(getMyViewings)
  const activity = useNotificationsSummary(user.id)
  const nextPayment = useNextPayment(user.id)

  const sortedApplications = useMemo(() => [...applications.data]
    .sort((a, b) => Date.parse(applicationTimestamp(b)) - Date.parse(applicationTimestamp(a)))
    .slice(0, 5), [applications.data])
  const underReview = applications.data.filter((item) => item.status === RENTAL_APPLICATION_STATUS.UNDER_REVIEW).length
  const now = viewings.loadedAt
  const upcoming = viewings.data.filter((item) =>
    (item.status === VIEWING_STATUS.APPROVED || item.status === VIEWING_STATUS.PENDING)
    && validDate(item.requestedDateTime) && Date.parse(item.requestedDateTime) > now)
    .sort((a, b) => Date.parse(a.requestedDateTime) - Date.parse(b.requestedDateTime))
  const nextViewing = upcoming[0]
  const propertyIds = useMemo(() => Array.from(new Set([
    ...sortedApplications.map((item) => item.propertyId),
    nextViewing?.propertyId,
  ].filter((id) => typeof id === 'string' && id))), [sortedApplications, nextViewing?.propertyId])
  const properties = usePropertyDirectory(propertyIds)

  return <main className="shared-page tenant-dashboard">
    <header className="tenant-dashboard__greeting">
      <div><p className="tenant-dashboard__eyebrow">Tenant dashboard</p><h1>Welcome, {user.fullName.trim() || 'there'}</h1><p>Track your rental journey, appointments and account updates in one place.</p></div>
    </header>

    <div className="tenant-dashboard__summaries">
      <SummaryCard title="Applications" icon="document" summary={applications}>
        <strong className="tenant-summary__value">{applications.data.length}</strong>
        <p>{applications.data.length === 0 ? 'No applications yet' : `${underReview} under review`}</p>
      </SummaryCard>
      <SummaryCard title="Upcoming Viewing" ariaLabel="Upcoming Viewing summary" icon="calendar" summary={viewings}>
        <strong className="tenant-summary__value">{upcoming.length}</strong>
        <p>{nextViewing ? <><time dateTime={nextViewing.requestedDateTime}>{formatDate(nextViewing.requestedDateTime, 'Date unavailable')}</time><br />{nextViewing.status === VIEWING_STATUS.APPROVED ? 'Approved' : 'Awaiting approval'}</> : 'No upcoming viewings'}</p>
      </SummaryCard>
      <SummaryCard title="Next Payment" icon="trend" summary={nextPayment}>
        {nextPayment.item ? <><strong className="tenant-summary__value tenant-summary__value--money">Rs. {moneyFormatter.format(nextPayment.item.amount)}</strong><p>Due <time dateTime={nextPayment.item.dueDate}>{formatDate(nextPayment.item.dueDate, 'Date unavailable')}</time></p></> : <><strong className="tenant-summary__empty-value">No payment due</strong><p>No unpaid schedule items found</p></>}
      </SummaryCard>
      <SummaryCard title="Open Request" icon="tools" pending>
        <p>Maintenance request summaries are not yet available on the web dashboard.</p>
      </SummaryCard>
    </div>

    <div className="tenant-dashboard__middle">
      <RecommendedSection userId={user.id} />
      <div className="tenant-dashboard__side">
        <RecentActivity activity={activity} />
        <UpcomingViewing summary={viewings} viewing={nextViewing} property={properties[nextViewing?.propertyId]} />
      </div>
    </div>

    <ApplicationsSection summary={applications} applications={sortedApplications} properties={properties} />
  </main>
}
