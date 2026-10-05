import { useContext, useEffect } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { getViewingsByProperty, VIEWING_STATUS } from '../../features/viewings/services/viewingApiService.js'
import { getApplicationsByProperty } from '../../features/rentalApplications/services/rentalApplicationApiService.js'
import RentalApplicationStatusBadge from '../../features/rentalApplications/components/RentalApplicationStatusBadge.jsx'
import usePropertyContext from '../property/usePropertyContext.js'
import { useOwnedPropertySelection, useOwnedProperties } from '../property/useOwnedProperties.js'
import { PageHeader } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import usePropertySummary from './usePropertySummary.js'
import useLandlordRevenue, { monthlyRevenue } from './useLandlordRevenue.js'
import { getPropertyMaintenanceRequests } from '../../features/maintenance/services/maintenanceApiService.js'
import { MAINTENANCE_STATUS } from '../../features/maintenance/services/maintenanceEnums.js'
import useDashboardValidation, { isReviewable, WORKFLOW_STATUS } from './useDashboardValidation.js'
import { PendingViewingsContext } from '../layout/PendingViewingsContext.js'
import { PendingApplicationsContext } from '../layout/PendingApplicationsContext.js'
import './landlord-dashboard.css'

const LOADING_COPY = 'Loading landlord activity...'

async function loadMaintenanceSummary(propertyId) {
  const requests = await getPropertyMaintenanceRequests(propertyId)
  return requests.map((request) => ({ ...request, status: MAINTENANCE_STATUS.byName[request.status] }))
}

function firstName(fullName) {
  return fullName?.trim().split(/\s+/).filter(Boolean)[0] || 'there'
}

function timeBasedGreeting(date = new Date()) {
  const hour = date.getHours()
  if (hour < 12) return 'Good morning'
  if (hour < 17) return 'Good afternoon'
  return 'Good evening'
}

function formattedDashboardDate(date = new Date()) {
  return new Intl.DateTimeFormat(undefined, {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  }).format(date)
}

function pluralized(count, singular, plural = `${singular}s`) {
  return count === 1 ? singular : plural
}

function scopedPath(path, propertyId) {
  return propertyId ? `${path}?${new URLSearchParams({ propertyId })}` : path
}

function SummaryCard({ title, icon, status, value, secondary, to, actionLabel, retry }) {
  const isReady = status === 'ready'
  const needsProperty = status === 'property-required'
  const isError = status === 'error'

  return (
    <section
      className={`shared-card landlord-summary landlord-summary--${icon}${!isReady ? ' landlord-summary--stateful' : ''}`}
      aria-label={title}
      aria-busy={status === 'loading'}
    >
      <span className="landlord-dashboard__icon" aria-hidden="true"><Icon name={icon} size={20} /></span>
      {isReady && <strong className="landlord-summary__value">{value}</strong>}
      {needsProperty && <strong className="landlord-summary__value landlord-summary__value--message">Select a property</strong>}
      {isError && <strong className="landlord-summary__value landlord-summary__value--message">Summary unavailable</strong>}
      <h2>{title}</h2>
      {isReady && <p>{secondary}</p>}
      {needsProperty && <p>Choose a property to {title === 'Applications' ? 'review applications' : 'view pending requests'}.</p>}
      {status === 'loading' && <p className="landlord-summary__loading" role="status">{LOADING_COPY}</p>}
      {isError && (
        <div className="landlord-summary__error" role="alert">
          <p>Something went wrong while loading the latest landlord data.</p>
          <button type="button" className="landlord-dashboard__text-button" onClick={retry}>Try again</button>
        </div>
      )}
      {to && status !== 'loading' && <Link className="landlord-summary__link" to={to} aria-label={actionLabel} />}
    </section>
  )
}

