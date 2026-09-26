import { useEffect, useState } from 'react'
import { useLocation } from 'react-router-dom'
import PropertySelectionState from '../../../shared/property/PropertySelectionState.jsx'
import usePropertyContext from '../../../shared/property/usePropertyContext.js'
import { useOwnedPropertySelection } from '../../../shared/property/useOwnedProperties.js'
import Icon from '../../../shared/ui/Icons.jsx'
import { APPLICATION_STATUS_DETAILS } from '../components/applicationStatus.js'
import RentalApplicationListCard from '../components/RentalApplicationListCard.jsx'
import {
  approveApplication,
  getApplicationsByProperty,
  markUnderReview,
  rejectApplication,
  RENTAL_APPLICATION_STATUS,
  RentalApplicationApiError,
  requestChanges,
} from '../services/rentalApplicationApiService.js'
import '../rentalApplications.css'
import './rental-application-management.css'

const STATUS_PRIORITY = {
  [RENTAL_APPLICATION_STATUS.SUBMITTED]: 0,
  [RENTAL_APPLICATION_STATUS.UNDER_REVIEW]: 1,
  [RENTAL_APPLICATION_STATUS.CHANGES_REQUESTED]: 2,
}

function safeErrorMessage(error, fallback) {
  return error instanceof RentalApplicationApiError ? error.message : fallback
}

function sortApplications(applications) {
  return [...applications].sort((left, right) => {
    const leftPriority = STATUS_PRIORITY[left.status] ?? 3
    const rightPriority = STATUS_PRIORITY[right.status] ?? 3
    if (leftPriority !== rightPriority) return leftPriority - rightPriority

    const leftDate = Date.parse(left.submittedAt || left.createdAt || '') || 0
    const rightDate = Date.parse(right.submittedAt || right.createdAt || '') || 0
    return rightDate - leftDate
  })
}

const FILTER_STATUSES = [
  ['All', 'all'],
  ...Object.entries(APPLICATION_STATUS_DETAILS)
    .filter(([status]) => Number(status) !== RENTAL_APPLICATION_STATUS.DRAFT)
    .map(([status, details]) => [details.label, status]),
  [APPLICATION_STATUS_DETAILS[RENTAL_APPLICATION_STATUS.DRAFT].label, String(RENTAL_APPLICATION_STATUS.DRAFT)],
]

function verifyPropertyApplications(applications, propertyId) {
  if (!Array.isArray(applications) || applications.some((application) =>
    !application || typeof application.id !== 'string' || !application.id.trim()
    || typeof application.tenantId !== 'string' || !application.tenantId.trim()
    || typeof application.propertyId !== 'string'
    || application.propertyId.toLowerCase() !== propertyId.toLowerCase()
    || !Object.hasOwn(APPLICATION_STATUS_DETAILS, application.status)
  )) throw new TypeError('Invalid property application response')
  return sortApplications(applications)
}

