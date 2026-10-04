import { useEffect, useRef, useState } from 'react'
import { ApiError } from '../../../core/api/apiClient.js'
import { getMyProperties } from '../../properties/services/propertyApiService.js'
import { AppCard, EmptyState, ErrorState, LoadingState, PageHeader, StatusBadge } from '../../../shared/ui/States.jsx'
import { getPricingHistory, getPricingWorkflow, startPricingAnalysis } from '../services/pricingAnalysisApiService.js'
import '../pricingAnalysis.css'
import PricingLeaseNavigation from '../../rentalOffers/PricingLeaseNavigation.jsx'
import { friendlyStepLabel, friendlyStepSummary, workflowStepStatus } from '../workflowPresentation.js'

const workflowStatuses = ['Pending', 'Running', 'Completed', 'Failed']

function errorMessage(error, fallback) {
  if (!(error instanceof ApiError)) return fallback
  if (error.statusCode === 401) return 'Your session has expired. Please sign in again.'
  if (error.statusCode === 403) return 'You do not have permission to access this property.'
  if (error.statusCode === 404) return 'This property or analysis could not be found.'
  if (error.statusCode === 409) return 'This analysis conflicts with the current property state. Please refresh and try again.'
  if (error.statusCode === 400) return error.message
  return fallback
}

function date(value) {
  if (!value) return '—'
  const timestamp = new Date(value)
  return Number.isNaN(timestamp.getTime()) ? '—' : timestamp.toLocaleString()
}

function amount(value) {
  return value == null || !Number.isFinite(Number(value)) ? '—' : new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(value)
}

function WorkflowDetails({ workflow, property, onRefresh, refreshing }) {
  const result = workflow.result
  const status = workflowStatuses[workflow.status] ?? 'Unknown'
  const insufficient = workflow.status === 2 && result && result.recommendedMinRent == null && result.recommendedMaxRent == null
  const evidence = result?.evidenceSufficiency ?? workflow.evidenceSufficiency
  const confidence = result?.confidence ?? workflow.confidence

  const noRecommendation = Boolean(insufficient)
  const countFromStep = workflow.steps?.map((step) => step.outputSummary?.match(/Eligible comparable evidence collected:\s*(\d+)/i)?.[1]).find((value) => value != null)
  const comparableCount = result?.comparablePropertiesFound ?? result?.comparablePropertyCount ?? result?.comparablesCount ?? countFromStep
  const confidenceLabel = confidence ? `${String(confidence).charAt(0)}${String(confidence).slice(1).toLowerCase()}` : null

  return <AppCard className="pricing-details">
    <div className="pricing-card-heading">
      <div><h2>Rental Price Analysis</h2><p>Last analyzed {date(workflow.completedAt ?? workflow.createdAt)}</p></div>
      <StatusBadge tone={workflow.status === 3 ? 'danger' : noRecommendation ? 'neutral' : workflow.status === 2 ? 'success' : 'progress'}>{workflow.status === 2 && noRecommendation ? 'Recommendation unavailable' : status}</StatusBadge>
    </div>
    {workflow.status <= 1 && <p role="status">Analysis is {status.toLowerCase()}. <button className="shared-button shared-button--outline" type="button" onClick={onRefresh} disabled={refreshing}>{refreshing ? 'Refreshing…' : 'Refresh status'}</button></p>}
    {workflow.status === 3 && <p className="shared-notice shared-notice--error" role="alert">{workflow.errorMessage || 'The analysis could not be completed. Please try again.'}</p>}
    {noRecommendation && <p className="shared-notice" role="status">Not enough comparable rental properties were found to produce a reliable pricing recommendation.</p>}
    {result && (result.recommendedMinRent != null || result.recommendedMaxRent != null) && <p className="pricing-recommendation">Recommended rent range: <strong>{amount(result.recommendedMinRent)} – {amount(result.recommendedMaxRent)}</strong></p>}
    {property && <section className="pricing-property-summary"><h3>Property</h3><p>{[property.city, property.bedrooms != null && `${property.bedrooms} bedrooms`, property.bathrooms != null && `${property.bathrooms} bathrooms`].filter(Boolean).join(' · ') || property.title}</p></section>}
    <div className="pricing-metrics">
      {comparableCount != null && <div><span>Comparable properties found</span><strong>{comparableCount}</strong></div>}
      {confidenceLabel && <div><span>Confidence</span><strong>{confidenceLabel}</strong></div>}
    </div>
    <details className="pricing-audit-details">
      <summary>View Analysis Details</summary>
      <div className="pricing-audit-details__content">
    <div className="pricing-card-heading">
      <div><h3>Execution summary</h3><p>Created {date(workflow.createdAt)}</p></div>
      <StatusBadge tone={workflow.status === 2 ? 'success' : workflow.status === 3 ? 'danger' : 'progress'}>{status}</StatusBadge>
    </div>
    {insufficient && <p className="shared-notice" role="status">Analysis completed with insufficient evidence for a numeric recommendation.</p>}
    {(result || evidence || confidence) && <>
      <div className="pricing-metrics">
        <div><span>Evidence level</span><strong>{evidence ?? '—'}</strong></div>
        <div><span>Confidence</span><strong>{confidence ?? '—'}</strong></div>
        {result && <><div><span>Recommended lower bound</span><strong>{amount(result.recommendedMinRent)}</strong></div>
        <div><span>Recommended upper bound</span><strong>{amount(result.recommendedMaxRent)}</strong></div></>}
      </div>
    </>}
    {result && <>
      {result.rationale && <section><h3>Result summary</h3><p>{result.rationale}</p></section>}
      {result.limitations?.length > 0 && <section><h3>Limitations</h3><ul>{result.limitations.map((item, index) => <li key={index}>{item}</li>)}</ul></section>}
      {result.warnings?.length > 0 && <section><h3>Warnings</h3><ul>{result.warnings.map((item, index) => <li key={index}>{item}</li>)}</ul></section>}
      {result.citedEvidenceRefs?.length > 0 && <section><h3>Evidence references</h3><ul>{result.citedEvidenceRefs.map((ref) => <li key={ref}>{ref}</li>)}</ul></section>}
    </>}
    <dl className="pricing-dates"><div><dt>Started</dt><dd>{date(workflow.startedAt)}</dd></div><div><dt>Completed</dt><dd>{date(workflow.completedAt)}</dd></div></dl>
    {workflow.steps?.length > 0 && <section><h3>Workflow steps</h3><ol className="pricing-steps">{[...workflow.steps].sort((a, b) => a.order - b.order).map((step) => <li key={step.order}><div className="pricing-card-heading"><strong><span className="pricing-step-number">{step.order}.</span> {friendlyStepLabel(step.name)}</strong><StatusBadge tone={step.status === 2 ? 'success' : step.status === 3 ? 'danger' : step.status === 4 ? 'neutral' : 'progress'}>{workflowStepStatus(step.status)}</StatusBadge></div>{friendlyStepSummary(step) && <p>{friendlyStepSummary(step)}</p>}{step.validationSummary && <p>Validation: {step.validationSummary}</p>}{step.status === 3 && step.errorMessage && <p>{step.errorMessage}</p>}</li>)}</ol></section>}
      </div>
    </details>
  </AppCard>
}