function PropertyFilter({ collection, selectedPropertyId }) {
  const navigate = useNavigate()

  if (!collection || collection.status === 'loading') {
    return (
      <div className="landlord-property-filter landlord-property-filter--state" aria-busy="true">
        <span className="landlord-dashboard__spinner" aria-hidden="true" />
        <span role="status">Loading properties...</span>
      </div>
    )
  }

  if (collection.status === 'error') {
    return (
      <div className="landlord-property-filter landlord-property-filter--state" role="alert">
        <span>Properties unavailable</span>
        <button type="button" className="landlord-dashboard__text-button" onClick={collection.retry}>Try again</button>
      </div>
    )
  }

  if (collection.properties.length === 0) {
    return (
      <Link className="landlord-property-filter landlord-property-filter--empty" to="/properties/new">
        <Icon name="building" size={16} />
        Add your first property
      </Link>
    )
  }

  return (
    <div className="landlord-property-filter">
      <Icon name="building" size={16} />
      <label>
        <span>Filter by property</span>
        <select
          aria-label="Filter dashboard by property"
          value={selectedPropertyId || ''}
          onChange={(event) => navigate(event.target.value
            ? `/dashboard?${new URLSearchParams({ propertyId: event.target.value })}`
            : '/dashboard')}
        >
          <option value="">All properties</option>
          {collection.properties.map((property) => (
            <option key={property.id} value={property.id}>{property.title}</option>
          ))}
        </select>
      </label>
    </div>
  )
}

function AttentionRow({ icon, title, description, to, action }) {
  return (
    <li className="landlord-attention__row">
      <span className={`landlord-dashboard__icon landlord-dashboard__icon--${icon}`} aria-hidden="true"><Icon name={icon} size={18} /></span>
      <div><h3>{title}</h3><p>{description}</p></div>
      <Link className="shared-button shared-button--outline" to={to}>{action}<Icon name="arrow" size={14} /></Link>
    </li>
  )
}

function InlineError({ retry }) {
  return (
    <div className="landlord-section-state landlord-section-state--error" role="alert">
      <span className="landlord-dashboard__icon" aria-hidden="true"><Icon name="alert" size={19} /></span>
      <div><h3>We couldn't load this section</h3><p>Something went wrong while loading the latest landlord data.</p></div>
      {retry && <button type="button" className="shared-button shared-button--outline" onClick={retry}>Try again</button>}
    </div>
  )
}

function SectionState({ title, description, icon = 'info', loading = false }) {
  return (
    <div className="landlord-section-state" role={loading ? 'status' : undefined}>
      <span className="landlord-dashboard__icon" aria-hidden="true">{loading ? <span className="landlord-dashboard__spinner" /> : <Icon name={icon} size={19} />}</span>
      <div><h3>{title}</h3><p>{description}</p></div>
    </div>
  )
}

function NeedsAttention({ applications, viewings, validation, selectedProperty, selectedPropertyId, properties }) {
  const reviewableApplications = applications.data.filter(isReviewable).length
  const pendingViewings = viewings.data.filter((item) => item.status === VIEWING_STATUS.PENDING).length
  const awaitingAiReview = validation.attention.filter((item) => item.status === WORKFLOW_STATUS.AWAITING_HUMAN_REVIEW).length
  const hasActions = reviewableApplications + pendingViewings + awaitingAiReview > 0
  const retryFailed = () => {
    if (applications.status === 'error') applications.retry()
    if (viewings.status === 'error') viewings.retry()
  }
  const scopeDescription = selectedProperty ? selectedProperty.title : 'all properties'

  let content
  if ([applications.status, viewings.status].includes('error')) {
    content = <InlineError retry={retryFailed} />
  } else if ([applications.status, viewings.status, validation.status].includes('loading')) {
    content = <SectionState title={LOADING_COPY} description={`Checking current activity for ${scopeDescription}.`} loading />
  } else if (!hasActions) {
    content = <SectionState title="You're all caught up" description={`No urgent landlord actions for ${scopeDescription} right now.`} icon="shield" />
  } else {
    content = (
      <ul className="landlord-attention__list">
        {reviewableApplications > 0 && (
          <AttentionRow
            icon="document"
            title={`${reviewableApplications} ${pluralized(reviewableApplications, 'application')} awaiting review`}
            description={`Review submitted applications for ${scopeDescription}.`}
            to={scopedPath('/rental-applications', selectedPropertyId)}
            action="Review"
          />
        )}
        {pendingViewings > 0 && (
          <AttentionRow
            icon="calendar"
            title={`${pendingViewings} viewing ${pluralized(pendingViewings, 'request')} pending approval`}
            description="Respond to requested viewing appointments."
            to={scopedPath('/viewing-requests', selectedPropertyId)}
            action="Review"
          />
        )}
        {awaitingAiReview > 0 && (
          <AttentionRow
            icon="search"
            title="AI validation requires human review"
            description="Review validation findings before making the final landlord decision."
            to={scopedPath('/ai-review', selectedPropertyId)}
            action="Open AI Review"
          />
        )}
        {validation.status === 'partial' && (
          <li className="landlord-attention__notice" role="status">Some AI validation activity could not be checked. Open AI Review for the latest available details.</li>
        )}
      </ul>
    )
  }

  return (
    <section className="landlord-attention" aria-labelledby="landlord-attention-title">
      <div className="landlord-dashboard__section-heading">
        <h2 id="landlord-attention-title">Needs Attention</h2>
        <PropertyFilter collection={properties} selectedPropertyId={selectedPropertyId} />
      </div>
      <div className="shared-card landlord-attention__card">{content}</div>
    </section>
  )
}

