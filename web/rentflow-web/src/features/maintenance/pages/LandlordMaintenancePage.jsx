import { useEffect, useState } from 'react'
import { useAuth } from '../../auth/useAuth.js'
import { USER_ROLES } from '../../auth/authModel.js'
import PropertySelectionState from '../../../shared/property/PropertySelectionState.jsx'
import usePropertyContext from '../../../shared/property/usePropertyContext.js'
import {
  approveCoordinationWorkflow,
  getCoordinationWorkflow,
  getLatestEstimate,
  getMaintenanceHistory,
  getMaintenanceRequestById,
  getPropertyMaintenanceRequests,
  MaintenanceApiError,
  rejectCoordinationWorkflow,
} from '../services/maintenanceApiService.js'
import '../maintenance.css'

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

const STATUS_LABELS = {
  0: 'Submitted',
  1: 'Triaged',
  2: 'Assigned',
  3: 'Estimate Pending',
  4: 'Estimate Submitted',
  5: 'Awaiting Landlord Approval',
  6: 'Approved',
  7: 'Rejected',
  8: 'In Progress',
  9: 'Completed',
  10: 'Cancelled',
  Submitted: 'Submitted',
  Triaged: 'Triaged',
  Assigned: 'Assigned',
  EstimatePending: 'Estimate Pending',
  EstimateSubmitted: 'Estimate Submitted',
  AwaitingLandlordApproval: 'Awaiting Landlord Approval',
  Approved: 'Approved',
  Rejected: 'Rejected',
  InProgress: 'In Progress',
  Completed: 'Completed',
  Cancelled: 'Cancelled',
  AwaitingHumanReview: 'Awaiting Human Review',
  Pending: 'Pending',
  Running: 'Running',
  Failed: 'Failed',
  Completed: 'Completed',
}

const CATEGORY_LABELS = {
  0: 'Plumbing',
  1: 'Electrical',
  2: 'Appliance',
  3: 'Structural',
  4: 'Security',
  5: 'Pest',
  6: 'Other',
  Plumbing: 'Plumbing',
  Electrical: 'Electrical',
  Appliance: 'Appliance',
  Structural: 'Structural',
  Security: 'Security',
  Pest: 'Pest',
  Other: 'Other',
}

const PRIORITY_LABELS = {
  0: 'Low',
  1: 'Normal',
  2: 'High',
  3: 'Emergency',
  Low: 'Low',
  Normal: 'Normal',
  High: 'High',
  Emergency: 'Emergency',
}

const ESTIMATE_STATUS_LABELS = {
  0: 'Draft',
  1: 'Submitted',
  2: 'Revision Requested',
  3: 'Approved',
  4: 'Rejected',
  5: 'Superseded',
  Draft: 'Draft',
  Submitted: 'Submitted',
  RevisionRequested: 'Revision Requested',
  Approved: 'Approved',
  Rejected: 'Rejected',
  Superseded: 'Superseded',
}

function formatLabel(value, labels = {}) {
  if (value == null || value === '') return 'Unknown'
  const normalizedValue = labels[value] ?? labels[String(value)] ?? value
  if (typeof normalizedValue === 'string' && normalizedValue.trim()) return normalizedValue

  return String(value)
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/_/g, ' ')
    .trim()
}

function toBadgeClass(value) {
  return String(value ?? 'unknown')
    .replace(/([a-z])([A-Z])/g, '$1-$2')
    .replace(/_/g, '-')
    .toLowerCase()
}

function money(value) {
  if (value == null || Number.isNaN(Number(value))) return '—'
  return new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 2,
  }).format(Number(value))
}

function extractWorkflowId(request) {
  if (!request || typeof request !== 'object') return null

  const candidates = [
    request.coordinationWorkflowId,
    request.workflowId,
    request.latestWorkflowId,
    request.currentWorkflowId,
    request.coordinationWorkflow?.id,
    request.coordinationWorkflow?.workflowId,
    request.latestCoordinationWorkflow?.id,
    request.latestCoordinationWorkflow?.workflowId,
  ]

  return candidates.find((value) => value != null && value !== '') ?? null
}

