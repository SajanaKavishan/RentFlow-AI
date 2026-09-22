import { Link } from 'react-router-dom'
import { getViewingsByProperty, VIEWING_STATUS } from '../../features/viewings/services/viewingApiService.js'
import { getApplicationsByProperty, RENTAL_APPLICATION_STATUS } from '../../features/rentalApplications/services/rentalApplicationApiService.js'
import PropertySelectionState from '../property/PropertySelectionState.jsx'
import usePropertyContext from '../property/usePropertyContext.js'
import { AppCard, PageHeader, StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import usePropertySummary from './usePropertySummary.js'
import './landlord-dashboard.css'

function SummaryCard({ title, icon, summary, to, children }) {
  return (
    <section className="shared-card landlord-summary" aria-label={title} aria-busy={summary.status === 'loading'}>
      <div className="landlord-summary__heading">
        <span className="landlord-dashboard__icon"><Icon name={icon} size={24} /></span>
        <h2>{title}</h2>
      </div>
      {summary.status === 'property-required' && <div className="landlord-summary__state">
        <StatusBadge tone="warning">Property required</StatusBadge>
        <p>Select a property to see this summary.</p>
      </div>}
      {summary.status === 'loading' && <p className="landlord-summary__state" role="status">Loading summary…</p>}
      {summary.status === 'error' && <div className="landlord-summary__state" role="alert">
        <p>{summary.message}</p>
        <button type="button" className="shared-button shared-button--outline" onClick={summary.retry}>Retry {title.toLowerCase()}</button>
      </div>}
      {summary.status === 'ready' && children}
      <Link className="landlord-summary__link" to={to}>Open {title}<Icon name="arrow" size={18} /></Link>
    </section>
  )
}

export default function LandlordDashboard({ user }) {
  const { propertyId } = usePropertyContext()
  return <LandlordOverview key={propertyId || 'property-required'} user={user} propertyId={propertyId} />
}

function LandlordOverview({ user, propertyId }) {
  const viewings = usePropertySummary(getViewingsByProperty, propertyId)
  const applications = usePropertySummary(getApplicationsByProperty, propertyId)
  const scopedPath = (path) => propertyId ? `${path}?${new URLSearchParams({ propertyId })}` : path
  const pendingViewings = viewings.data.filter((item) => item.status === VIEWING_STATUS.PENDING).length
  const applicationCounts = [
    { label: 'Submitted', status: RENTAL_APPLICATION_STATUS.SUBMITTED },
    { label: 'Under review', status: RENTAL_APPLICATION_STATUS.UNDER_REVIEW },
    { label: 'Changes requested', status: RENTAL_APPLICATION_STATUS.CHANGES_REQUESTED },
  ].map((entry) => ({ ...entry, count: applications.data.filter((item) => item.status === entry.status).length }))

  return (
    <main className="shared-page landlord-dashboard">
      <PageHeader title={`Welcome, ${user.fullName.trim() || 'there'}`}>
        <p>Review requests, follow up on applications and keep your property moving.</p>
      </PageHeader>

      {propertyId ? <section className="landlord-dashboard__context" aria-label="Property context">
        <span className="landlord-dashboard__icon"><Icon name="building" size={24} /></span>
        <div><h2>Selected property</h2><p>Activity below is scoped to this property.</p><code>{propertyId}</code></div>
      </section> : <PropertySelectionState className="landlord-dashboard__context landlord-dashboard__selection" />}

      <div className="landlord-dashboard__summaries">
        <SummaryCard title="Viewing Requests" icon="calendar" summary={viewings} to={scopedPath('/viewing-requests')}>
          <p className="landlord-summary__total"><strong>{viewings.data.length}</strong><span>Total requests</span></p>
          {viewings.data.length === 0 ? <p>No viewing requests for this property yet.</p> : <dl className="landlord-summary__counts">
            <div><dt>Pending response</dt><dd>{pendingViewings}</dd></div>
          </dl>}
        </SummaryCard>
        <SummaryCard title="Rental Applications" icon="document" summary={applications} to={scopedPath('/rental-applications')}>
          <p className="landlord-summary__total"><strong>{applications.data.length}</strong><span>Total applications</span></p>
          {applications.data.length === 0 ? <p>No rental applications for this property yet.</p> : <dl className="landlord-summary__counts">
            {applicationCounts.map((entry) => <div key={entry.status}><dt>{entry.label}</dt><dd>{entry.count}</dd></div>)}
          </dl>}
        </SummaryCard>
      </div>
      {propertyId && <p className="landlord-dashboard__note">Summaries load when you open this dashboard. Open a workspace to review the latest records.</p>}

      <section className="landlord-dashboard__ai" aria-labelledby="landlord-ai-title">
        <AppCard className="landlord-dashboard__ai-card">
          <span className="landlord-dashboard__icon"><Icon name="search" size={24} /></span>
          <div><h2 id="landlord-ai-title">AI Review</h2><p>Review application validation findings and documents before making your decision.</p></div>
          <Link className="shared-button" to={scopedPath('/ai-review')}>Open AI Review <Icon name="arrow" size={18} /></Link>
        </AppCard>
      </section>
    </main>
  )
}