function applicationDate(application) {
  return [application.submittedAt, application.createdAt].find((value) =>
    typeof value === 'string' && Number.isFinite(Date.parse(value))) || null
}

function applicantLabel(application) {
  return typeof application.tenantId === 'string' && application.tenantId.trim()
    ? application.tenantId.trim()
    : application.id
}

function formatCurrency(value) {
  const amount = Number(value)
  return Number.isFinite(amount) && amount >= 0 ? `Rs. ${amount.toLocaleString()}` : 'Not provided'
}

function RecentApplications({ applications, validation, selectedProperty, selectedPropertyId, properties }) {
  const recent = [...applications.data]
    .sort((a, b) => (Date.parse(applicationDate(b)) || 0) - (Date.parse(applicationDate(a)) || 0))
    .slice(0, 5)
  const aiReadyIds = new Set(validation.attention
    .filter((item) => item.status === WORKFLOW_STATUS.AWAITING_HUMAN_REVIEW)
    .map((item) => item.applicationId))
  const propertyTitles = new Map(
    (properties?.status === 'ready' ? properties.properties : [])
      .map((property) => [property.id.toLowerCase(), property.title]),
  )

  let content
  if (applications.status === 'loading') {
    content = <SectionState title={LOADING_COPY} description={`Checking recent applications for ${selectedProperty?.title || 'all properties'}.`} loading />
  } else if (applications.status === 'error') {
    content = <InlineError retry={applications.retry} />
  } else if (recent.length === 0) {
    content = <SectionState title="No applications yet" description={`Rental applications for ${selectedProperty?.title || 'your properties'} will appear here.`} icon="document" />
  } else {
    content = (
      <div className="landlord-recent__table-wrap">
        <table>
          <thead><tr><th scope="col">Applicant / Reference</th><th scope="col">Property</th><th scope="col">Monthly Income</th><th scope="col">Status</th><th scope="col">Action</th></tr></thead>
          <tbody>{recent.map((application) => {
            const label = applicantLabel(application)
            const aiReady = aiReadyIds.has(application.id)
            const applicationPropertyId = application.propertyId
            const propertyTitle = propertyTitles.get(applicationPropertyId.toLowerCase()) || selectedProperty?.title || 'Property'
            const to = `/properties/${encodeURIComponent(applicationPropertyId)}/rental-applications/${encodeURIComponent(application.id)}/validation`
            return (
              <tr key={application.id}>
                <th scope="row">
                  <span className="landlord-recent__applicant-mark" aria-hidden="true">{label.charAt(0).toLocaleUpperCase() || 'T'}</span>
                  <span className="landlord-recent__applicant" title={label}><span>Tenant reference</span><code>{label}</code></span>
                </th>
                <td>{propertyTitle}</td>
                <td>{formatCurrency(application.monthlyIncome)}</td>
                <td><RentalApplicationStatusBadge status={application.status} /></td>
                <td><Link aria-label={`${aiReady ? 'AI Review' : 'Review'} application ${application.id}`} to={to}>{aiReady ? 'AI Review' : 'Review'}<Icon name="arrow" size={14} /></Link></td>
              </tr>
            )
          })}</tbody>
        </table>
      </div>
    )
  }

  return (
    <section className="landlord-recent" aria-labelledby="landlord-recent-title">
      <div className="landlord-dashboard__section-heading">
        <div><h2 id="landlord-recent-title">Recent Applications</h2><p>Showing applications for {selectedProperty?.title || 'all properties'}</p></div>
        <Link to={scopedPath('/rental-applications', selectedPropertyId)}>View all <Icon name="arrow" size={14} /></Link>
      </div>
      <div className="shared-card landlord-recent__card">{content}</div>
    </section>
  )
}

