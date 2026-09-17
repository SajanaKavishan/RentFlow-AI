import { useEffect, useState } from 'react'
import RentalApplicationCard from '../components/RentalApplicationCard.jsx'
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

// TODO(dev-only): Replace this temporary property ID with the property selected
// from authenticated landlord/property navigation.
const TEMPORARY_PROPERTY_ID = '22222222-2222-2222-2222-222222222222'

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

function RentalApplicationsPage() {
  const [pageState, setPageState] = useState({
    status: 'loading',
    applications: [],
    error: '',
  })
  const [updatingId, setUpdatingId] = useState(null)
  const [actionError, setActionError] = useState({ id: null, message: '' })
  const [notice, setNotice] = useState('')

  useEffect(() => {
    let isActive = true

    getApplicationsByProperty(TEMPORARY_PROPERTY_ID)
      .then((applications) => {
        if (isActive) {
          setPageState({
            status: 'success',
            applications: sortApplications(applications),
            error: '',
          })
        }
      })
      .catch((error) => {
        if (!isActive) return
        setPageState({
          status: 'error',
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
  }, [])

  async function loadApplications() {
    setPageState((current) => ({ ...current, status: 'loading', error: '' }))
    setActionError({ id: null, message: '' })
    setNotice('')

    try {
      const applications = await getApplicationsByProperty(
        TEMPORARY_PROPERTY_ID,
      )
      setPageState({
        status: 'success',
        applications: sortApplications(applications),
        error: '',
      })
    } catch (error) {
      setPageState({
        status: 'error',
        applications: [],
        error: safeErrorMessage(
          error,
          'Unable to load rental applications. Please try again.',
        ),
      })
    }
  }

  async function updateApplication(id, operation, successMessage) {
    if (updatingId) return false

    setUpdatingId(id)
    setActionError({ id: null, message: '' })
    setNotice('')

    try {
      const updatedApplication = await operation()
      setPageState((current) => ({
        ...current,
        applications: sortApplications(
          current.applications.map((application) =>
            application.id === id ? updatedApplication : application,
          ),
        ),
      }))
      setNotice(successMessage)
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

  const reviewCounts = pageState.applications.reduce(
    (counts, application) => {
      if (application.status === RENTAL_APPLICATION_STATUS.SUBMITTED) {
        counts.submitted += 1
      } else if (
        application.status === RENTAL_APPLICATION_STATUS.UNDER_REVIEW
      ) {
        counts.underReview += 1
      } else if (
        application.status === RENTAL_APPLICATION_STATUS.CHANGES_REQUESTED
      ) {
        counts.changesRequested += 1
      }
      return counts
    },
    { submitted: 0, underReview: 0, changesRequested: 0 },
  )
  const attentionCount =
    reviewCounts.submitted +
    reviewCounts.underReview +
    reviewCounts.changesRequested

  return (
    <main
      className="applications-page"
      aria-busy={pageState.status === 'loading'}
    >
      <header className="applications-page__header">
        <div>
          <p className="applications-page__eyebrow">Landlord workspace</p>
          <h1>Rental applications</h1>
          <p>
            Review tenant details, supporting documents, and validation findings
            before making a landlord decision.
          </p>
        </div>
        <button
          type="button"
          className="application-button application-button--quiet"
          onClick={loadApplications}
          disabled={pageState.status === 'loading'}
        >
          Refresh
        </button>
      </header>

      {notice && (
        <div className="applications-notice" role="status">
          {notice}
        </div>
      )}

      {pageState.status === 'loading' && (
        <section className="applications-state" aria-live="polite">
          <span className="applications-spinner" aria-hidden="true" />
          <h2>Loading rental applications</h2>
          <p>Please wait while we fetch the latest applications.</p>
        </section>
      )}

      {pageState.status === 'error' && (
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

      {pageState.status === 'success' &&
        pageState.applications.length === 0 && (
          <section className="applications-state">
            <div className="applications-state__icon" aria-hidden="true">
              ✓
            </div>
            <h2>No rental applications yet</h2>
            <p>New tenant applications for this property will appear here.</p>
          </section>
        )}

      {pageState.status === 'success' &&
        pageState.applications.length > 0 && (
          <>
            <section
              className="applications-summary"
              aria-label="Application review summary"
            >
              <div className="applications-summary__intro">
                <p className="applications-page__eyebrow">Review queue</p>
                <h2>Applications needing attention</h2>
                <p>
                  {attentionCount === 0
                    ? 'No applications currently need action.'
                    : `${attentionCount} ${attentionCount === 1 ? 'application needs' : 'applications need'} attention. Priority items are listed first.`}
                </p>
              </div>
              <dl className="applications-summary__counts">
                <div className="applications-summary__count applications-summary__count--submitted">
                  <dt>Submitted</dt>
                  <dd>{reviewCounts.submitted}</dd>
                </div>
                <div className="applications-summary__count applications-summary__count--review">
                  <dt>Under review</dt>
                  <dd>{reviewCounts.underReview}</dd>
                </div>
                <div className="applications-summary__count applications-summary__count--changes">
                  <dt>Changes requested</dt>
                  <dd>{reviewCounts.changesRequested}</dd>
                </div>
              </dl>
            </section>

            <section
              className="applications-list"
              aria-label="Rental applications"
            >
              {pageState.applications.map((application) => (
                <RentalApplicationCard
                  key={application.id}
                  application={application}
                  isUpdating={updatingId === application.id}
                  actionError={
                    actionError.id === application.id ? actionError.message : ''
                  }
                  onReview={handleReview}
                  onApprove={handleApprove}
                  onReject={handleReject}
                  onRequestChanges={handleRequestChanges}
                />
              ))}
            </section>
          </>
        )}
    </main>
  )
}

export default RentalApplicationsPage
