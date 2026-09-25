import { useEffect, useState } from 'react'
import { useAuth } from '../../auth/useAuth.js'
import {
  createMaintenanceRequest,
  getMaintenanceRequestById,
  getTenantMaintenanceRequests,
  MaintenanceApiError,
} from '../services/maintenanceApiService.js'
import '../maintenance.css'

const DEFAULT_FORM = {
  propertyId: '',
  title: '',
  description: '',
  category: 'Plumbing',
  priority: 'Normal',
  tenantAccessNotes: '',
}

const MAINTENANCE_CATEGORIES = [
  'Plumbing',
  'Electrical',
  'Appliance',
  'Structural',
  'Security',
  'Pest',
  'Other',
]

const MAINTENANCE_PRIORITIES = ['Low', 'Normal', 'High', 'Emergency']

function isValidGuid(value) {
  return /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/.test(value)
}

function safeErrorMessage(error, fallback) {
  return error instanceof MaintenanceApiError ? error.message : fallback
}

function formatDate(value) {
  if (!value) return '—'
  const parsed = new Date(value)
  if (Number.isNaN(parsed.getTime())) return '—'
  return parsed.toLocaleString(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  })
}

function formatStatusLabel(value) {
  if (!value) return 'Unknown'
  return value
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/_/g, ' ')
    .trim()
}

function statusClass(value) {
  return String(value || 'unknown')
    .replace(/([a-z])([A-Z])/g, '$1-$2')
    .replace(/_/g, '-')
    .toLowerCase()
}

