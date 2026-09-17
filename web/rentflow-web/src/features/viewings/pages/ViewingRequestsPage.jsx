import { useEffect, useState } from 'react'
import ViewingCard from '../components/ViewingCard.jsx'
import {
  approveViewing,
  getViewingsByProperty,
  rejectViewing,
  ViewingApiError,
  VIEWING_STATUS,
} from '../services/viewingApiService.js'
import '../viewings.css'

// TODO(dev-only): Replace with the property selected through authenticated
// landlord/property navigation when those flows are implemented.
const TEMPORARY_PROPERTY_ID = '22222222-2222-2222-2222-222222222222'

function safeErrorMessage(error, fallback) {
  return error instanceof ViewingApiError ? error.message : fallback
}

function prioritizePending(viewings) {
  return viewings
    .map((viewing, index) => ({ viewing, index }))
    .sort((left, right) => {
      const leftPriority = left.viewing.status === VIEWING_STATUS.PENDING ? 0 : 1
      const rightPriority = right.viewing.status === VIEWING_STATUS.PENDING ? 0 : 1
      return leftPriority - rightPriority || left.index - right.index
    })
    .map(({ viewing }) => viewing)
}

function ViewingRequestsPage() {
  const [pageState, setPageState] = useState({
    status: 'loading',
    viewings: [],
    error: '',
  })
  const [updatingId, setUpdatingId] = useState(null)
  const [actionError, setActionError] = useState({ id: null, message: '' })
  const [notice, setNotice] = useState('')
  const pendingCount = pageState.viewings.filter(
    (viewing) => viewing.status === VIEWING_STATUS.PENDING,
  ).length
  const orderedViewings = prioritizePending(pageState.viewings)

  useEffect(() => {
    let isActive = true

    getViewingsByProperty(TEMPORARY_PROPERTY_ID)
      .then((viewings) => {
        if (isActive) setPageState({ status: 'success', viewings, error: '' })
      })
      .catch((error) => {
        if (!isActive) return
        setPageState({
          status: 'error',
          viewings: [],
          error: safeErrorMessage(
            error,
            'Unable to load viewing requests. Please try again.',
          ),
        })
      })

    return () => {
      isActive = false
    }
  }, [])

  async function loadViewings() {
    setPageState((current) => ({ ...current, status: 'loading', error: '' }))
    setNotice('')

    try {
      const viewings = await getViewingsByProperty(TEMPORARY_PROPERTY_ID)
      setPageState({ status: 'success', viewings, error: '' })
    } catch (error) {
      setPageState({
        status: 'error',
        viewings: [],
        error: safeErrorMessage(
          error,
          'Unable to load viewing requests. Please try again.',
        ),
      })
    }
  }

  async function updateViewing(id, operation, successMessage) {
    if (updatingId) return false

    setUpdatingId(id)
    setActionError({ id: null, message: '' })
    setNotice('')

    try {
      const updatedViewing = await operation()
      setPageState((current) => ({
        ...current,
        viewings: current.viewings.map((viewing) =>
          viewing.id === id ? updatedViewing : viewing,
        ),
      }))
      setNotice(successMessage)
      return true
    } catch (error) {
      setActionError({
        id,
        message: safeErrorMessage(
          error,
          'Unable to update this viewing request. Please try again.',
        ),
      })
      return false
    } finally {
      setUpdatingId(null)
    }
  }

  function handleApprove(id, response) {
    return updateViewing(
      id,
      () => approveViewing(id, response),
      'Viewing request approved.',
    )
  }

  function handleReject(id, reason) {
    return updateViewing(
      id,
      () => rejectViewing(id, reason),
      'Viewing request rejected.',
    )
  }

  return (
    <main
      className="viewings-page"
      aria-busy={pageState.status === 'loading'}
    >
      <header className="viewings-page__header">
        <div>
          <p className="viewings-page__eyebrow">Landlord workspace</p>
          <h1>Viewing requests</h1>
          <p>
            Review requested appointments and respond to tenants interested in
            your property.
          </p>
        </div>
        <button
          type="button"
          className="button button--quiet viewings-page__refresh"
          onClick={loadViewings}
          disabled={pageState.status === 'loading'}
        >
          <span aria-hidden="true">↻</span>
          {pageState.status === 'loading' ? 'Refreshing...' : 'Refresh'}
        </button>
      </header>

      {notice && (
        <div className="page-notice page-notice--success" role="status">
          <span className="page-notice__icon" aria-hidden="true">✓</span>
          <span>{notice}</span>
        </div>
      )}

      {pageState.status === 'loading' && (
        <section className="page-state" aria-live="polite">
          <span className="loading-spinner" aria-hidden="true" />
          <h2>Loading viewing requests</h2>
          <p>Please wait while we fetch the latest requests.</p>
        </section>
      )}

      {pageState.status === 'error' && (
        <section className="page-state page-state--error" role="alert">
          <div className="page-state__icon" aria-hidden="true">
            !
          </div>
          <h2>We couldn&apos;t load the requests</h2>
          <p>{pageState.error}</p>
          <button type="button" className="button button--primary" onClick={loadViewings}>
            Try again
          </button>
        </section>
      )}

      {pageState.status === 'success' && pageState.viewings.length === 0 && (
        <section className="page-state">
          <div className="page-state__icon" aria-hidden="true">
            ✓
          </div>
          <h2>No viewing requests yet</h2>
          <p>
            New tenant requests for this property will appear here when they
            are submitted.
          </p>
        </section>
      )}

      {pageState.status === 'success' && pageState.viewings.length > 0 && (
        <>
          <section className="viewings-summary" aria-label="Request summary">
            <div
              className={`viewings-summary__item${
                pendingCount > 0 ? ' viewings-summary__item--priority' : ''
              }`}
            >
              <span className="viewings-summary__number">{pendingCount}</span>
              <span>
                <strong>Pending response</strong>
                <small>
                  {pendingCount > 0
                    ? 'Review these requests first'
                    : 'No requests need a decision'}
                </small>
              </span>
            </div>
            <div className="viewings-summary__item">
              <span className="viewings-summary__number">
                {pageState.viewings.length}
              </span>
              <span>
                <strong>Total requests</strong>
                <small>Across all current statuses</small>
              </span>
            </div>
          </section>

          <section
            className="viewings-results"
            aria-labelledby="viewings-results-title"
          >
            <div className="viewings-results__heading">
              <div>
                <p className="viewings-page__eyebrow">Request queue</p>
                <h2 id="viewings-results-title">All viewing requests</h2>
              </div>
              <p>Pending requests are shown first.</p>
            </div>
            <div className="viewings-list">
              {orderedViewings.map((viewing) => (
                <ViewingCard
                  key={viewing.id}
                  viewing={viewing}
                  isUpdating={updatingId === viewing.id}
                  actionError={
                    actionError.id === viewing.id ? actionError.message : ''
                  }
                  onApprove={handleApprove}
                  onReject={handleReject}
                />
              ))}
            </div>
          </section>
        </>
      )}
    </main>
  )
}

export default ViewingRequestsPage