function RentalApplicationsPage() {
  const { propertyId } = usePropertyContext()
  const selection = useOwnedPropertySelection(propertyId)
  const { pathname } = useLocation()
  const isAiReviewRoute = pathname === '/ai-review' || /\/ai-review\/?$/.test(pathname)
  const [pageState, setPageState] = useState({
    status: 'loading',
    propertyId: null,
    applications: [],
    error: '',
  })
  const [updatingId, setUpdatingId] = useState(null)
  const [actionError, setActionError] = useState({ id: null, message: '' })
  const [notice, setNotice] = useState({ propertyId: null, message: '' })
  const [reloadKey, setReloadKey] = useState(0)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const pageStatus = selection.status !== 'selected'
    ? 'property-context'
    : pageState.propertyId === propertyId
      ? pageState.status
      : 'loading'

  useEffect(() => {
    if (!propertyId || selection.status !== 'selected') return undefined

    let isActive = true

    getApplicationsByProperty(propertyId)
      .then((applications) => {
        if (isActive) {
          setPageState({
            status: 'success',
            propertyId,
            applications: verifyPropertyApplications(applications, propertyId),
            error: '',
          })
        }
      })
      .catch((error) => {
        if (!isActive) return
        setPageState({
          status: 'error',
          propertyId,
          applications: [],
          error: safeErrorMessage(
            error,
            'Unable to load rental applications. Please try again.',
          ),
        })
      })

    return () => {
      isActive = false
    }
  }, [propertyId, reloadKey, selection.status])

  function loadApplications() {
    if (!propertyId || selection.status !== 'selected' || pageStatus === 'loading') return

    setPageState((current) => ({
      ...current,
      status: 'loading',
      propertyId,
      error: '',
    }))
    setActionError({ id: null, message: '' })
    setNotice({ propertyId: null, message: '' })
    setReloadKey((value) => value + 1)
  }

  async function updateApplication(id, operation, successMessage) {
    if (updatingId) return false

    setUpdatingId(id)
    setActionError({ id: null, message: '' })
    setNotice({ propertyId: null, message: '' })

    try {
      const updatedApplication = await operation()
      setPageState((current) => ({
        ...current,
        applications: current.propertyId === propertyId ? sortApplications(
          current.applications.map((application) =>
            application.id === id ? updatedApplication : application,
          ),
        ) : current.applications,
      }))
      setNotice({ propertyId, message: successMessage })
      return true
    } catch (error) {
      setActionError({
        id,
        message: safeErrorMessage(
          error,
          'Unable to update this rental application. Please try again.',
        ),
      })
      return false
    } finally {
      setUpdatingId(null)
    }
  }

  function handleReview(id) {
    return updateApplication(
      id,
      () => markUnderReview(id),
      'Application marked as under review.',
    )
  }

  function handleApprove(id, response) {
    return updateApplication(
      id,
      () => approveApplication(id, response),
      'Application approved.',
    )
  }

  function handleReject(id, reason) {
    return updateApplication(
      id,
      () => rejectApplication(id, reason),
      'Application rejected.',
    )
  }

  function handleRequestChanges(id, message) {
    return updateApplication(
      id,
      () => requestChanges(id, message),
      'Changes requested from the tenant.',
    )
  }

  const applications = pageStatus === 'success' ? pageState.applications : []
  const awaitingReview = applications.filter((application) =>
    [RENTAL_APPLICATION_STATUS.SUBMITTED, RENTAL_APPLICATION_STATUS.UNDER_REVIEW].includes(application.status)).length
  const query = search.trim().toLocaleLowerCase()
  const visibleApplications = applications.filter((application) =>
    (statusFilter === 'all' || application.status === Number(statusFilter))
    && (!query || [application.tenantId, application.propertyId, selection.property?.title,
      selection.property?.address, selection.property?.city]
      .filter(Boolean).some((value) => value.toLocaleLowerCase().includes(query))))

  return (
    <main
      className="applications-page"
      aria-busy={pageStatus === 'loading'}
    >
      <header className="applications-page__header">
        <div>
          <h1>{isAiReviewRoute ? 'AI Review' : 'Rental Applications'}</h1>
          <p className="applications-page__description">
            {isAiReviewRoute
              ? 'Review application validation findings and supporting documents before making a decision.'
              : 'Track tenant applications, review documents and validation findings, and make the final landlord decision.'}
          </p>
          {selection.property && <p className="applications-page__property">
            <strong>{selection.property.title}</strong>
            <span>{[selection.property.address, selection.property.city].filter(Boolean).join(', ')}</span>
          </p>}
          {pageStatus === 'success' && <p className="applications-page__count">
            {applications.length} total <span aria-hidden="true">&middot;</span> {awaitingReview} awaiting review
          </p>}
        </div>
        <button
          type="button"
          className="application-button application-button--quiet"
          onClick={loadApplications}
          disabled={selection.status !== 'selected' || pageStatus === 'loading'}
        >
          <Icon name="refresh" size={17} />Refresh
        </button>
      </header>

      {pageStatus === 'property-context' && (
        <PropertySelectionState className="applications-state" destination={isAiReviewRoute ? 'ai-review' : 'rental-applications'}
          selectedPropertyId={selection.status === 'unauthorized' ? propertyId : null} />
      )}

      {pageStatus === 'success' && notice.propertyId === propertyId && notice.message && (
        <div className="applications-notice" role="status">
          {notice.message}
        </div>
      )}

      {pageStatus === 'loading' && (
        <section className="applications-state" aria-live="polite">
          <span className="applications-spinner" aria-hidden="true" />
          <h2>Loading rental applications</h2>
          <p>Please wait while we fetch the latest applications.</p>
        </section>
      )}

      {pageStatus === 'error' && (
        <section
          className="applications-state applications-state--error"
          role="alert"
        >
          <div className="applications-state__icon" aria-hidden="true">
            !
          </div>
          <h2>We could not load the applications</h2>
          <p>{pageState.error}</p>
          <button
            type="button"
            className="application-button application-button--primary"
            onClick={loadApplications}
          >
            Try again
          </button>
        </section>
      )}

      {pageStatus === 'success' &&
        pageState.applications.length === 0 && (
          <section className="applications-state">
            <div className="applications-state__icon" aria-hidden="true"><Icon name="document" size={25} /></div>
            <h2>No rental applications yet</h2>
            <p>New tenant applications for this property will appear here.</p>
          </section>
        )}

      {pageStatus === 'success' &&
        pageState.applications.length > 0 && (
          <>
            <div className="applications-toolbar">
              <label className="applications-toolbar__search">
                <Icon name="search" size={19} />
                <input type="search" aria-label="Search tenant or property" value={search} onChange={(event) => setSearch(event.target.value)}
                  placeholder="Search tenant or property" />
              </label>
              <div className="applications-toolbar__filters" role="group" aria-label="Filter applications by status">
                {FILTER_STATUSES.map(([label, value]) => <button key={value} type="button"
                  className={`applications-toolbar__filter${statusFilter === value ? ' applications-toolbar__filter--active' : ''}`}
                  aria-pressed={statusFilter === value} onClick={() => setStatusFilter(value)}>{label}</button>)}
              </div>
            </div>

            {visibleApplications.length === 0 ? <section className="applications-state applications-state--filtered">
              <Icon name="search" size={28} />
              <h2>No matching applications</h2>
              <p>Try a different tenant or property search, or choose another status.</p>
              <button type="button" className="application-button application-button--quiet"
                onClick={() => { setSearch(''); setStatusFilter('all') }}>Clear filters</button>
            </section> : <section className="applications-list" aria-label="Rental applications">
              {visibleApplications.map((application) => <RentalApplicationListCard
                key={application.id} application={application} property={selection.property} isUpdating={updatingId === application.id}
                actionError={actionError.id === application.id ? actionError.message : ''}
                onReview={handleReview} onApprove={handleApprove} onReject={handleReject}
                onRequestChanges={handleRequestChanges} />)}
            </section>}
          </>
        )}
    </main>
  )
}

export default RentalApplicationsPage