function PortfolioOverview({ collection }) {
  const properties = collection?.status === 'ready' ? collection.properties : []
  const total = properties.length
  const available = properties.filter((property) => property.isAvailable).length
  const unavailable = total - available
  const rents = properties.map((property) => Number(property.monthlyRent))
  const hasAverageRent = rents.length > 0 && rents.every((rent) => Number.isFinite(rent) && rent > 0)
  const averageRent = hasAverageRent ? rents.reduce((sum, rent) => sum + rent, 0) / rents.length : null

  return (
    <section className="shared-card landlord-portfolio" aria-labelledby="landlord-portfolio-title">
      <div className="landlord-dashboard__section-heading"><h2 id="landlord-portfolio-title">Portfolio Overview</h2></div>
      {!collection || collection.status === 'loading' ? (
        <SectionState title={LOADING_COPY} description="Checking your owned properties." loading />
      ) : collection.status === 'error' ? (
        <InlineError retry={collection.retry} />
      ) : (
        <dl className="landlord-portfolio__metrics">
          <div>
            <dt><span>Available properties</span><strong>{available} / {total}</strong></dt>
            <dd><span className="landlord-portfolio__track"><span style={{ width: `${total ? (available / total) * 100 : 0}%` }} /></span></dd>
          </div>
          <div>
            <dt><span>Unavailable properties</span><strong>{unavailable} / {total}</strong></dt>
            <dd><span className="landlord-portfolio__track landlord-portfolio__track--muted"><span style={{ width: `${total ? (unavailable / total) * 100 : 0}%` }} /></span></dd>
          </div>
          {hasAverageRent && (
            <div className="landlord-portfolio__average">
              <dt>Average monthly rent</dt>
              <dd>{formatCurrency(Math.round(averageRent))}</dd>
            </div>
          )}
        </dl>
      )}
    </section>
  )
}

function MaintenanceCard({ maintenance, selectedPropertyId }) {
  const open = maintenance.data.filter((request) => ![9, 10].includes(request.status)).length
  const awaitingApproval = maintenance.data.filter((request) => request.status === 5).length
  return (
    <section className="shared-card landlord-maintenance" aria-labelledby="landlord-maintenance-title">
      <div className="landlord-maintenance__heading">
        <h2 id="landlord-maintenance-title">Maintenance</h2>
        <Link to={selectedPropertyId ? `/properties/${encodeURIComponent(selectedPropertyId)}/maintenance` : '/modules/maintenance/landlord'}>View all <Icon name="arrow" size={14} /></Link>
      </div>
      <div className="landlord-maintenance__body">
        {maintenance.status === 'loading' ? <SectionState title="Loading maintenance..." description="Checking requests for your properties." loading />
          : maintenance.status === 'error' ? <InlineError retry={maintenance.retry} />
            : <SectionState icon="tools" title={open ? `${open} open ${pluralized(open, 'request')}` : 'No open maintenance requests'}
              description={awaitingApproval ? `${awaitingApproval} awaiting your approval` : 'No estimates awaiting your approval.'} />}
      </div>
    </section>
  )
}

export default function LandlordDashboard({ user }) {
  const { propertyId } = usePropertyContext()
  return <LandlordOverview key={propertyId || 'all-properties'} user={user} propertyId={propertyId} />
}