export default function LandlordMaintenancePage() {
  const { propertyId } = usePropertyContext()
  const { user } = useAuth()

  const [requests, setRequests] = useState([])
  const [selectedRequestId, setSelectedRequestId] = useState(null)
  const [selectedRequest, setSelectedRequest] = useState(null)
  const [history, setHistory] = useState([])
  const [latestEstimate, setLatestEstimate] = useState(null)
  const [workflow, setWorkflow] = useState(null)
  const [pageState, setPageState] = useState('loading')
  const [pageError, setPageError] = useState('')
  const [detailState, setDetailState] = useState('idle')
  const [detailError, setDetailError] = useState('')
  const [historyState, setHistoryState] = useState('idle')
  const [historyError, setHistoryError] = useState('')
  const [estimateState, setEstimateState] = useState('idle')
  const [estimateError, setEstimateError] = useState('')
  const [workflowState, setWorkflowState] = useState('idle')
  const [workflowError, setWorkflowError] = useState('')
  const [decisionNotes, setDecisionNotes] = useState('')
  const [decisionPending, setDecisionPending] = useState(false)
  const [decisionNotice, setDecisionNotice] = useState('')

  const isLandlord = user && [USER_ROLES.LANDLORD, USER_ROLES.ADMIN].includes(user.role)

  async function loadRequestDetails(requestId) {
    if (!requestId) {
      setSelectedRequest(null)
      setHistory([])
      setLatestEstimate(null)
      setWorkflow(null)
      setDetailState('idle')
      setDetailError('')
      setHistoryState('idle')
      setHistoryError('')
      setEstimateState('idle')
      setEstimateError('')
      setWorkflowState('idle')
      setWorkflowError('')
      setDecisionNotes('')
      setDecisionNotice('')
      return
    }

    setSelectedRequestId(requestId)
    setDetailState('loading')
    setDetailError('')
    setHistoryState('loading')
    setHistoryError('')
    setEstimateState('loading')
    setEstimateError('')
    setWorkflowState('loading')
    setWorkflowError('')
    setDecisionNotes('')
    setDecisionNotice('')

    try {
      const request = await getMaintenanceRequestById(requestId)
      setSelectedRequest(request)
      setDetailState('success')

      try {
        const nextHistory = await getMaintenanceHistory(requestId)
        setHistory(Array.isArray(nextHistory) ? nextHistory : [])
        setHistoryState('success')
      } catch (historyError) {
        setHistory([])
        setHistoryState('error')
        setHistoryError(
          safeErrorMessage(
            historyError,
            'Unable to load the request history. Please try again.',
          ),
        )
      }

      try {
        const latest = await getLatestEstimate(requestId)
        setLatestEstimate(latest ?? null)
        setEstimateState(latest ? 'success' : 'empty')
      } catch (estimateError) {
        setLatestEstimate(null)
        setEstimateState('error')
        setEstimateError(
          safeErrorMessage(
            estimateError,
            'Unable to load the latest estimate. Please try again.',
          ),
        )
      }

      const workflowId = extractWorkflowId(request)
      if (!workflowId) {
        setWorkflow(null)
        setWorkflowState('none')
        setWorkflowError('No coordination workflow available for this request.')
        return
      }

      try {
        const nextWorkflow = await getCoordinationWorkflow(requestId, workflowId)
        setWorkflow(nextWorkflow)
        setWorkflowState('success')
      } catch (workflowError) {
        setWorkflow(null)
        setWorkflowState('error')
        setWorkflowError(
          safeErrorMessage(
            workflowError,
            'Unable to load the coordination workflow. Please try again.',
          ),
        )
      }
    } catch (requestError) {
      setSelectedRequest(null)
      setHistory([])
      setLatestEstimate(null)
      setWorkflow(null)
      setDetailState('error')
      setDetailError(
        safeErrorMessage(
          requestError,
          'Unable to load the selected maintenance request. Please try again.',
        ),
      )
      setHistoryState('idle')
      setHistoryError('')
      setEstimateState('idle')
      setEstimateError('')
      setWorkflowState('idle')
      setWorkflowError('')
    }
  }

  async function loadRequests() {
    if (!propertyId) {
      setRequests([])
      setSelectedRequestId(null)
      setSelectedRequest(null)
      setPageState('property-required')
      setPageError('')
      return
    }

    setPageState('loading')
    setPageError('')

    try {
      const nextRequests = await getPropertyMaintenanceRequests(propertyId)
      const safeRequests = Array.isArray(nextRequests) ? nextRequests : []
      setRequests(safeRequests)

      if (safeRequests.length === 0) {
        setPageState('empty')
        setSelectedRequestId(null)
        setSelectedRequest(null)
        setHistory([])
        setLatestEstimate(null)
        setWorkflow(null)
        setDetailState('idle')
        setDetailError('')
        return
      }

      const nextSelectedId = selectedRequestId && safeRequests.some((request) => request.id === selectedRequestId)
        ? selectedRequestId
        : safeRequests[0].id

      setPageState('success')
      setSelectedRequestId(nextSelectedId)
      await loadRequestDetails(nextSelectedId)
    } catch (error) {
      setPageState('error')
      setPageError(
        safeErrorMessage(
          error,
          'Unable to load maintenance requests for this property. Please try again.',
        ),
      )
      setRequests([])
      setSelectedRequestId(null)
      setSelectedRequest(null)
      setHistory([])
      setLatestEstimate(null)
      setWorkflow(null)
      setDetailState('idle')
      setDetailError('')
    }
  }

  useEffect(() => {
    if (!isLandlord) {
      setPageState('unauthorized')
      setPageError('You do not have permission to view landlord maintenance records.')
      return undefined
    }

    loadRequests()
    return undefined
  }, [propertyId, isLandlord])

  async function handleWorkflowDecision(action) {
    if (!selectedRequest || !workflow || decisionPending) return

    const workflowId = workflow.id
    if (!workflowId) {
      setWorkflowError('This coordination workflow does not contain a valid workflow ID.')
      return
    }

    setDecisionPending(true)
    setDecisionNotice('')
    setWorkflowError('')

    try {
      const nextWorkflow = action === 'approve'
        ? await approveCoordinationWorkflow(selectedRequest.id, workflowId, decisionNotes)
        : await rejectCoordinationWorkflow(selectedRequest.id, workflowId, decisionNotes)

      setWorkflow(nextWorkflow)
      setWorkflowState('success')
      setDecisionNotice(
        action === 'approve'
          ? 'AI/workflow review approved. This does not change the maintenance request status.'
          : 'AI/workflow review rejected. This does not change the maintenance request status.',
      )
    } catch (error) {
      setWorkflowError(
        safeErrorMessage(
          error,
          'Unable to record the workflow decision. Please try again.',
        ),
      )
    } finally {
      setDecisionPending(false)
    }
  }

  const workflowRequiresDecision =
    workflow && workflow.status === 'AwaitingHumanReview' && workflow.requiresHumanApproval !== false

  return (
    <main className="maintenance-page" aria-busy={pageState === 'loading'}>
      <header className="maintenance-page__header">
        <div>
          <p className="maintenance-page__eyebrow">Landlord workspace</p>
          <h1>Maintenance &amp; support management</h1>
          <p>
            Review property maintenance issues, inspect request details, and handle AI coordination workflow decisions.
          </p>
        </div>
        <button
          type="button"
          className="button button--quiet maintenance-page__refresh"
          onClick={loadRequests}
          disabled={pageState === 'loading' || !propertyId || !isLandlord}
        >
          <span aria-hidden="true">↻</span>
          {pageState === 'loading' ? 'Refreshing...' : 'Refresh'}
        </button>
      </header>

      {!isLandlord && (
        <section className="page-state page-state--error" role="alert">
          <div className="page-state__icon" aria-hidden="true">!</div>
          <h2>Access denied</h2>
          <p>You must be signed in as a landlord or admin to view maintenance management.</p>
        </section>
      )}

      {isLandlord && !propertyId && <PropertySelectionState className="page-state" />}

      {isLandlord && propertyId && pageState === 'loading' && (
        <section className="page-state" aria-live="polite">
          <span className="loading-spinner" aria-hidden="true" />
          <h2>Loading maintenance requests</h2>
          <p>Please wait while we fetch the active property records.</p>
        </section>
      )}

      {isLandlord && propertyId && pageState === 'error' && (
        <section className="page-state page-state--error" role="alert">
          <div className="page-state__icon" aria-hidden="true">!</div>
          <h2>We could not load maintenance requests</h2>
          <p>{pageError}</p>
          <button type="button" className="button button--primary" onClick={loadRequests}>
            Try again
          </button>
        </section>
      )}

      {isLandlord && propertyId && pageState === 'empty' && (
        <section className="page-state">
          <div className="page-state__icon" aria-hidden="true">✓</div>
          <h2>No maintenance requests yet</h2>
          <p>There are no maintenance requests for the selected property.</p>
        </section>
      )}

      {isLandlord && propertyId && pageState === 'success' && (
        <div className="maintenance-layout">
          <aside className="maintenance-panel">
            <div className="maintenance-panel__header">
              <p className="maintenance-page__eyebrow">Property requests</p>
              <h2>{requests.length} request{requests.length === 1 ? '' : 's'}</h2>
            </div>

            {requests.length === 0 ? (
              <div className="page-state page-state--inline">
                <h3>No open requests</h3>
              </div>
            ) : (
              <div className="maintenance-request-list">
                {requests.map((request) => (
                  <button
                    key={request.id}
                    type="button"
                    className={`maintenance-request-card${
                      selectedRequestId === request.id ? ' maintenance-request-card--selected' : ''
                    }`}
                    onClick={() => loadRequestDetails(request.id)}
                  >
                    <div className="maintenance-request-card__topline">
                      <strong>{request.title}</strong>
                      <span className={`status-badge status-badge--${toBadgeClass(request.status)}`}>
                        {formatLabel(request.status, STATUS_LABELS)}
                      </span>
                    </div>
                    <div className="maintenance-request-card__meta">
                      <span>{formatLabel(request.category, CATEGORY_LABELS)}</span>
                      <span>{formatLabel(request.priority, PRIORITY_LABELS)}</span>
                    </div>
                    <small>Created {formatDate(request.createdAt)}</small>
                  </button>
                ))}
              </div>
            )}
          </aside>

          <section className="maintenance-panel">
            {detailState === 'loading' && (
              <div className="page-state page-state--inline" aria-live="polite">
                <span className="loading-spinner" aria-hidden="true" />
                <h3>Loading request details</h3>
              </div>
            )}

            {detailState === 'error' && (
              <div className="page-state page-state--inline page-state--error" role="alert">
                <div className="page-state__icon" aria-hidden="true">!</div>
                <h3>Request unavailable</h3>
                <p>{detailError}</p>
              </div>
            )}

            {detailState === 'success' && selectedRequest && (
              <div className="maintenance-detail">
                <div className="maintenance-detail__topline">
                  <div>
                    <p className="maintenance-page__eyebrow">Selected request</p>
                    <h3>{selectedRequest.title}</h3>
                  </div>
                  <span className={`status-badge status-badge--${toBadgeClass(selectedRequest.status)}`}>
                    {formatLabel(selectedRequest.status, STATUS_LABELS)}
                  </span>
                </div>

                <dl className="maintenance-detail__meta">
                  <div>
                    <dt>Category</dt>
                    <dd>{formatLabel(selectedRequest.category, CATEGORY_LABELS)}</dd>
                  </div>
                  <div>
                    <dt>Priority</dt>
                    <dd>{formatLabel(selectedRequest.priority, PRIORITY_LABELS)}</dd>
                  </div>
                  <div>
                    <dt>Tenant ID</dt>
                    <dd>{selectedRequest.tenantId}</dd>
                  </div>
                  <div>
                    <dt>Technician ID</dt>
                    <dd>{selectedRequest.technicianId ?? 'Unassigned'}</dd>
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

                <div className="maintenance-detail__section">
                  <h4>Description</h4>
                  <p>{selectedRequest.description || 'No description provided.'}</p>
                </div>

                {selectedRequest.tenantAccessNotes && (
                  <div className="maintenance-detail__section">
                    <h4>Tenant access notes</h4>
                    <p>{selectedRequest.tenantAccessNotes}</p>
                  </div>
                )}

                {selectedRequest.triageNotes && (
                  <div className="maintenance-detail__section">
                    <h4>Triage notes</h4>
                    <p>{selectedRequest.triageNotes}</p>
                  </div>
                )}

                {selectedRequest.assignmentNotes && (
                  <div className="maintenance-detail__section">
                    <h4>Assignment notes</h4>
                    <p>{selectedRequest.assignmentNotes}</p>
                  </div>
                )}
              </div>
            )}
          </section>

          <aside className="maintenance-panel">
            <div className="maintenance-panel__header">
              <p className="maintenance-page__eyebrow">Request activity</p>
              <h2>History</h2>
            </div>

            {historyState === 'loading' && (
              <div className="page-state page-state--inline" aria-live="polite">
                <span className="loading-spinner" aria-hidden="true" />
                <h3>Loading history</h3>
              </div>
            )}

            {historyState === 'error' && (
              <div className="page-state page-state--inline page-state--error" role="alert">
                <div className="page-state__icon" aria-hidden="true">!</div>
                <h3>Unable to load history</h3>
                <p>{historyError}</p>
              </div>
            )}

            {historyState === 'success' && history.length === 0 && (
              <div className="page-state page-state--inline">
                <h3>No history recorded</h3>
                <p>This request has no status history yet.</p>
              </div>
            )}

            {historyState === 'success' && history.length > 0 && (
              <div className="maintenance-request-list">
                {history.map((entry) => (
                  <div className="maintenance-request-card" key={entry.id}>
                    <div className="maintenance-request-card__topline">
                      <strong>{formatLabel(entry.toStatus)}</strong>
                      <span className={`status-badge status-badge--${toBadgeClass(entry.toStatus)}`}>
                        {formatLabel(entry.toStatus)}
                      </span>
                    </div>
                    <div className="maintenance-request-card__meta">
                      <span>Changed by {entry.changedByUserId ?? 'System'}</span>
                      <span>{formatDate(entry.changedAt)}</span>
                    </div>
                    {entry.notes && <small>{entry.notes}</small>}
                  </div>
                ))}
              </div>
            )}

            <div className="maintenance-panel__header" style={{ marginTop: '28px' }}>
              <p className="maintenance-page__eyebrow">Latest estimate</p>
              <h2>Repair estimate</h2>
            </div>

            {estimateState === 'loading' && (
              <div className="page-state page-state--inline" aria-live="polite">
                <span className="loading-spinner" aria-hidden="true" />
                <h3>Loading estimate</h3>
              </div>
            )}

            {estimateState === 'error' && (
              <div className="page-state page-state--inline page-state--error" role="alert">
                <div className="page-state__icon" aria-hidden="true">!</div>
                <h3>Estimate unavailable</h3>
                <p>{estimateError}</p>
              </div>
            )}

            {estimateState === 'empty' && (
              <div className="page-state page-state--inline">
                <h3>No estimate</h3>
                <p>No estimate has been submitted for this maintenance request yet.</p>
              </div>
            )}

            {estimateState === 'success' && latestEstimate && (
              <div className="maintenance-detail__section">
                <p><strong>Status:</strong> {formatLabel(latestEstimate.status)}</p>
                <p><strong>Total cost:</strong> {money(latestEstimate.totalCost)}</p>
                <p><strong>Labor:</strong> {money(latestEstimate.laborCost)}</p>
                <p><strong>Parts:</strong> {money(latestEstimate.partsCost)}</p>
                <p><strong>Additional:</strong> {money(latestEstimate.additionalCost)}</p>
                {latestEstimate.notes && <p><strong>Notes:</strong> {latestEstimate.notes}</p>}
                <p><strong>Technician ID:</strong> {latestEstimate.technicianId}</p>
                <p><strong>Submitted:</strong> {formatDate(latestEstimate.submittedAt || latestEstimate.createdAt)}</p>
              </div>
            )}

            <div className="maintenance-panel__header" style={{ marginTop: '28px' }}>
              <p className="maintenance-page__eyebrow">AI workflow</p>
              <h2>Coordination review</h2>
            </div>

            {workflowState === 'none' && (
              <div className="page-state page-state--inline">
                <h3>No coordination workflow available</h3>
                <p>No coordination workflow ID was included in the current maintenance request response.</p>
              </div>
            )}

            {workflowState === 'loading' && (
              <div className="page-state page-state--inline" aria-live="polite">
                <span className="loading-spinner" aria-hidden="true" />
                <h3>Loading workflow</h3>
              </div>
            )}

            {workflowState === 'error' && (
              <div className="page-state page-state--inline page-state--error" role="alert">
                <div className="page-state__icon" aria-hidden="true">!</div>
                <h3>Workflow unavailable</h3>
                <p>{workflowError}</p>
              </div>
            )}

            {workflowState === 'success' && workflow && (
              <div className="maintenance-detail__section">
                <p><strong>Workflow ID:</strong> {workflow.id}</p>
                <p><strong>Status:</strong> {formatLabel(workflow.status, STATUS_LABELS)}</p>
                <p><strong>Approval status:</strong> {formatLabel(workflow.approvalStatus, STATUS_LABELS)}</p>
                <p><strong>Requires human approval:</strong> {workflow.requiresHumanApproval ? 'Yes' : 'No'}</p>
                {workflow.planSummary && <p><strong>Plan summary:</strong> {workflow.planSummary}</p>}
                {workflow.executionSummary && <p><strong>Execution summary:</strong> {workflow.executionSummary}</p>}
                {workflow.finalResultJson && <p><strong>Result:</strong> {workflow.finalResultJson}</p>}

                {workflowRequiresDecision && (
                  <div style={{ marginTop: '16px' }}>
                    <p className="maintenance-page__eyebrow" style={{ marginBottom: '10px' }}>
                      AI / workflow review decision
                    </p>
                    <label>
                      <span>Decision notes</span>
                      <textarea
                        value={decisionNotes}
                        onChange={(event) => setDecisionNotes(event.target.value)}
                        rows={4}
                        placeholder="Optional decision notes for the AI coordination review"
                      />
                    </label>
                    <div style={{ display: 'flex', gap: '8px', marginTop: '12px' }}>
                      <button
                        type="button"
                        className="button button--primary"
                        onClick={() => handleWorkflowDecision('approve')}
                        disabled={decisionPending}
                      >
                        {decisionPending ? 'Approving...' : 'Approve'}
                      </button>
                      <button
                        type="button"
                        className="button button--quiet"
                        onClick={() => handleWorkflowDecision('reject')}
                        disabled={decisionPending}
                      >
                        {decisionPending ? 'Rejecting...' : 'Reject'}
                      </button>
                    </div>
                  </div>
                )}

                {!workflowRequiresDecision && workflow.approvalStatus !== 'Pending' && (
                  <p style={{ marginTop: '12px' }}>
                    <strong>Review outcome:</strong> {formatLabel(workflow.approvalStatus, STATUS_LABELS)}
                  </p>
                )}

                {decisionNotice && (
                  <div className="page-notice" role="status" style={{ marginTop: '12px' }}>
                    <span className="page-notice__icon" aria-hidden="true">✓</span>
                    <span>{decisionNotice}</span>
                  </div>
                )}

                {workflowError && (
                  <div className="form-message form-message--error" style={{ marginTop: '12px' }}>
                    {workflowError}
                  </div>
                )}
              </div>
            )}
          </aside>
        </div>
      )}
    </main>
  )
}
