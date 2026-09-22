import { useEffect, useState } from 'react'
import PropertySelectionState from '../../../shared/property/PropertySelectionState.jsx'
import usePropertyContext from '../../../shared/property/usePropertyContext.js'
import ViewingCard from '../components/ViewingCard.jsx'
import {
  approveViewing,
  getViewingsByProperty,
  rejectViewing,
  ViewingApiError,
  VIEWING_STATUS,
} from '../services/viewingApiService.js'
import '../viewings.css'

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
  const { propertyId } = usePropertyContext()
  const [pageState, setPageState] = useState({
    status: 'loading',
    propertyId: null,
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
  const pageStatus = !propertyId
    ? 'property-required'
    : pageState.propertyId === propertyId
      ? pageState.status
      : 'loading'

  useEffect(() => {
    if (!propertyId) return undefined

    let isActive = true

    getViewingsByProperty(propertyId)
      .then((viewings) => {
        if (isActive) {
          setPageState({ status: 'success', propertyId, viewings, error: '' })
        }
      })
      .catch((error) => {
        if (!isActive) return
        setPageState({
          status: 'error',
          propertyId,
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
  }, [propertyId])

  async function loadViewings() {
    if (!propertyId) return

    setPageState((current) => ({
      ...current,
      status: 'loading',
      propertyId,
      error: '',
    }))
    setNotice('')

    try {
      const viewings = await getViewingsByProperty(propertyId)
      setPageState({ status: 'success', propertyId, viewings, error: '' })
    } catch (error) {
      setPageState({
        status: 'error',
        propertyId,
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
      aria-busy={pageStatus === 'loading'}
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
          disabled={!propertyId || pageStatus === 'loading'}
        >
          <span aria-hidden="true">↻</span>
          {pageStatus === 'loading' ? 'Refreshing...' : 'Refresh'}
        </button>
      </header>

      {pageStatus === 'property-required' && (
        <PropertySelectionState className="page-state" />
      )}

      {pageStatus === 'success' && notice && (
        <div className="page-notice page-notice--success" role="status">
          <span className="page-notice__icon" aria-hidden="true">✓</span>
          <span>{notice}</span>
        </div>
      )}

      {pageStatus === 'loading' && (
        <section className="page-state" aria-live="polite">
          <span className="loading-spinner" aria-hidden="true" />
          <h2>Loading viewing requests</h2>
          <p>Please wait while we fetch the latest requests.</p>
        </section>
      )}

      {pageStatus === 'error' && (
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

      {pageStatus === 'success' && pageState.viewings.length === 0 && (
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

      {pageStatus === 'success' && pageState.viewings.length > 0 && (
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