function TenantMaintenancePage() {
  const { user } = useAuth()
  const tenantId = user?.id

  const [requests, setRequests] = useState([])
  const [selectedRequestId, setSelectedRequestId] = useState(null)
  const [selectedRequest, setSelectedRequest] = useState(null)
  const [detailState, setDetailState] = useState('idle')
  const [detailError, setDetailError] = useState('')
  const [pageState, setPageState] = useState('loading')
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [form, setForm] = useState(DEFAULT_FORM)
  const [formError, setFormError] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)

  async function loadRequestDetails(id) {
    if (!id) {
      setSelectedRequest(null)
      setDetailState('idle')
      setDetailError('')
      return
    }

    setDetailState('loading')
    setDetailError('')

    try {
      const nextRequest = await getMaintenanceRequestById(id)
      setSelectedRequest(nextRequest)
      setDetailState('success')
    } catch (requestError) {
      setSelectedRequest(null)
      setDetailState('error')
      setDetailError(
        safeErrorMessage(
          requestError,
          'Unable to load the selected maintenance request. Please try again.',
        ),
      )
    }
  }

  async function refreshRequests() {
    if (!tenantId) {
      setPageState('unauthorized')
      setRequests([])
      setSelectedRequestId(null)
      setSelectedRequest(null)
      return
    }

    setPageState('loading')
    setError('')
    setNotice('')

    try {
      const nextRequests = await getTenantMaintenanceRequests(tenantId)
      setRequests(Array.isArray(nextRequests) ? nextRequests : [])
      setPageState('success')

      if (nextRequests.length === 0) {
        setSelectedRequestId(null)
        setSelectedRequest(null)
        setDetailState('idle')
        setDetailError('')
        return
      }

      const fallbackId = nextRequests[0].id
      setSelectedRequestId(fallbackId)
      await loadRequestDetails(fallbackId)
    } catch (loadError) {
      setPageState('error')
      setError(
        safeErrorMessage(
          loadError,
          'Unable to load your maintenance requests. Please try again.',
        ),
      )
      setRequests([])
      setSelectedRequestId(null)
      setSelectedRequest(null)
      setDetailState('idle')
      setDetailError('')
    }
  }

  useEffect(() => {
    refreshRequests()
  }, [tenantId])

  const handleRequestSelection = async (requestId) => {
    if (!requestId) return
    setSelectedRequestId(requestId)
    await loadRequestDetails(requestId)
  }

  const handleChange = (event) => {
    const { name, value } = event.target
    setForm((current) => ({ ...current, [name]: value }))
  }

  const handleSubmit = async (event) => {
    event.preventDefault()

    if (!tenantId) {
      setFormError('Please sign in to submit a maintenance request.')
      return
    }

    if (
      !form.propertyId.trim() ||
      !form.title.trim() ||
      !form.description.trim()
    ) {
      setFormError('Please complete the property, title, and description fields.')
      return
    }

    const normalizedPropertyId = form.propertyId.trim()
    if (!isValidGuid(normalizedPropertyId)) {
      setFormError('Property ID must be a valid GUID/UUID in the format xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.')
      return
    }

    setIsSubmitting(true)
    setFormError('')
    setNotice('')

    try {
      const payload = {
        propertyId: normalizedPropertyId,
        title: form.title.trim(),
        description: form.description.trim(),
        category: form.category,
        priority: form.priority,
        tenantAccessNotes: form.tenantAccessNotes.trim() || null,
      }

      const createdRequest = await createMaintenanceRequest(tenantId, payload)
      setRequests((current) => [createdRequest, ...current])
      setForm(DEFAULT_FORM)
      setSelectedRequestId(createdRequest.id)
      setNotice('Maintenance request submitted successfully.')
      await loadRequestDetails(createdRequest.id)
    } catch (submitError) {
      setFormError(
        safeErrorMessage(
          submitError,
          'Unable to submit your request. Please try again.',
        ),
      )
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <main className="maintenance-page" aria-busy={pageState === 'loading'}>
      <header className="maintenance-page__header">
        <div>
          <p className="maintenance-page__eyebrow">Tenant workspace</p>
          <h1>Maintenance requests</h1>
          <p>
            Track issues in your home, keep notes for the maintenance team, and
            review the latest status on each request.
          </p>
        </div>
        <button
          type="button"
          className="button button--quiet maintenance-page__refresh"
          onClick={refreshRequests}
          disabled={pageState === 'loading'}
        >
          <span aria-hidden="true">↻</span>
          {pageState === 'loading' ? 'Refreshing...' : 'Refresh'}
        </button>
      </header>

      {notice && (
        <div className="page-notice page-notice--success" role="status">
          <span className="page-notice__icon" aria-hidden="true">
            ✓
          </span>
          <span>{notice}</span>
        </div>
      )}

      {pageState === 'loading' && (
        <section className="page-state" aria-live="polite">
          <span className="loading-spinner" aria-hidden="true" />
          <h2>Loading maintenance requests</h2>
          <p>Please wait while we fetch your request history.</p>
        </section>
      )}

      {pageState === 'error' && (
        <section className="page-state page-state--error" role="alert">
          <div className="page-state__icon" aria-hidden="true">
            !
          </div>
          <h2>We couldn&apos;t load your maintenance requests</h2>
          <p>{error}</p>
          <button type="button" className="button button--primary" onClick={refreshRequests}>
            Try again
          </button>
        </section>
      )}

      {pageState === 'success' && (
        <div className="maintenance-layout">
          <section className="maintenance-panel maintenance-panel--list" aria-labelledby="maintenance-list-title">
            <div className="maintenance-panel__header">
              <div>
                <p className="maintenance-page__eyebrow">Request history</p>
                <h2 id="maintenance-list-title">Your requests</h2>
              </div>
            </div>

            {requests.length === 0 ? (
              <div className="page-state page-state--inline">
                <div className="page-state__icon" aria-hidden="true">
                  ✓
                </div>
                <h3>No maintenance requests yet</h3>
                <p>Submit a new request to get support for your property.</p>
              </div>
            ) : (
              <div className="maintenance-request-list">
                {requests.map((request) => (
                  <button
                    type="button"
                    key={request.id}
                    className={`maintenance-request-card${
                      selectedRequestId === request.id ? ' maintenance-request-card--selected' : ''
                    }`}
                    onClick={() => handleRequestSelection(request.id)}
                  >
                    <div className="maintenance-request-card__topline">
                      <strong>{request.title}</strong>
                      <span className={`status-badge status-badge--${statusClass(request.status)}`}>
                        {formatStatusLabel(request.status)}
                      </span>
                    </div>
                    <div className="maintenance-request-card__meta">
                      <span>{request.category}</span>
                      <span>{request.priority}</span>
                    </div>
                    <small>Submitted {formatDate(request.createdAt)}</small>
                  </button>
                ))}
              </div>
            )}
          </section>

          <section className="maintenance-panel maintenance-panel--form">
            <div className="maintenance-panel__header">
              <div>
                <p className="maintenance-page__eyebrow">New request</p>
                <h2>Report an issue</h2>
              </div>
            </div>

            <form className="maintenance-form" onSubmit={handleSubmit}>
              <label>
                Property ID
                <input
                  type="text"
                  name="propertyId"
                  value={form.propertyId}
                  onChange={handleChange}
                  placeholder="e.g. 9b1040b3-f45d-4f2a-b91d-2d8f4ec6b4fd"
                />
              </label>

              <label>
                Title
                <input
                  type="text"
                  name="title"
                  value={form.title}
                  onChange={handleChange}
                  placeholder="Leaking kitchen sink"
                />
              </label>

              <label>
                Description
                <textarea
                  name="description"
                  value={form.description}
                  onChange={handleChange}
                  rows={6}
                  placeholder="Describe the issue, what is happening, and when it started."
                />
              </label>

              <div className="maintenance-form__row">
                <label>
                  Category
                  <select name="category" value={form.category} onChange={handleChange}>
                    {MAINTENANCE_CATEGORIES.map((category) => (
                      <option key={category} value={category}>
                        {category}
                      </option>
                    ))}
                  </select>
                </label>

                <label>
                  Priority
                  <select name="priority" value={form.priority} onChange={handleChange}>
                    {MAINTENANCE_PRIORITIES.map((priority) => (
                      <option key={priority} value={priority}>
                        {priority}
                      </option>
                    ))}
                  </select>
                </label>
              </div>

              <label>
                Tenant access notes
                <textarea
                  name="tenantAccessNotes"
                  value={form.tenantAccessNotes}
                  onChange={handleChange}
                  rows={3}
                  placeholder="Optional notes for the technician such as access instructions or key location."
                />
              </label>

              {formError && (
                <div className="form-message form-message--error" role="alert">
                  {formError}
                </div>
              )}

              <button type="submit" className="button button--primary" disabled={isSubmitting}>
                {isSubmitting ? 'Submitting...' : 'Submit request'}
              </button>
            </form>
          </section>

          <aside className="maintenance-panel maintenance-panel--detail" aria-live="polite">
            <div className="maintenance-panel__header">
              <div>
                <p className="maintenance-page__eyebrow">Details</p>
                <h2>Request summary</h2>
              </div>
            </div>

            {detailState === 'loading' && (
              <div className="page-state page-state--inline">
                <span className="loading-spinner" aria-hidden="true" />
                <p>Loading request details...</p>
              </div>
            )}

            {detailState === 'error' && (
              <div className="page-state page-state--error page-state--inline">
                <div className="page-state__icon" aria-hidden="true">
                  !
                </div>
                <p>{detailError}</p>
              </div>
            )}

            {detailState === 'success' && selectedRequest && (
              <article className="maintenance-detail">
                <div className="maintenance-detail__topline">
                  <h3>{selectedRequest.title}</h3>
                  <span className={`status-badge status-badge--${statusClass(selectedRequest.status)}`}>
                    {formatStatusLabel(selectedRequest.status)}
                  </span>
                </div>

                <dl className="maintenance-detail__meta">
                  <div>
                    <dt>Property ID</dt>
                    <dd>{selectedRequest.propertyId}</dd>
                  </div>
                  <div>
                    <dt>Category</dt>
                    <dd>{selectedRequest.category}</dd>
                  </div>
                  <div>
                    <dt>Priority</dt>
                    <dd>{selectedRequest.priority}</dd>
                  </div>
                  <div>
                    <dt>Created</dt>
                    <dd>{formatDate(selectedRequest.createdAt)}</dd>
                  </div>
                  <div>
                    <dt>Updated</dt>
                    <dd>{formatDate(selectedRequest.updatedAt)}</dd>
                  </div>
                </dl>

                <section className="maintenance-detail__section">
                  <h4>Description</h4>
                  <p>{selectedRequest.description || 'No description was provided.'}</p>
                </section>

                <section className="maintenance-detail__section">
                  <h4>Tenant access notes</h4>
                  <p>{selectedRequest.tenantAccessNotes || 'No access notes were provided.'}</p>
                </section>

                {selectedRequest.triageNotes && (
                  <section className="maintenance-detail__section">
                    <h4>Triage notes</h4>
                    <p>{selectedRequest.triageNotes}</p>
                  </section>
                )}

                {selectedRequest.assignmentNotes && (
                  <section className="maintenance-detail__section">
                    <h4>Assignment notes</h4>
                    <p>{selectedRequest.assignmentNotes}</p>
                  </section>
                )}
              </article>
            )}

            {!selectedRequest && detailState !== 'loading' && detailState !== 'error' && (
              <div className="page-state page-state--inline">
                <div className="page-state__icon" aria-hidden="true">
                  ✓
                </div>
                <p>Select a request to view the full details.</p>
              </div>
            )}
          </aside>
        </div>
      )}
    </main>
  )
}

export default TenantMaintenancePage
