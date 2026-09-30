import { useCallback, useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { getTenantMaintenanceRequests } from '../../features/maintenance/maintenanceApi.js'
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
import { getMyLeases, getMyPayments, getScheduleByLease } from '../../features/tenantLeasePayments/services/tenantLeasePaymentsApi.js'
import ViewingStatusBadge from '../../features/viewings/components/ViewingStatusBadge.jsx'
import { getMyViewings, VIEWING_STATUS } from '../../features/viewings/services/viewingApiService.js'
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
const relativeTimeFormatter = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' })

const viewingActivity = {
  [VIEWING_STATUS.PENDING]: 'Viewing requested',
  [VIEWING_STATUS.APPROVED]: 'Viewing approved',
  [VIEWING_STATUS.REJECTED]: 'Viewing declined',
  [VIEWING_STATUS.CANCELLED]: 'Viewing cancelled',
  [VIEWING_STATUS.COMPLETED]: 'Viewing completed',
}
const applicationActivity = {
  [RENTAL_APPLICATION_STATUS.DRAFT]: 'Application draft created',
  [RENTAL_APPLICATION_STATUS.SUBMITTED]: 'Application submitted',
  [RENTAL_APPLICATION_STATUS.UNDER_REVIEW]: 'Application under review',
  [RENTAL_APPLICATION_STATUS.CHANGES_REQUESTED]: 'Application changes requested',
  [RENTAL_APPLICATION_STATUS.APPROVED]: 'Application approved',
  [RENTAL_APPLICATION_STATUS.REJECTED]: 'Application declined',
  [RENTAL_APPLICATION_STATUS.WITHDRAWN]: 'Application withdrawn',
}
const leaseActivity = ['Lease pending', 'Lease active', 'Lease terminated', 'Lease completed']
const paymentActivity = ['Payment pending', 'Payment completed', 'Payment failed']
const maintenanceActivity = [
  'Maintenance request submitted', 'Maintenance request triaged', 'Technician assigned',
  'Repair estimate pending', 'Repair estimate submitted', 'Awaiting landlord approval',
  'Repair approved', 'Repair rejected', 'Repair in progress', 'Repair completed', 'Maintenance request cancelled',
]
const tenantGreetings = ['Welcome back', 'Good to see you', 'Hello', 'Hi there']

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

function latestTimestamp(item, preferred = []) {
  return [...preferred, 'updatedAt', 'createdAt'].map((field) => item?.[field]).find(validDate) || ''
}

function activityTime(value) {
  if (!validDate(value)) return 'Date unavailable'
  const elapsedSeconds = (Date.parse(value) - Date.now()) / 1000
  const ranges = [
    ['year', 60 * 60 * 24 * 365],
    ['month', 60 * 60 * 24 * 30],
    ['week', 60 * 60 * 24 * 7],
    ['day', 60 * 60 * 24],
    ['hour', 60 * 60],
    ['minute', 60],
  ]
  const absoluteSeconds = Math.abs(elapsedSeconds)
  if (absoluteSeconds >= 60 * 60 * 24 * 7) return notificationTime(value)
  const [unit, seconds] = ranges.find(([, size]) => absoluteSeconds >= size) || ['second', 1]
  return relativeTimeFormatter.format(Math.round(elapsedSeconds / seconds), unit)
}

function notificationIcon(type) {
  if (type.startsWith('viewing.')) return 'calendar'
  if (type.startsWith('rental_application.')) return 'document'
  if (type.startsWith('payment.') || type.startsWith('lease.')) return 'wallet'
  if (type.startsWith('maintenance')) return 'tools'
  return 'bell'
}

function normalizeActivities({ notifications, viewings, applications, leases, payments, maintenance }) {
  const items = [
    ...notifications.map((item) => ({
      id: `notification:${item.id}`,
      icon: notificationIcon(item.eventType),
      tone: 'notification',
      title: item.title,
      description: item.message,
      timestamp: item.createdAt,
      target: '/notifications',
      source: 'Notification',
      unread: !item.isRead,
    })),
    ...viewings.map((item) => ({
      id: `viewing:${item.id}`,
      icon: 'calendar',
      tone: 'viewing',
      title: viewingActivity[item.status] || 'Viewing updated',
      description: validDate(item.requestedDateTime)
        ? `Appointment ${viewingFormatter.format(new Date(item.requestedDateTime))}`
        : 'Appointment date unavailable',
      timestamp: latestTimestamp(item),
      target: '/modules/my-viewings',
      source: 'Viewing',
    })),
    ...applications.map((item) => ({
      id: `application:${item.id}`,
      icon: 'document',
      tone: 'application',
      title: applicationActivity[item.status] || 'Application updated',
      description: item.landlordResponse || `Current status: ${(applicationActivity[item.status] || 'Status unavailable').replace('Application ', '').toLowerCase()}.`,
      timestamp: latestTimestamp(item, ['submittedAt']),
      target: `/notifications/rental-application/${encodeURIComponent(item.id)}`,
      source: 'Application',
    })),
    ...leases.map((item) => ({
      id: `lease:${item.id}`,
      icon: 'wallet',
      tone: 'payment',
      title: leaseActivity[item.status] || 'Lease updated',
      description: item.startDate && item.endDate
        ? `Lease term ${formatDate(item.startDate, item.startDate)} to ${formatDate(item.endDate, item.endDate)}`
        : 'Lease details updated.',
      timestamp: latestTimestamp(item),
      target: '/modules/lease-payments',
      source: 'Lease',
    })),
    ...payments.map((item) => ({
      id: `payment:${item.id}`,
      icon: 'wallet',
      tone: 'payment',
      title: paymentActivity[item.status] || 'Payment updated',
      description: `${Number.isFinite(Number(item.amount)) ? `Rs. ${moneyFormatter.format(Number(item.amount))}` : 'Amount unavailable'}${item.paymentMethod ? ` via ${item.paymentMethod}` : ''}`,
      timestamp: latestTimestamp(item, ['paidAt']),
      target: '/modules/lease-payments',
      source: 'Payment',
    })),
    ...maintenance.map((item) => ({
      id: `maintenance:${item.id}`,
      icon: 'tools',
      tone: 'maintenance',
      title: maintenanceActivity[item.status] || 'Maintenance request updated',
      description: item.title || 'Maintenance request details updated.',
      timestamp: latestTimestamp(item),
      target: null,
      source: 'Maintenance',
    })),
  ]

  return items.sort((a, b) => (Date.parse(b.timestamp) || 0) - (Date.parse(a.timestamp) || 0)).slice(0, 6)
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

function useNextPayment(userId, leases) {
  const [attempt, setAttempt] = useState(0)
  const [state, setState] = useState({ status: 'loading', item: null })

  useEffect(() => {
    let active = true
    if (leases.status !== 'ready') return () => { active = false }

    async function loadNextPayment() {
      try {
        const activeLeases = leases.data.filter((lease) => lease?.status === 1 && typeof lease.id === 'string')
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
  }, [attempt, leases.data, leases.message, leases.status, userId])

  const visibleState = leases.status === 'loading'
    ? { status: 'loading', item: null }
    : leases.status === 'error'
      ? { status: 'error', item: null, message: leases.message || 'Unable to load your leases.' }
      : state

  return {
    ...visibleState,
    retry() {
      setState({ status: 'loading', item: null })
      if (leases.status === 'error') leases.retry()
      else setAttempt((value) => value + 1)
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

function SummaryCard({ title, ariaLabel = title, icon, summary, children }) {
  return <section className="tenant-summary" aria-label={ariaLabel} aria-busy={summary?.status === 'loading'}>
    <span className="tenant-summary__icon" data-icon={icon}><Icon name={icon} size={21} /></span>
    {summary?.status === 'loading' && <p className="tenant-summary__state" role="status">Loading summary&hellip;</p>}
    {summary?.status === 'error' && <div className="tenant-summary__state" role="alert"><p>{summary.message || 'Unable to load this summary.'}</p><button className="tenant-retry" type="button" onClick={summary.retry}>Retry {title.toLowerCase()}</button></div>}
    {summary?.status === 'ready' && children}
    <span className="tenant-summary__label">{title}</span>
  </section>
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
        const ranked = (matches.matches || [])
          .map((match) => ({
            ...propertyById.get(match.propertyId),
            ...match,
            id: match.propertyId,
          }))
          .filter((property) => property.title && Number.isFinite(Number(property.matchScore)))
          .sort((left, right) => Number(right.matchScore) - Number(left.matchScore))
          .slice(0, 3)
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
      <Link className="tenant-recommendation-card__link" to={`/properties/${property.id}`} aria-label={`View ${property.title}`}>
        <div className="tenant-recommendation-card__image">{property.imageUrl ? <img src={property.imageUrl} alt="" /> : <span><Icon name="home" size={28} />No property photo</span>}<strong aria-label={`${property.matchScore} percent match`}><Icon name="sparkles" size={13} />{property.matchScore}% Match</strong></div>
        <div className="tenant-recommendation-card__details">
          <h3>{property.title}</h3>
          <p className="tenant-recommendation-card__location"><Icon name="location" size={14} />{property.city}</p>
          <dl className="tenant-recommendation-card__facts">
            <div className="tenant-recommendation-card__rent"><dt className="sr-only">Monthly rent</dt><dd><strong>Rs. {moneyFormatter.format(Number(property.monthlyRent))}</strong><span>/mo</span></dd></div>
            <div><dt className="sr-only">Bedrooms</dt><dd><Icon name="bed" size={15} />{property.bedrooms}</dd></div>
            <div><dt className="sr-only">Bathrooms</dt><dd><Icon name="bath" size={15} />{property.bathrooms}</dd></div>
          </dl>
        </div>
      </Link>
      {/* The previous compact text layout is retained only as migration context.
      <div><p><Icon name="location" size={14} />{property.city}</p><h3>{property.title}</h3><dl><div><dt className="sr-only">Rent</dt><dd>Rs. {moneyFormatter.format(Number(property.monthlyRent))}/month</dd></div><div><dt className="sr-only">Bedrooms and bathrooms</dt><dd>{property.bedrooms} bed · {property.bathrooms} bath</dd></div></dl><Link to={`/properties/${property.id}`}>View property <Icon name="arrow" size={14} /></Link></div>
      */}
    </article>)}</div>}
  </section>
}

function RecentActivity({ activity }) {
  return <section className="tenant-dashboard__section" aria-labelledby="tenant-activity-title">
    <div className="tenant-section-heading">
      <h2 id="tenant-activity-title">Recent Activity</h2>
    </div>
    <div className="tenant-activity-card" aria-busy={activity.status === 'loading'}>
      {activity.status === 'loading' && <div className="tenant-panel-state" role="status"><span className="shared-spinner" aria-hidden="true" />Loading recent activity&hellip;</div>}
      {activity.status === 'error' && <div className="tenant-panel-state" role="alert"><strong>Activity could not be loaded</strong><p>{activity.message}</p><button className="tenant-retry" type="button" onClick={activity.retry}>Retry activity</button></div>}
      {activity.status === 'ready' && activity.warning && <div className="tenant-activity-warning" role="status"><Icon name="alert" size={15} /><span>{activity.warning}</span><button type="button" onClick={activity.retry}>Retry</button></div>}
      {activity.status === 'ready' && activity.data.length === 0 && <div className="tenant-panel-state"><span className="tenant-panel-state__icon"><Icon name="bell" size={24} /></span><strong>No recent activity</strong><p>Viewing, application, lease, payment, maintenance and account updates will appear here.</p></div>}
      {activity.status === 'ready' && activity.data.length > 0 && <ol className="tenant-activity-list">
        {activity.data.map((item) => <li key={item.id}>
          <span className={`tenant-activity__icon tenant-activity__icon--${item.tone}`}><Icon name={item.icon} size={18} /></span>
          <div className="tenant-activity__content"><span className="tenant-activity__source">{item.source}</span><strong>{item.title}</strong><p>{item.description}</p></div>
          <div className="tenant-activity__meta">{validDate(item.timestamp) ? <time dateTime={item.timestamp}>{activityTime(item.timestamp)}</time> : <span>Date unavailable</span>}{item.unread && <span className="tenant-activity__unread" aria-label="Unread" />}</div>
          {item.target && <Link className="tenant-activity__link" to={item.target} aria-label={`Open ${item.title}`}><Icon name="chevronRight" size={17} /></Link>}
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
  const [greeting] = useState(() => tenantGreetings[Math.floor(Math.random() * tenantGreetings.length)])
  const applications = useTenantSummary(getMyApplications)
  const viewings = useTenantSummary(getMyViewings)
  const notifications = useNotificationsSummary(user.id)
  const leases = useTenantSummary(getMyLeases)
  const payments = useTenantSummary(getMyPayments)
  const loadMaintenance = useCallback(() => getTenantMaintenanceRequests(user.id), [user.id])
  const maintenance = useTenantSummary(loadMaintenance)
  const nextPayment = useNextPayment(user.id, leases)

  const activity = useMemo(() => {
    const sources = [notifications, viewings, applications, leases, payments, maintenance]
    if (sources.some((source) => source.status === 'loading')) return { status: 'loading', data: [] }
    const ready = sources.filter((source) => source.status === 'ready')
    const failed = sources.filter((source) => source.status === 'error')
    const retry = () => failed.forEach((source) => source.retry())
    if (ready.length === 0) {
      return { status: 'error', data: [], message: 'Recent activity could not be loaded from available services.', retry }
    }
    return {
      status: 'ready',
      data: normalizeActivities({
        notifications: notifications.status === 'ready' ? notifications.data : [],
        viewings: viewings.status === 'ready' ? viewings.data : [],
        applications: applications.status === 'ready' ? applications.data : [],
        leases: leases.status === 'ready' ? leases.data : [],
        payments: payments.status === 'ready' ? payments.data : [],
        maintenance: maintenance.status === 'ready' ? maintenance.data : [],
      }),
      warning: failed.length > 0 ? `Some activity could not be loaded (${failed.length} ${failed.length === 1 ? 'source' : 'sources'} unavailable).` : '',
      retry,
    }
  }, [applications, leases, maintenance, notifications, payments, viewings])

  const sortedApplications = useMemo(() => [...applications.data]
    .sort((a, b) => Date.parse(applicationTimestamp(b)) - Date.parse(applicationTimestamp(a)))
    .slice(0, 5), [applications.data])
  const underReview = applications.data.filter((item) => item.status === RENTAL_APPLICATION_STATUS.UNDER_REVIEW).length
  const openMaintenance = maintenance.data.filter((item) => ![7, 9, 10].includes(item.status))
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
      <div><h1>{greeting}, {user.fullName.trim() || 'there'}</h1><p>Track your rental journey, appointments and account updates in one place.</p></div>
      <UpcomingViewing summary={viewings} viewing={nextViewing} property={properties[nextViewing?.propertyId]} />
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
      <SummaryCard title="Next Payment" icon="wallet" summary={nextPayment}>
        {nextPayment.item ? <><strong className="tenant-summary__value tenant-summary__value--money">Rs. {moneyFormatter.format(nextPayment.item.amount)}</strong><p>Due <time dateTime={nextPayment.item.dueDate}>{formatDate(nextPayment.item.dueDate, 'Date unavailable')}</time></p></> : <><strong className="tenant-summary__empty-value">No payment due</strong><p>No unpaid schedule items found</p></>}
      </SummaryCard>
      <SummaryCard title="Open Request" icon="tools" summary={maintenance}>
        <strong className="tenant-summary__value">{openMaintenance.length}</strong>
        <p>{openMaintenance.length === 0 ? 'No open maintenance requests' : `${openMaintenance.length} ${openMaintenance.length === 1 ? 'request' : 'requests'} need attention`}</p>
      </SummaryCard>
      <section className="shared-card tenant-summary tenant-summary--green" aria-label="Lease & Payments">
        <span className="tenant-dashboard__icon"><Icon name="document" size={24} /></span>
        <h2>Lease & Payments</h2>
        <p>Review your offers, leases, rent schedules and payments.</p>
        <Link className="tenant-text-link" to="/modules/lease-payments">Open Lease & Payments <Icon name="arrow" size={18} /></Link>
      </section>
      <Link className="shared-card tenant-summary tenant-summary--amber" to="/modules/maintenance" aria-label="Maintenance">
        <span className="tenant-dashboard__icon"><Icon name="tools" size={24} /></span>
        <h2>Maintenance</h2>
        <p>Request repairs and track their progress.</p>
      </Link>
    </div>

    <div className="tenant-dashboard__middle">
      <RecommendedSection userId={user.id} />
      <div className="tenant-dashboard__side">
        <RecentActivity activity={activity} />
      </div>
    </div>

    <ApplicationsSection summary={applications} applications={sortedApplications} properties={properties} />
  </main>
}