export default function PricingAnalysisPage() {
  const [propertiesState, setPropertiesState] = useState({ status: 'loading', items: [], error: '' })
  const [propertyId, setPropertyId] = useState('')
  const [historyState, setHistoryState] = useState({ propertyId: '', status: 'idle', items: [], error: '' })
  const [historyReload, setHistoryReload] = useState(0)
  const [detailState, setDetailState] = useState({ propertyId: '', status: 'idle', workflow: null, error: '' })
  const [submitting, setSubmitting] = useState(false)
  const [actionError, setActionError] = useState('')
  const detailRequest = useRef(0)

  useEffect(() => {
    let active = true
    getMyProperties().then((items) => {
      if (active) setPropertiesState({ status: 'ready', items, error: '' })
    }).catch((error) => {
      if (active) setPropertiesState({ status: 'error', items: [], error: errorMessage(error, 'Unable to load your properties.') })
    })
    return () => { active = false }
  }, [])

  useEffect(() => {
    if (!propertyId) return undefined
    let active = true
    getPricingHistory(propertyId).then((items) => {
      if (active) setHistoryState({ propertyId, status: 'ready', items, error: '' })
    }).catch((error) => {
      if (active) setHistoryState({ propertyId, status: 'error', items: [], error: errorMessage(error, 'Unable to load pricing analysis history.') })
    })
    return () => { active = false }
  }, [propertyId, historyReload])

  async function openWorkflow(id, selectedPropertyId = propertyId) {
    const request = ++detailRequest.current
    setDetailState({ propertyId: selectedPropertyId, status: 'loading', workflow: null, error: '' })
    try {
      const workflow = await getPricingWorkflow(id)
      if (request === detailRequest.current) setDetailState((current) => current.propertyId === selectedPropertyId ? { propertyId: selectedPropertyId, status: 'ready', workflow, error: '' } : current)
    } catch (error) {
      if (request === detailRequest.current) setDetailState((current) => current.propertyId === selectedPropertyId ? { propertyId: selectedPropertyId, status: 'error', workflow: null, error: errorMessage(error, 'Unable to load the pricing analysis.') } : current)
    }
  }

  async function start() {
    if (!propertyId || submitting) return
    const selectedPropertyId = propertyId
    ++detailRequest.current
    setSubmitting(true)
    setActionError('')
    setDetailState({ propertyId: selectedPropertyId, status: 'loading', workflow: null, error: '' })
    try {
      const workflow = await startPricingAnalysis(selectedPropertyId)
      setDetailState((current) => current.propertyId === selectedPropertyId ? { propertyId: selectedPropertyId, status: 'ready', workflow, error: '' } : current)
      setHistoryReload((value) => value + 1)
    } catch (error) {
      setActionError(errorMessage(error, 'Unable to complete the pricing analysis. Please try again.'))
      setDetailState((current) => current.propertyId === selectedPropertyId ? { propertyId: selectedPropertyId, status: 'idle', workflow: null, error: '' } : current)
    } finally {
      setSubmitting(false)
    }
  }

  if (propertiesState.status === 'loading') return <LoadingState title="Loading your properties" />
  if (propertiesState.status === 'error') return <ErrorState title="Unable to load properties" message={propertiesState.error} onRetry={() => { setPropertiesState({ status: 'loading', items: [], error: '' }); getMyProperties().then((items) => setPropertiesState({ status: 'ready', items, error: '' })).catch((error) => setPropertiesState({ status: 'error', items: [], error: errorMessage(error, 'Unable to load your properties.') })) }} />

  const history = historyState.propertyId === propertyId ? historyState : { status: 'loading', items: [] }
  const detail = detailState.propertyId === propertyId ? detailState : { status: 'idle' }
  return <main className="shared-page pricing-page">
    <PageHeader eyebrow="Pricing / Lease" title="Rental Price Analysis"><p>Review evidence based rental price guidance for your properties.</p></PageHeader>
    <PricingLeaseNavigation />
    {propertiesState.items.length === 0 ? <EmptyState title="No properties yet" message="Add a property in Manage Properties to run a rental price analysis." /> : <>
      <AppCard>
        <div className="pricing-controls"><label htmlFor="pricing-property">Property</label><select id="pricing-property" value={propertyId} disabled={submitting} onChange={(event) => { ++detailRequest.current; setPropertyId(event.target.value); setActionError(''); setDetailState({ propertyId: '', status: 'idle', workflow: null, error: '' }) }}><option value="">Select a property</option>{propertiesState.items.map((property) => <option key={property.id} value={property.id}>{property.title} — {property.city}</option>)}</select><button className="shared-button" type="button" onClick={start} disabled={!propertyId || submitting}>{submitting ? 'Analyzing…' : 'Start analysis'}</button></div>
        {actionError && <p className="shared-notice shared-notice--error" role="alert">{actionError}</p>}
      </AppCard>
      {!propertyId ? <EmptyState title="Select a property" message="Choose one of your properties to view its analyses or start a new one." /> : <div className="pricing-grid">
        <section aria-label="Pricing analysis history"><AppCard><h2>Previous analyses</h2>{history.status === 'loading' && <p role="status">Loading analysis history…</p>}{history.status === 'error' && <div role="alert"><p>{history.error}</p><button className="shared-button shared-button--outline" type="button" onClick={() => setHistoryReload((value) => value + 1)}>Try again</button></div>}{history.status === 'ready' && (history.items.length === 0 ? <p>No previous analyses for this property.</p> : <ul className="pricing-history">{history.items.map((workflow) => <li key={workflow.workflowId}><div><strong>{date(workflow.createdAt)}</strong><span>{workflowStatuses[workflow.status] ?? 'Unknown'} · {workflow.evidenceSufficiency ?? 'Evidence pending'}</span></div><button className="shared-button shared-button--outline" type="button" disabled={submitting || detail.status === 'loading'} onClick={() => openWorkflow(workflow.workflowId)}>View details</button></li>)}</ul>)}</AppCard></section>
        <section aria-label="Selected pricing analysis">{detail.status === 'loading' && <AppCard><p role="status">Loading analysis details…</p></AppCard>}{detail.status === 'error' && <AppCard><p className="shared-notice shared-notice--error" role="alert">{detail.error}</p></AppCard>}{detail.status === 'ready' && <WorkflowDetails workflow={detail.workflow} property={propertiesState.items.find((item) => item.id === propertyId)} onRefresh={() => openWorkflow(detail.workflow.workflowId)} refreshing={false} />}{detail.status === 'idle' && <AppCard><h2>Analysis details</h2><p>Start a new analysis or open one from the history.</p></AppCard>}</section>
      </div>}
    </>}
  </main>
}
