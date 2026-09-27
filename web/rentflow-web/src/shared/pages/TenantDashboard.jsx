import { Link } from 'react-router-dom'
import { getMyApplications, RENTAL_APPLICATION_STATUS } from '../../features/rentalApplications/services/rentalApplicationApiService.js'
import { getMyViewings, VIEWING_STATUS } from '../../features/viewings/services/viewingApiService.js'
import { navigationItemForPath } from '../navigation/roleNavigation.js'
import { AppCard, StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import useTenantSummary from './useTenantSummary.js'
import './tenant-dashboard.css'

function SummaryCard({ title, icon, tone, summary, children }) {
  return <section className={`shared-card tenant-summary tenant-summary--${tone}`} aria-label={title} aria-busy={summary.status === 'loading'}>
    <span className="tenant-dashboard__icon"><Icon name={icon} size={24} /></span>
    <h2>{title}</h2>
    {summary.status === 'loading' && <p role="status">Loading summary…</p>}
    {summary.status === 'error' && <div role="alert"><p>{summary.message || 'Unable to load this summary.'}</p><button className="tenant-retry" type="button" onClick={summary.retry}>Retry {title.toLowerCase()}</button></div>}
    {summary.status === 'ready' && children}
  </section>
}

function PendingCard({ title, icon, tone, children }) {
  return <section className={`shared-card tenant-summary tenant-summary--${tone}`} aria-label={title}>
    <span className="tenant-dashboard__icon"><Icon name={icon} size={24} /></span>
    <h2>{title}</h2>
    <StatusBadge tone="warning">Integration pending</StatusBadge>
    <p>{children}</p>
  </section>
}

export default function TenantDashboard({ user }) {
  const applications = useTenantSummary(getMyApplications)
  const viewings = useTenantSummary(getMyViewings)
  const underReview = applications.data.filter((item) => item.status === RENTAL_APPLICATION_STATUS.UNDER_REVIEW).length
  const changesRequested = applications.data.filter((item) => item.status === RENTAL_APPLICATION_STATUS.CHANGES_REQUESTED).length
  // A requested time is only confirmed once approved. Past and cancelled
  // appointments must never inflate the upcoming count.
  const now = viewings.loadedAt
  const upcoming = viewings.data.filter((item) => item.status === VIEWING_STATUS.APPROVED && Date.parse(item.requestedDateTime) > now)
    .sort((a, b) => Date.parse(a.requestedDateTime) - Date.parse(b.requestedDateTime))
  const pendingViewings = viewings.data.filter((item) => item.status === VIEWING_STATUS.PENDING).length
  const nextViewing = upcoming[0]
  const quickActions = ['/modules/my-viewings', '/modules/my-applications'].map((path) => navigationItemForPath(user.role, path))

  return <main className="shared-page tenant-dashboard">
    <header className="tenant-dashboard__greeting">
      <div><p className="tenant-dashboard__eyebrow">Your rental journey</p><h1>Welcome, {user.fullName.trim() || 'there'}</h1><p>Keep track of your applications and plan your next viewing.</p></div>
      <Link className="shared-button" to="/modules/properties">Property availability <Icon name="arrow" size={18} /></Link>
    </header>

    <div className="tenant-dashboard__summaries">
      <SummaryCard title="Applications" icon="document" tone="olive" summary={applications}>
        <strong className="tenant-summary__value">{applications.data.length}</strong>
        {applications.data.length === 0 ? <p>No applications yet.</p> : <p>{underReview} under review<br />{changesRequested} requesting changes</p>}
      </SummaryCard>
      <SummaryCard title="Upcoming viewings" icon="calendar" tone="violet" summary={viewings}>
        <strong className="tenant-summary__value">{upcoming.length}</strong>
        {nextViewing ? <p>Next confirmed viewing<br /><time dateTime={nextViewing.requestedDateTime}>{new Date(nextViewing.requestedDateTime).toLocaleString(undefined, { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit', timeZoneName: 'short' })}</time></p> : <p>{viewings.data.length === 0 ? 'No viewings yet.' : 'No upcoming confirmed viewings.'}</p>}
        {pendingViewings > 0 && <p>{pendingViewings} awaiting confirmation</p>}
      </SummaryCard>
      <section className="shared-card tenant-summary tenant-summary--green" aria-label="Lease & Payments">
        <span className="tenant-dashboard__icon"><Icon name="document" size={24} /></span>
        <h2>Lease & Payments</h2>
        <p>Review your offers, leases, rent schedules and payments.</p>
        <Link className="tenant-text-link" to="/modules/lease-payments">Open Lease & Payments <Icon name="arrow" size={18} /></Link>
      </section>
      <PendingCard title="Maintenance" icon="tools" tone="amber">Request repairs and track their progress once this feature is available.</PendingCard>
    </div>

    <div className="tenant-dashboard__lower">
      <section aria-labelledby="tenant-properties-title">
        <h2 id="tenant-properties-title">Find your next home</h2>
        <AppCard className="tenant-properties">
          <span className="tenant-properties__illustration" aria-hidden="true"><Icon name="building" size={48} /></span>
          <StatusBadge tone="warning">Integration pending</StatusBadge>
          <h3>A place for your next chapter</h3>
          <p>Property browsing and recommendations will appear here when the property feature is available.</p>
          <Link className="tenant-text-link" to="/modules/properties">Property availability <Icon name="arrow" size={18} /></Link>
        </AppCard>
      </section>
      <section aria-labelledby="tenant-actions-title">
        <h2 id="tenant-actions-title">Quick actions</h2>
        <AppCard className="tenant-actions">
          {quickActions.map((item) => <Link key={item.id} className="tenant-action" to={item.path}>
            <span className="tenant-dashboard__icon"><Icon name={item.id === 'my-viewings' ? 'calendar' : 'document'} size={22} /></span>
            <span><strong>{item.label}</strong><small>{item.available ? 'Open your workspace' : 'Web integration pending · Available in the mobile app'}</small></span>
            <Icon name="arrow" size={18} />
          </Link>)}
          <p className="tenant-actions__note">Summaries are loaded from your account when you open this dashboard.</p>
        </AppCard>
      </section>
    </div>
  </main>
}