function LandlordOverview({ user, propertyId }) {
  const publishPendingViewings = useContext(PendingViewingsContext)
  const publishPendingApplications = useContext(PendingApplicationsContext)
  const ownedProperties = useOwnedProperties()
  const selection = useOwnedPropertySelection(propertyId)
  const selectedPropertyId = selection.status === 'selected' ? propertyId : null
  const selectedProperty = selection.status === 'selected' ? selection.property : null
  const summaryPropertyIds = ownedProperties?.status === 'ready'
    ? selectedPropertyId
      ? [selectedPropertyId]
      : ownedProperties.properties.map((property) => property.id)
    : null
  const viewings = usePropertySummary(getViewingsByProperty, summaryPropertyIds)
  const applications = usePropertySummary(getApplicationsByProperty, summaryPropertyIds)
  const maintenance = usePropertySummary(loadMaintenanceSummary, summaryPropertyIds)
  const revenue = useLandlordRevenue(summaryPropertyIds)
  const validation = useDashboardValidation(applications)
  const pendingViewings = viewings.data.filter((item) => item.status === VIEWING_STATUS.PENDING).length
  const reviewableApplications = applications.data.filter(isReviewable).length
  const availableProperties = ownedProperties?.status === 'ready'
    ? ownedProperties.properties.filter((property) => property.isAvailable).length
    : 0
  const now = new Date()

  useEffect(() => {
    publishPendingViewings?.(selectedPropertyId, viewings.status === 'ready' ? pendingViewings : null)
  }, [selectedPropertyId, viewings.status, pendingViewings, publishPendingViewings])

  useEffect(() => {
    publishPendingApplications?.(selectedPropertyId, applications.status === 'ready' ? reviewableApplications : null)
  }, [selectedPropertyId, applications.status, reviewableApplications, publishPendingApplications])

  return (
    <main className="shared-page landlord-dashboard">
      <PageHeader title={`${timeBasedGreeting(now)}, ${firstName(user.fullName)}`}>
        <p className="landlord-dashboard__date">{formattedDashboardDate(now)}</p>
        <p>Here&apos;s what&apos;s happening across your rental portfolio today.</p>
      </PageHeader>

      <div className="landlord-dashboard__summaries">
        <SummaryCard
          title="Active Properties"
          icon="building"
          status={ownedProperties?.status || 'loading'}
          value={availableProperties}
          secondary={ownedProperties?.properties.length
            ? `${ownedProperties.properties.length} total properties`
            : 'No properties yet'}
          to="/modules/manage-properties"
          actionLabel="Manage Properties"
          retry={ownedProperties?.retry}
        />
        <SummaryCard
          title="Pending Viewings"
          icon="calendar"
          status={viewings.status}
          value={pendingViewings}
          secondary={selectedProperty ? `For ${selectedProperty.title}` : 'Across all properties'}
          to={scopedPath('/viewing-requests', selectedPropertyId)}
          actionLabel="View Viewing Requests"
          retry={viewings.retry}
        />
        <SummaryCard
          title="Applications"
          icon="document"
          status={applications.status}
          value={applications.data.length}
          secondary={reviewableApplications > 0
            ? `${reviewableApplications} awaiting review`
            : selectedProperty ? `For ${selectedProperty.title}` : 'Across all properties'}
          to={scopedPath('/rental-applications', selectedPropertyId)}
          actionLabel="View Rental Applications"
          retry={applications.retry}
        />
        <SummaryCard title="Revenue This Month" icon="trend" status={revenue.status}
          value={formatCurrency(monthlyRevenue(revenue.data))}
          secondary={`Completed rent payments · ${selectedProperty ? selectedProperty.title : 'All properties'}`}
          to="/modules/payments" actionLabel="View Payments" retry={revenue.retry} />
      </div>

      <div className="landlord-dashboard__content">
        <div className="landlord-dashboard__primary">
          <NeedsAttention
            applications={applications}
            viewings={viewings}
            validation={validation}
            selectedProperty={selectedProperty}
            selectedPropertyId={selectedPropertyId}
            properties={ownedProperties}
          />
          <RecentApplications
            applications={applications}
            validation={validation}
            selectedProperty={selectedProperty}
            selectedPropertyId={selectedPropertyId}
            properties={ownedProperties}
          />
        </div>
        <aside className="landlord-dashboard__aside" aria-label="Portfolio details">
          <PortfolioOverview collection={ownedProperties} />
          <MaintenanceCard maintenance={maintenance} selectedPropertyId={selectedPropertyId} />
        </aside>
      </div>
    </main>
  )
}
