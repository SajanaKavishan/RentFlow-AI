import { useEffect, useState } from 'react'
import ViewingCard from '../components/ViewingCard.jsx'
import {
  approveViewing,
  getViewingsByProperty,
  rejectViewing,
  ViewingApiError,
} from '../services/viewingApiService.js'
import '../viewings.css'

// TODO(dev-only): Replace with the property selected through authenticated
// landlord/property navigation when those flows are implemented.
const TEMPORARY_PROPERTY_ID = '22222222-2222-2222-2222-222222222222'

function safeErrorMessage(error, fallback) {
  return error instanceof ViewingApiError ? error.message : fallback
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
    <main className="viewings-page">
      <header className="viewings-page__header">
        <div>
          <p className="viewings-page__eyebrow">Landlord workspace</p>
          <h1>Viewing requests</h1>
          <p>Review and respond to tenants interested in your property.</p>
        </div>
        <button type="button" className="button button--quiet" onClick={loadViewings}>
          Refresh
        </button>
      </header>

      {notice && (
        <div className="page-notice page-notice--success" role="status">
          {notice}
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
          <h2>We couldn’t load the requests</h2>
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
          <p>New tenant requests for this property will appear here.</p>
        </section>
      )}

      {pageState.status === 'success' && pageState.viewings.length > 0 && (
        <section className="viewings-list" aria-label="Viewing requests">
          {pageState.viewings.map((viewing) => (
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
        </section>
      )}
    </main>
  )
}

export default ViewingRequestsPage
