import { useCallback, useEffect, useRef, useState } from 'react'
import { useAuth } from '../../auth/useAuth.js'
import { USER_ROLES } from '../../auth/authModel.js'
import usePropertyContext from '../../../shared/property/usePropertyContext.js'
import {
  approveCoordinationWorkflow,
  assignMaintenanceTechnician,
  getMaintenanceTechnicians,
  getLandlordMaintenanceProperties,
  getLatestCoordinationWorkflow,
  getLatestEstimate,
  getMaintenanceHistory,
  getMaintenanceRequestById,
  getPropertyMaintenanceRequests,
  markMaintenanceEstimatePending,
  MaintenanceApiError,
  rejectCoordinationWorkflow,
  reviewRepairEstimate,
  startCoordinationWorkflow,
  triageMaintenanceRequest,
} from '../services/maintenanceApiService.js'
import {
  MAINTENANCE_CATEGORY,
  MAINTENANCE_PRIORITY,
  MAINTENANCE_STATUS,
  maintenanceEnumLabel,
} from '../services/maintenanceEnums.js'
import AiCoordinationCard from '../components/AiCoordinationCard.jsx'
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

const ESTIMATE_STATUS_LABELS = {
  0: 'Draft',
  1: 'Submitted',
  2: 'Revision Requested',
  3: 'Approved',
  4: 'Rejected',
  5: 'Superseded',
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

function historyActorLabel(entry) {
  if (entry.changedByName) {
    const role = entry.changedByRole === 'MaintenanceTechnician'
      ? 'Technician'
      : formatLabel(entry.changedByRole)
    return entry.changedByRole ? `${role} · ${entry.changedByName}` : entry.changedByName
  }
  return entry.changedByRole ? formatLabel(entry.changedByRole) : 'System'
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

export default function LandlordMaintenancePage() {
  const { propertyId } = usePropertyContext()
  const { user } = useAuth()

  const [properties, setProperties] = useState([])
  const [selectedPropertyId, setSelectedPropertyId] = useState('')
  const [propertyState, setPropertyState] = useState('loading')
  const [propertyError, setPropertyError] = useState('')
  const [propertyLoadVersion, setPropertyLoadVersion] = useState(0)
  const [requests, setRequests] = useState([])
  const [selectedRequestId, setSelectedRequestId] = useState(null)
  const selectedRequestIdRef = useRef(null)
  const detailLoadVersionRef = useRef(0)
  const coordinationOperationRef = useRef(0)
  const coordinationPendingRef = useRef(false)
  const coordinationRequestsRef = useRef(new Map())
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
  const [technicians, setTechnicians] = useState([])
  const [technicianState, setTechnicianState] = useState('idle')
  const [technicianError, setTechnicianError] = useState('')
  const [selectedTechnicianId, setSelectedTechnicianId] = useState('')
  const [assignmentNotes, setAssignmentNotes] = useState('')
  const [triageCategory, setTriageCategory] = useState('')
  const [triagePriority, setTriagePriority] = useState('')
  const [triageNotes, setTriageNotes] = useState('')
  const [requestActionPending, setRequestActionPending] = useState(false)
  const [requestActionError, setRequestActionError] = useState('')
  const [requestActionNotice, setRequestActionNotice] = useState('')
  const [estimateReviewPending, setEstimateReviewPending] = useState(false)
  const [estimateReviewNotes, setEstimateReviewNotes] = useState('')

  const isLandlord = user && [USER_ROLES.LANDLORD, USER_ROLES.ADMIN].includes(user.role)
  const activePropertyId = propertyId || selectedPropertyId

  useEffect(() => () => {
    ++detailLoadVersionRef.current
    ++coordinationOperationRef.current
  }, [])

  useEffect(() => {
    if (!isLandlord || propertyId) return undefined

    let active = true

    getLandlordMaintenanceProperties()
      .then((nextProperties) => {
        if (!active) return
        if (!Array.isArray(nextProperties)) {
          throw new TypeError('The property service returned an invalid property list.')
        }
        setProperties(nextProperties)
        setPropertyState(nextProperties.length ? 'success' : 'empty')
      })
      .catch((error) => {
        if (!active) return
        setPropertyState('error')
        setPropertyError(error.message || 'Unable to load your properties.')
      })

    return () => {
      active = false
    }
  }, [isLandlord, propertyId, propertyLoadVersion])

  function retryPropertyLoad() {
    setPropertyState('loading')
    setPropertyError('')
    setPropertyLoadVersion((version) => version + 1)
  }

  const updateSelectedRequestId = useCallback((requestId) => {
    selectedRequestIdRef.current = requestId
    setSelectedRequestId(requestId)
  }, [])

  const loadRequestDetails = useCallback(async (requestId) => {
    const loadVersion = ++detailLoadVersionRef.current
    const isCurrent = () => detailLoadVersionRef.current === loadVersion
    ++coordinationOperationRef.current
    coordinationPendingRef.current = false
    setDecisionPending(false)
    setWorkflow(null)
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
      setEstimateReviewNotes('')
      setRequestActionError('')
      setRequestActionNotice('')
      return
    }

    updateSelectedRequestId(requestId)
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
    setEstimateReviewNotes('')
    setRequestActionError('')
    setRequestActionNotice('')

    try {
      const request = await getMaintenanceRequestById(requestId)
      if (!isCurrent()) return
      setSelectedRequest(request)
      setDetailState('success')
      setTriageCategory(request.category)
      setTriagePriority(request.priority)
      setTriageNotes(request.triageNotes ?? '')
      setAssignmentNotes(request.assignmentNotes ?? '')
      setSelectedTechnicianId(request.technicianId ?? '')
      setTechnicianError('')
      if (request.status === 'Triaged') {
        setTechnicianState('loading')
        try {
          const nextTechnicians = await getMaintenanceTechnicians()
          if (!isCurrent()) return
          setTechnicians(Array.isArray(nextTechnicians) ? nextTechnicians : [])
          setTechnicianState(nextTechnicians?.length ? 'success' : 'empty')
        } catch (technicianLoadError) {
          if (!isCurrent()) return
          setTechnicians([])
          setTechnicianState('error')
          setTechnicianError(technicianLoadError.message || 'Unable to load maintenance technicians.')
        }
      } else {
        setTechnicians([])
        setTechnicianState('idle')
      }

      try {
        const nextHistory = await getMaintenanceHistory(requestId)
        if (!isCurrent()) return
        setHistory(Array.isArray(nextHistory) ? nextHistory : [])
        setHistoryState('success')
      } catch (historyError) {
        if (!isCurrent()) return
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
        if (!isCurrent()) return
        setLatestEstimate(latest ?? null)
        setEstimateState(latest ? 'success' : 'empty')
      } catch (estimateError) {
        if (!isCurrent()) return
        setLatestEstimate(null)
        if (estimateError instanceof MaintenanceApiError && estimateError.statusCode === 404) {
          setEstimateState('empty')
          setEstimateError('')
        } else {
          setEstimateState('error')
          setEstimateError(
            safeErrorMessage(
              estimateError,
              'Unable to load the latest estimate. Please try again.',
            ),
          )
        }
      }

      try {
        // A refresh/reselection joins the same request's ongoing operation instead
        // of briefly showing an empty analysis or allowing another POST.
        const ongoing = coordinationRequestsRef.current.get(requestId)
        if (ongoing) {
          setWorkflowState(ongoing.analyzing ? 'analyzing' : 'loading')
          setDecisionPending(true)
        }
        const nextWorkflow = ongoing ? await ongoing.promise : await getLatestCoordinationWorkflow(requestId)
        if (!isCurrent()) return
        setWorkflow(nextWorkflow ?? null)
        setWorkflowState(nextWorkflow ? 'success' : 'none')
        setWorkflowError('')
      } catch {
        if (!isCurrent()) return
        setWorkflow(null)
        setWorkflowState('error')
        setWorkflowError('AI analysis unavailable')
      } finally {
        if (isCurrent()) setDecisionPending(false)
      }
    } catch (requestError) {
      if (!isCurrent()) return
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
  }, [updateSelectedRequestId])

  const loadRequests = useCallback(async () => {
    if (!activePropertyId) {
      setRequests([])
      updateSelectedRequestId(null)
      setSelectedRequest(null)
      setPageState('property-required')
      setPageError('')
      return
    }

    setPageState('loading')
    setPageError('')

    try {
      const nextRequests = await getPropertyMaintenanceRequests(activePropertyId)
      const safeRequests = Array.isArray(nextRequests) ? nextRequests : []
      setRequests(safeRequests)

      if (safeRequests.length === 0) {
        setPageState('empty')
        updateSelectedRequestId(null)
        setSelectedRequest(null)
        setHistory([])
        setLatestEstimate(null)
        setWorkflow(null)
        setDetailState('idle')
        setDetailError('')
        return
      }

      const currentRequestId = selectedRequestIdRef.current
      const nextSelectedId = currentRequestId && safeRequests.some((request) => request.id === currentRequestId)
        ? currentRequestId
        : safeRequests[0].id

      setPageState('success')
      updateSelectedRequestId(nextSelectedId)
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
      updateSelectedRequestId(null)
      setSelectedRequest(null)
      setHistory([])
      setLatestEstimate(null)
      setWorkflow(null)
      setDetailState('idle')
      setDetailError('')
    }
  }, [activePropertyId, loadRequestDetails, updateSelectedRequestId])

  useEffect(() => {
    if (!isLandlord) return undefined

    const loadTimer = window.setTimeout(() => {
      void loadRequests()
    }, 0)

    return () => window.clearTimeout(loadTimer)
  }, [isLandlord, loadRequests])

  async function handleWorkflowDecision(action) {
    if (!selectedRequest || !workflow?.id || coordinationPendingRef.current ||
        coordinationRequestsRef.current.has(selectedRequest.id) ||
        workflow.status !== 'AwaitingHumanReview' || workflow.approvalStatus !== 'Pending') return
    const requestId = selectedRequest.id
    const operation = ++coordinationOperationRef.current
    const isCurrent = () => coordinationOperationRef.current === operation &&
      selectedRequestIdRef.current === requestId
    coordinationPendingRef.current = true
    setDecisionPending(true)
    setDecisionNotice('')
    setWorkflowError('')
    const operationPromise = action === 'approve'
      ? approveCoordinationWorkflow(requestId, workflow.id, decisionNotes)
      : rejectCoordinationWorkflow(requestId, workflow.id, decisionNotes)
    coordinationRequestsRef.current.set(requestId, { promise: operationPromise, analyzing: false })
    try {
      const nextWorkflow = await operationPromise
      if (!isCurrent()) return
      setWorkflow(nextWorkflow)
      setWorkflowState('success')
    } catch {
      if (isCurrent()) setWorkflowError('Unable to record the recommendation review.')
    } finally {
      if (coordinationRequestsRef.current.get(requestId)?.promise === operationPromise) {
        coordinationRequestsRef.current.delete(requestId)
      }
      if (isCurrent()) {
        coordinationPendingRef.current = false
        setDecisionPending(false)
      }
    }
  }

  async function loadCoordinationWorkflow(analyze) {
    if (!selectedRequest || coordinationPendingRef.current || coordinationRequestsRef.current.has(selectedRequest.id)) return
    const requestId = selectedRequest.id
    const operation = ++coordinationOperationRef.current
    const isCurrent = () => coordinationOperationRef.current === operation &&
      selectedRequestIdRef.current === requestId
    coordinationPendingRef.current = true
    setDecisionPending(true)
    setWorkflowError('')
    setDecisionNotice('')
    setWorkflowState(analyze ? 'analyzing' : 'loading')
    const operationPromise = analyze
      ? startCoordinationWorkflow(requestId)
      : getLatestCoordinationWorkflow(requestId)
    coordinationRequestsRef.current.set(requestId, { promise: operationPromise, analyzing: analyze })
    try {
      const nextWorkflow = await operationPromise
      if (!isCurrent()) return
      setWorkflow(nextWorkflow ?? null)
      setWorkflowState(nextWorkflow ? 'success' : 'none')
    } catch {
      if (isCurrent()) {
        setWorkflowState('error')
        setWorkflowError('AI analysis unavailable')
      }
    } finally {
      if (coordinationRequestsRef.current.get(requestId)?.promise === operationPromise) {
        coordinationRequestsRef.current.delete(requestId)
      }
      if (isCurrent()) {
        coordinationPendingRef.current = false
        setDecisionPending(false)
      }
    }
  }

  function useSuggestionInTriage(result) {
    if (selectedRequest?.status !== 'Submitted') return
    if (result.suggestedCategory !== null) setTriageCategory(result.suggestedCategory)
    // Keep a human Emergency selection when AI proposes a lower priority.
    const keepEmergency = triagePriority === 'Emergency' || selectedRequest.priority === 'Emergency'
    if (result.suggestedPriority !== null && !keepEmergency) setTriagePriority(result.suggestedPriority)
    const keptPriorityNote = keepEmergency
      ? (triagePriority === 'Emergency' ? ' Emergency priority was kept.' : ' Your selected priority was kept.')
      : ''
    setDecisionNotice('Triage suggestions filled in for review.' + keptPriorityNote + ' Submit triage separately to save.')
  }

  async function handleRequestTransition(action) {
    if (!selectedRequest || requestActionPending) return
    setRequestActionPending(true)
    setRequestActionError('')
    setRequestActionNotice('')
    try {
      if (action === 'triage') {
        await triageMaintenanceRequest(selectedRequest.id, {
          category: triageCategory,
          priority: triagePriority,
          triageNotes,
        })
      } else if (action === 'assign') {
        await assignMaintenanceTechnician(selectedRequest.id, {
          technicianId: selectedTechnicianId,
          assignmentNotes,
        })
      } else {
        await markMaintenanceEstimatePending(selectedRequest.id)
      }
      await loadRequests()
      setRequestActionNotice(
        action === 'triage' ? 'Request triaged.' :
          action === 'assign' ? 'Technician assigned.' : 'Estimate requested from the technician.',
      )
    } catch (error) {
      setRequestActionError(
        safeErrorMessage(error, 'Unable to update the maintenance request. Please try again.'),
      )
    } finally {
      setRequestActionPending(false)
    }
  }

  async function handleEstimateReview(action) {
    if (!selectedRequest || !latestEstimate || estimateReviewPending) return
    setEstimateReviewPending(true)
    setRequestActionError('')
    setRequestActionNotice('')
    try {
      await reviewRepairEstimate(selectedRequest.id, latestEstimate.id, action, estimateReviewNotes)
      await loadRequests()
      setRequestActionNotice(
        action === 'approve' ? 'Repair estimate approved.' :
          action === 'reject' ? 'Repair estimate rejected.' : 'Revision requested from the technician.',
      )
    } catch (error) {
      setRequestActionError(
        safeErrorMessage(error, 'Unable to review the estimate. Please try again.'),
      )
    } finally {
      setEstimateReviewPending(false)
    }
  }

  const isPageLoading = Boolean(isLandlord && pageState === 'loading')

  return (
    <main className="maintenance-page maintenance-page--landlord" aria-busy={isPageLoading}>
      <header className="maintenance-page__header">
        <div>
          <h1>Maintenance &amp; support management</h1>
          <p>
            Review property maintenance issues and keep every maintenance decision under human control.
          </p>
        </div>
        <button
          type="button"
          className="button button--quiet maintenance-page__refresh"
          onClick={loadRequests}
          disabled={isPageLoading || !activePropertyId || !isLandlord}
        >
          <span aria-hidden="true">↻</span>
          {isPageLoading ? 'Refreshing...' : 'Refresh'}
        </button>
      </header>

      {!isLandlord && (
        <section className="page-state page-state--error" role="alert">
          <div className="page-state__icon" aria-hidden="true">!</div>
          <h2>Access denied</h2>
          <p>You must be signed in as a landlord or admin to view maintenance management.</p>
        </section>
      )}

      {isLandlord && !activePropertyId && propertyState === 'loading' && (
        <section className="page-state" role="status" aria-live="polite">
          <span className="loading-spinner" aria-hidden="true" />
          <h2>Loading your properties</h2>
          <p>Select one of your properties to review its maintenance requests.</p>
        </section>
      )}

      {isLandlord && !activePropertyId && propertyState === 'error' && (
        <section className="page-state page-state--error" role="alert">
          <h2>We could not load your properties</h2>
          <p>{propertyError}</p>
          <button type="button" className="button button--primary" onClick={retryPropertyLoad}>
            Try again
          </button>
        </section>
      )}

      {isLandlord && !activePropertyId && propertyState === 'empty' && (
        <section className="page-state">
          <h2>No properties available</h2>
          <p>Create or manage a property before reviewing property-scoped maintenance requests.</p>
        </section>
      )}

      {isLandlord && !propertyId && propertyState === 'success' && (
        <section className="maintenance-panel maintenance-property-selector">
          <label>
            Property
            <select
              aria-label="Property"
              value={selectedPropertyId}
              onChange={(event) => setSelectedPropertyId(event.target.value)}
            >
              <option value="">Choose a property</option>
              {properties.map((property) => (
                <option key={property.id} value={property.id}>
                  {[property.title, property.address, property.city].filter(Boolean).join(' — ')}
                </option>
              ))}
            </select>
          </label>
        </section>
      )}

      {isLandlord && activePropertyId && pageState === 'loading' && (
        <section className="page-state" aria-live="polite">
          <span className="loading-spinner" aria-hidden="true" />
          <h2>Loading maintenance requests</h2>
          <p>Please wait while we fetch the active property records.</p>
        </section>
      )}

      {isLandlord && activePropertyId && pageState === 'error' && (
        <section className="page-state page-state--error" role="alert">
          <div className="page-state__icon" aria-hidden="true">!</div>
          <h2>We could not load maintenance requests</h2>
          <p>{pageError}</p>
          <button type="button" className="button button--primary" onClick={loadRequests}>
            Try again
          </button>
        </section>
      )}

      {isLandlord && activePropertyId && pageState === 'empty' && (
        <section className="page-state">
          <div className="page-state__icon" aria-hidden="true">✓</div>
          <h2>No maintenance requests yet</h2>
          <p>There are no maintenance requests for the selected property.</p>
        </section>
      )}

      {isLandlord && activePropertyId && pageState === 'success' && (
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
                        {maintenanceEnumLabel(request.status, MAINTENANCE_STATUS)}
                      </span>
                    </div>
                    <div className="maintenance-request-card__meta">
                      <span>{maintenanceEnumLabel(request.category, MAINTENANCE_CATEGORY)}</span>
                      <span>{maintenanceEnumLabel(request.priority, MAINTENANCE_PRIORITY)}</span>
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
                    <h2>{selectedRequest.title}</h2>
                  </div>
                  <span className={`status-badge status-badge--${toBadgeClass(selectedRequest.status)}`}>
                    {maintenanceEnumLabel(selectedRequest.status, MAINTENANCE_STATUS)}
                  </span>
                </div>

                <dl className="maintenance-detail__meta">
                  <div>
                    <dt>Category</dt>
                    <dd>{maintenanceEnumLabel(selectedRequest.category, MAINTENANCE_CATEGORY)}</dd>
                  </div>
                  <div>
                    <dt>Priority</dt>
                    <dd>{maintenanceEnumLabel(selectedRequest.priority, MAINTENANCE_PRIORITY)}</dd>
                  </div>
                  <div>
                    <dt>Tenant</dt>
                    <dd>{selectedRequest.tenantName || 'Tenant'}</dd>
                  </div>
                  <div>
                    <dt>Technician</dt>
                    <dd>{selectedRequest.assignedTechnicianName || 'Unassigned'}</dd>
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

            {detailState === 'success' && selectedRequest && <AiCoordinationCard
              request={selectedRequest}
              workflow={workflow}
              state={workflowState}
              pending={decisionPending}
              error={workflowError}
              notice={decisionNotice}
              decisionNotes={decisionNotes}
              onDecisionNotesChange={setDecisionNotes}
              onAnalyze={() => loadCoordinationWorkflow(true)}
              onRefresh={() => loadCoordinationWorkflow(false)}
              onDecision={handleWorkflowDecision}
              onUseSuggestions={selectedRequest.status === 'Submitted' ? useSuggestionInTriage : undefined}
            />}

            {detailState === 'success' && selectedRequest && <div className="maintenance-request-actions-heading">
              <h3>Request actions</h3>
              <p>Review and submit maintenance changes separately.</p>
            </div>}

            {detailState === 'success' && selectedRequest?.status === 'Submitted' && (
              <section className="maintenance-detail__section" aria-label="Triage request">
                <h4>Triage request</h4>
                <div className="maintenance-form">
                  <div className="maintenance-form__row">
                    <label>
                      Category
                      <select value={triageCategory} onChange={(event) => setTriageCategory(event.target.value)}>
                        {Object.keys(MAINTENANCE_CATEGORY.byName).map((category) => (
                          <option key={category} value={category}>{maintenanceEnumLabel(category, MAINTENANCE_CATEGORY)}</option>
                        ))}
                      </select>
                    </label>
                    <label>
                      Priority
                      <select value={triagePriority} onChange={(event) => setTriagePriority(event.target.value)}>
                        {Object.keys(MAINTENANCE_PRIORITY.byName).map((priority) => (
                          <option key={priority} value={priority}>{priority}</option>
                        ))}
                      </select>
                    </label>
                  </div>
                  <label>
                    Triage notes
                    <textarea value={triageNotes} onChange={(event) => setTriageNotes(event.target.value)} rows={3} />
                  </label>
                  <button
                    type="button"
                    className="button button--primary"
                    onClick={() => handleRequestTransition('triage')}
                    disabled={requestActionPending}
                  >
                    {requestActionPending ? 'Saving...' : 'Triage request'}
                  </button>
                </div>
              </section>
            )}

            {detailState === 'success' && selectedRequest?.status === 'Triaged' && (
              <section className="maintenance-detail__section" aria-label="Assign technician">
                <h4>Assign a maintenance technician</h4>
                {technicianState === 'loading' && <p role="status">Loading active technicians…</p>}
                {technicianState === 'error' && <p role="alert">{technicianError}</p>}
                {technicianState === 'empty' && <p>No active maintenance technicians are available.</p>}
                {technicianState === 'success' && (
                  <div className="maintenance-form">
                    <label>
                      Technician
                      <select
                        aria-label="Maintenance technician"
                        value={selectedTechnicianId}
                        onChange={(event) => setSelectedTechnicianId(event.target.value)}
                      >
                        <option value="">Choose a technician</option>
                        {technicians.map((technician) => (
                          <option key={technician.id} value={technician.id}>
                            {technician.name || technician.fullName || 'Technician'}
                          </option>
                        ))}
                      </select>
                    </label>
                    <label>
                      Assignment notes
                      <textarea value={assignmentNotes} onChange={(event) => setAssignmentNotes(event.target.value)} rows={3} />
                    </label>
                    <button
                      type="button"
                      className="button button--primary"
                      onClick={() => handleRequestTransition('assign')}
                      disabled={requestActionPending || !selectedTechnicianId}
                    >
                      {requestActionPending ? 'Assigning…' : 'Assign technician'}
                    </button>
                  </div>
                )}
              </section>
            )}

            {detailState === 'success' && selectedRequest?.status === 'Assigned' && (
              <section className="maintenance-detail__section">
                <h4>Estimate workflow</h4>
                <p>Request a repair estimate from the assigned technician to continue.</p>
                <button
                  type="button"
                  className="button button--primary"
                  onClick={() => handleRequestTransition('estimate-pending')}
                  disabled={requestActionPending}
                >
                  {requestActionPending ? 'Requesting…' : 'Request estimate'}
                </button>
              </section>
            )}

            {requestActionError && <p role="alert" className="form-message form-message--error">{requestActionError}</p>}
            {requestActionNotice && <p role="status" className="page-notice">{requestActionNotice}</p>}
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
                      <strong>{maintenanceEnumLabel(entry.toStatus, MAINTENANCE_STATUS)}</strong>
                      <span className={`status-badge status-badge--${toBadgeClass(maintenanceEnumLabel(entry.toStatus, MAINTENANCE_STATUS))}`}>
                        {maintenanceEnumLabel(entry.toStatus, MAINTENANCE_STATUS)}
                      </span>
                    </div>
                    <div className="maintenance-request-card__meta">
                      <span>Changed by {historyActorLabel(entry)}</span>
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
                <p><strong>Status:</strong> {formatLabel(latestEstimate.status, ESTIMATE_STATUS_LABELS)}</p>
                <p><strong>Total cost:</strong> {money(latestEstimate.totalCost)}</p>
                <p><strong>Labor:</strong> {money(latestEstimate.laborCost)}</p>
                <p><strong>Parts:</strong> {money(latestEstimate.partsCost)}</p>
                <p><strong>Additional:</strong> {money(latestEstimate.additionalCost)}</p>
                {latestEstimate.notes && <p><strong>Notes:</strong> {latestEstimate.notes}</p>}
                <p><strong>Technician:</strong> {selectedRequest.assignedTechnicianName || 'Unassigned'}</p>
                <p><strong>Submitted:</strong> {formatDate(latestEstimate.submittedAt || latestEstimate.createdAt)}</p>
                {selectedRequest?.status === 'AwaitingLandlordApproval' &&
                  (latestEstimate.status === 1 || latestEstimate.status === 'Submitted') && (
                    <div className="maintenance-form" style={{ marginTop: '14px' }}>
                      <label>
                        Review notes
                        <textarea
                          value={estimateReviewNotes}
                          onChange={(event) => setEstimateReviewNotes(event.target.value)}
                          rows={3}
                        />
                      </label>
                      <div className="maintenance-review-actions">
                        <button
                          type="button"
                          className="button button--primary"
                          onClick={() => handleEstimateReview('approve')}
                          disabled={estimateReviewPending}
                        >
                          {estimateReviewPending ? 'Saving…' : 'Approve estimate'}
                        </button>
                        <button
                          type="button"
                          className="button button--quiet"
                          onClick={() => handleEstimateReview('reject')}
                          disabled={estimateReviewPending}
                        >
                          Reject estimate
                        </button>
                        <button
                          type="button"
                          className="button button--quiet"
                          onClick={() => handleEstimateReview('request-revision')}
                          disabled={estimateReviewPending}
                        >
                          Request revision
                        </button>
                      </div>
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
