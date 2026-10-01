import { useContext, useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import PropertySelectionState from '../../../shared/property/PropertySelectionState.jsx'
import usePropertyContext from '../../../shared/property/usePropertyContext.js'
import { useOwnedPropertySelection } from '../../../shared/property/useOwnedProperties.js'
import { PendingViewingsContext } from '../../../shared/layout/PendingViewingsContext.js'
import Icon from '../../../shared/ui/Icons.jsx'
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

function validPropertyViewing(viewing, propertyId, expectedId = null) {
  return Boolean(
    viewing
    && typeof viewing.id === 'string'
    && viewing.id.trim()
    && (!expectedId || viewing.id.toLowerCase() === expectedId.toLowerCase())
    && typeof viewing.tenantId === 'string'
    && viewing.tenantId.trim()
    && typeof viewing.propertyId === 'string'
    && viewing.propertyId.toLowerCase() === propertyId.toLowerCase()
    && Object.values(VIEWING_STATUS).includes(viewing.status),
  )
}

function verifyPropertyViewings(viewings, propertyId) {
  if (!Array.isArray(viewings)
    || viewings.some((viewing) => !validPropertyViewing(viewing, propertyId))
    || new Set(viewings.map((viewing) => viewing.id.toLowerCase())).size !== viewings.length) {
    throw new TypeError('Invalid property viewing response')
  }
  return viewings
}

const STATUS_FILTERS = [
  { value: 'all', label: 'All' },
  { value: VIEWING_STATUS.PENDING, label: 'Pending' },
  { value: VIEWING_STATUS.APPROVED, label: 'Approved' },
  { value: VIEWING_STATUS.REJECTED, label: 'Rejected' },
]

function requestSearchFields(viewing) {
  return [
    viewing.tenantId,
    viewing.tenantMessage,
    viewing.landlordResponse,
    viewing.requestedDateTime,
    viewing.createdAt,
  ].filter((value) => typeof value === 'string')
}

function ViewingRequestsPage() {
  const publishPendingViewings = useContext(PendingViewingsContext)
  const { propertyId } = usePropertyContext()
  const selection = useOwnedPropertySelection(propertyId)
  const [pageState, setPageState] = useState({
    status: 'loading',
    propertyId: null,
    viewings: [],
    error: '',
  })
  const [updatingId, setUpdatingId] = useState(null)
  const [actionError, setActionError] = useState({ id: null, message: '' })
  const [notice, setNotice] = useState({ propertyId: null, message: '' })
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const pendingCount = pageState.viewings.filter(
    (viewing) => viewing.status === VIEWING_STATUS.PENDING,
  ).length
  const orderedViewings = prioritizePending(pageState.viewings)
  const filteredViewings = useMemo(() => {
    const normalizedSearch = search.trim().toLowerCase()
    return orderedViewings.filter((viewing) => {
      const matchesStatus = statusFilter === 'all' || viewing.status === statusFilter
      const matchesSearch = !normalizedSearch || requestSearchFields(viewing)
        .some((value) => value.toLowerCase().includes(normalizedSearch))
      return matchesStatus && matchesSearch
    })
  }, [orderedViewings, search, statusFilter])
  const pageStatus = selection.status !== 'selected'
    ? 'property-context'
    : pageState.propertyId === propertyId
      ? pageState.status
      : 'loading'

  useEffect(() => {
    if (selection.status === 'selected') {
      publishPendingViewings?.(propertyId, pageStatus === 'success' ? pendingCount : null)
    }
  }, [pageStatus, propertyId, pendingCount, publishPendingViewings, selection.status])

  useEffect(() => {
    if (!propertyId || selection.status !== 'selected') return undefined

    let isActive = true

    getViewingsByProperty(propertyId)
      .then((viewings) => {
        if (isActive) {
          setPageState({
            status: 'success',
            propertyId,
            viewings: verifyPropertyViewings(viewings, propertyId),
            error: '',
          })
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
  }, [propertyId, selection.status])

  async function loadViewings() {
    if (!propertyId || selection.status !== 'selected') return

    setPageState((current) => ({
      ...current,
      status: 'loading',
      propertyId,
      error: '',
    }))
    setNotice({ propertyId: null, message: '' })

    try {
      const viewings = await getViewingsByProperty(propertyId)
      setPageState({
        status: 'success',
        propertyId,
        viewings: verifyPropertyViewings(viewings, propertyId),
        error: '',
      })
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
    setNotice({ propertyId: null, message: '' })

    try {
      const updatedViewing = await operation()
      if (!validPropertyViewing(updatedViewing, propertyId, id)) {
        throw new TypeError('Invalid viewing update response')
      }
      setPageState((current) => ({
        ...current,
        viewings: current.propertyId === propertyId
          ? current.viewings.map((viewing) =>
              viewing.id === id ? updatedViewing : viewing,
            )
          : current.viewings,
      }))
      setNotice({ propertyId, message: successMessage })
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
      aria-busy={pageStatus === 'loading' || selection.status === 'loading'}
    >
      {selection.property && (
        <Link
          className="viewings-page__back"
          to={`/properties/${encodeURIComponent(selection.property.id)}`}
        >
          <Icon name="arrowLeft" size={16} /> Back to Property
        </Link>
      )}

      <header className="viewings-page__header">
        <div className="viewings-page__intro">
          <h1>Viewing Requests</h1>
          <p>
            Review requested appointments and respond to tenants interested in
            your property.
          </p>
          {selection.property && (
            <div className="viewings-page__property" role="group" aria-label="Selected property">
              <span>Selected property</span>
              <strong>{selection.property.title}</strong>
              {[selection.property.address, selection.property.city].filter(Boolean).length > 0 && (
                <small>
                  <Icon name="pin" size={15} />
                  {[selection.property.address, selection.property.city].filter(Boolean).join(', ')}
                </small>
              )}
            </div>
          )}
        </div>
        <div className="viewings-page__header-actions">
          {pageStatus === 'success' && (
            <dl className="viewings-page__counts" role="group" aria-label="Viewing request counts">
              <div>
                <dt>Total</dt>
                <dd>{pageState.viewings.length}</dd>
              </div>
              <div className={pendingCount > 0 ? 'is-pending' : ''}>
                <dt>Pending</dt>
                <dd>{pendingCount}</dd>
              </div>
            </dl>
          )}
          <button
            type="button"
            className="button button--quiet viewings-page__refresh"
            onClick={loadViewings}
            disabled={selection.status !== 'selected' || pageStatus === 'loading'}
          >
            <span aria-hidden="true">↻</span>
            {pageStatus === 'loading' ? 'Refreshing...' : 'Refresh'}
          </button>
        </div>
      </header>

      {pageStatus === 'property-context' && (
        <PropertySelectionState className="page-state" destination="viewing-requests"
          selectedPropertyId={selection.status === 'unauthorized' ? propertyId : null} />
      )}

      {pageStatus === 'success' && notice.propertyId === propertyId && notice.message && (
        <div className="page-notice page-notice--success" role="status">
          <span className="page-notice__icon" aria-hidden="true">✓</span>
          <span>{notice.message}</span>
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
        <section
          className="viewings-results"
          aria-labelledby="viewings-results-title"
        >
          <div className="viewings-results__heading">
            <div>
              <p className="viewings-page__eyebrow">Request queue</p>
              <h2 id="viewings-results-title">All viewing requests</h2>
            </div>
            <p>{filteredViewings.length} of {pageState.viewings.length} requests shown</p>
          </div>
          <div className="viewings-filters" aria-label="Filter viewing requests">
            <label className="viewings-filters__search">
              <span className="sr-only">Search viewing requests</span>
              <Icon name="search" size={17} />
              <input
                type="search"
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder="Search by tenant ID or message"
              />
            </label>
            <div className="viewings-filters__statuses" role="group" aria-label="Request status">
              {STATUS_FILTERS.map((filter) => (
                <button
                  key={filter.label}
                  type="button"
                  className={`viewings-filter${statusFilter === filter.value ? ' viewings-filter--active' : ''}`}
                  aria-pressed={statusFilter === filter.value}
                  onClick={() => setStatusFilter(filter.value)}
                >
                  {filter.label}
                </button>
              ))}
            </div>
          </div>
          <div className="viewings-list">
            {filteredViewings.map((viewing) => (
              <ViewingCard
                key={viewing.id}
                viewing={viewing}
                property={selection.property}
                isUpdating={updatingId === viewing.id}
                actionError={
                  actionError.id === viewing.id ? actionError.message : ''
                }
                onApprove={handleApprove}
                onReject={handleReject}
              />
            ))}
          </div>
          {filteredViewings.length === 0 && (
            <div className="viewings-filter-empty" role="status">
              <h3>No matching viewing requests</h3>
              <p>Try a different search or status filter.</p>
            </div>
          )}
        </section>
      )}
    </main>
  )
}

export default ViewingRequestsPage
