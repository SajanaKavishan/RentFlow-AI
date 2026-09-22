import { Link } from 'react-router-dom'
import { getViewingsByProperty, VIEWING_STATUS } from '../../features/viewings/services/viewingApiService.js'
import { getApplicationsByProperty, RENTAL_APPLICATION_STATUS } from '../../features/rentalApplications/services/rentalApplicationApiService.js'
import PropertySelectionState from '../property/PropertySelectionState.jsx'
import usePropertyContext from '../property/usePropertyContext.js'
import { AppCard, PageHeader } from '../ui/States.jsx'
import RentalApplicationStatusBadge from '../../features/rentalApplications/components/RentalApplicationStatusBadge.jsx'
import Icon from '../ui/Icons.jsx'
import usePropertySummary from './usePropertySummary.js'
import useDashboardValidation, { isReviewable, WORKFLOW_STATUS } from './useDashboardValidation.js'
import './landlord-dashboard.css'

function SummaryCard({ title, icon, summary, to, children }) {
  return (
    <section className="shared-card landlord-summary" aria-label={title} aria-busy={summary.status === 'loading'}>
      <div className="landlord-summary__heading">
        <span className="landlord-dashboard__icon"><Icon name={icon} size={24} /></span>
        <h2>{title}</h2>
      </div>
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

function AttentionRow({ icon, title, description, to, action }) {
  return <li className="landlord-attention__row">
    <span className="landlord-dashboard__icon"><Icon name={icon} size={20} /></span>
    <div><h3>{title}</h3><p>{description}</p></div>
    <Link className="shared-button shared-button--outline" to={to}>{action}<Icon name="arrow" size={16} /></Link>
  </li>
}

function applicationDate(application) {
  return [application.submittedAt, application.createdAt].find((value) =>
    typeof value === 'string' && Number.isFinite(Date.parse(value))) || null
}

function RecentApplications({ applications, scopedPath }) {
  const recent = [...applications].sort((a, b) => (Date.parse(applicationDate(b)) || 0) - (Date.parse(applicationDate(a)) || 0)).slice(0, 5)
  return <section className="landlord-recent" aria-labelledby="landlord-recent-title">
    <div className="landlord-dashboard__section-heading"><h2 id="landlord-recent-title">Recent Applications</h2><Link to={scopedPath('/rental-applications')}>View all applications <Icon name="arrow" size={16} /></Link></div>
    <div className="shared-card landlord-recent__card">
      <table>
        <caption className="landlord-recent__caption">Latest applications by submitted or created date</caption>
        <thead><tr><th scope="col">Application</th><th scope="col">Received</th><th scope="col">Status</th><th scope="col">Details</th></tr></thead>
        <tbody>{recent.map((application) => {
          const date = applicationDate(application)
          return <tr key={application.id}>
            <th scope="row"><span className="landlord-recent__reference" title={application.id}>{application.id}</span></th>
            <td>{date ? <time dateTime={date}>{new Date(date).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })}</time> : 'Date unavailable'}</td>
            <td><RentalApplicationStatusBadge status={application.status} /></td>
            <td><Link aria-label={`Open application ${application.id}`} to={scopedPath(`/notifications/rental-application/${encodeURIComponent(application.id)}`)}>Open <Icon name="arrow" size={16} /></Link></td>
          </tr>
        })}</tbody>
      </table>
    </div>
  </section>
}

export default function LandlordDashboard({ user }) {
  const { propertyId } = usePropertyContext()
  return <LandlordOverview key={propertyId || 'property-required'} user={user} propertyId={propertyId} />
}

function LandlordOverview({ user, propertyId }) {
  const viewings = usePropertySummary(getViewingsByProperty, propertyId)
  const applications = usePropertySummary(getApplicationsByProperty, propertyId)
  const validation = useDashboardValidation(applications)
  const scopedPath = (path) => propertyId ? `${path}?${new URLSearchParams({ propertyId })}` : path
  const pendingViewings = viewings.data.filter((item) => item.status === VIEWING_STATUS.PENDING).length
  const reviewableApplications = applications.data.filter(isReviewable).length
  const awaitingReview = validation.attention.filter((item) => item.status === WORKFLOW_STATUS.AWAITING_HUMAN_REVIEW).length
  const failedWorkflows = validation.attention.filter((item) => item.status === WORKFLOW_STATUS.FAILED).length
  const hasAttention = pendingViewings + reviewableApplications + validation.attention.length > 0
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
        <div><h2>Selected property</h2><code>{propertyId}</code></div>
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

      {hasAttention && <section className="landlord-attention" aria-labelledby="landlord-attention-title">
        <div className="landlord-dashboard__section-heading"><h2 id="landlord-attention-title">Needs Attention</h2><span>For this property</span></div>
        <ul className="shared-card landlord-attention__list">
          {reviewableApplications > 0 && <AttentionRow icon="document" title={`${reviewableApplications} ${reviewableApplications === 1 ? 'application ready' : 'applications ready'} for review`} description="Submitted or under review. Your decision is required." to={scopedPath('/rental-applications')} action="Review applications" />}
          {pendingViewings > 0 && <AttentionRow icon="calendar" title={`${pendingViewings} pending viewing ${pendingViewings === 1 ? 'request' : 'requests'}`} description="Review the requested times and respond to tenants." to={scopedPath('/viewing-requests')} action="Review viewings" />}
          {validation.status === 'partial' && <li className="landlord-attention__notice" role="status">Some AI workflows could not be checked. AI counts include only confirmed results.</li>}
          {awaitingReview > 0 && <AttentionRow icon="search" title={`${awaitingReview} AI ${awaitingReview === 1 ? 'workflow awaits' : 'workflows await'} human review`} description="Review validation findings before making a decision." to={scopedPath('/ai-review')} action="Review AI findings" />}
          {failedWorkflows > 0 && <AttentionRow icon="alert" title={`${failedWorkflows} AI ${failedWorkflows === 1 ? 'workflow needs' : 'workflows need'} a retry`} description="The latest validation run reported a failure." to={scopedPath('/ai-review')} action="Open validation" />}
        </ul>
      </section>}

      {applications.status === 'ready' && applications.data.length > 0 && <RecentApplications applications={applications.data} scopedPath={scopedPath} />}

      <section className="landlord-dashboard__ai" aria-labelledby="landlord-ai-title">
        <AppCard className="landlord-dashboard__ai-card">
          <span className="landlord-dashboard__icon"><Icon name="search" size={24} /></span>
          <div><h2 id="landlord-ai-title">AI Review</h2><p>Review application validation findings and documents before making your decision.</p>
            {propertyId && validation.status === 'loading' && <p role="status">Checking AI workflows for reviewable applications…</p>}
            {propertyId && ['error', 'partial'].includes(validation.status) && <p className="landlord-dashboard__ai-unavailable">AI summary unavailable or incomplete. Open AI Review to check the latest findings.</p>}
          </div>
          <Link className="shared-button" to={scopedPath('/ai-review')}>Open AI Review <Icon name="arrow" size={18} /></Link>
        </AppCard>
      </section>
    </main>
  )
}
