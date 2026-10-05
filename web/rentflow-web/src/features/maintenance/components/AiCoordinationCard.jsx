import { useId } from 'react'
import {
  COORDINATION_CATEGORY_LABELS, COORDINATION_FLAGS, COORDINATION_NEXT_STEPS,
  parseCoordinationResult, parsePhotoEvidence,
} from '../services/maintenanceCoordinationResult.js'
import './ai-coordination.css'

function ConfidenceBadge({ value }) {
  return <span className={`ai-coordination__confidence ai-coordination__confidence--${value.toLowerCase()}`}>
    {value === 'Unknown' ? 'Confidence unknown' : `${value} confidence`}
  </span>
}

export default function AiCoordinationCard({
  request, workflow, state, pending, error, notice, decisionNotes,
  onDecisionNotesChange, onAnalyze, onRefresh, onDecision, onUseSuggestions,
}) {
  const headingId = useId()
  const notesId = useId()
  const result = parseCoordinationResult(workflow, request.id)
  const photoEvidence = parsePhotoEvidence(workflow?.photoEvidence)
  const accepted = workflow?.approvalStatus === 'Approved' && workflow?.status === 'Completed'
  const rejected = workflow?.approvalStatus === 'Rejected' && workflow?.status === 'Failed'
  const reviewed = accepted || rejected
  const running = ['Pending', 'Running'].includes(workflow?.status)
  const loading = state === 'loading' || state === 'analyzing' || running
  const unavailable = state === 'error' || (state === 'success' && (
    !result || (!reviewed && workflow?.status !== 'AwaitingHumanReview') ||
    (!reviewed && (workflow?.approvalStatus !== 'Pending' || workflow?.requiresHumanApproval !== true))
  ))
  const showResult = !loading && !unavailable && state === 'success' && result
  const canReview = showResult && !reviewed && workflow.requiresHumanApproval === true
  const uncertain = showResult && [result.categoryConfidence, result.priorityConfidence]
    .some((confidence) => ['Low', 'Unknown'].includes(confidence))
  const emergency = showResult && (result.suggestedPriority === 'Emergency' || request.priority === 'Emergency')
  const nextStep = showResult && result.nextAction ? COORDINATION_NEXT_STEPS[result.nextAction] : null

  return <section className="ai-coordination" aria-labelledby={headingId} aria-busy={loading}>
    <header className="ai-coordination__header">
      <div>
        <p className="ai-coordination__eyebrow">Human-led maintenance</p>
        <h3 id={headingId}>AI Coordination</h3>
        <p className="ai-coordination__support">AI-assisted recommendation for human review.</p>
      </div>
      {showResult && <span className="ai-coordination__badge">Human review required</span>}
    </header>

    {loading && <div className="ai-coordination__state" role="status" aria-live="polite">
      <span className="ai-coordination__spinner" aria-hidden="true" />
      <strong>{state === 'loading' ? 'Loading saved analysis?' : 'Analyzing maintenance request?'}</strong>
      <p>{state === 'loading' ? 'Checking for a saved recommendation.' : 'Reviewing the request details and available evidence.'}</p>
      {running && state !== 'analyzing' && <button type="button" className="button button--quiet" onClick={onRefresh} disabled={pending}>Check progress</button>}
    </div>}

    {!loading && unavailable && <div className="ai-coordination__state ai-coordination__state--error" role="alert">
      <strong>AI analysis unavailable</strong>
      <p>The maintenance request can still be managed normally.</p>
      <button type="button" className="button button--quiet" onClick={onAnalyze} disabled={pending}>Try again</button>
    </div>}

    {!loading && !unavailable && state === 'none' && <div className="ai-coordination__state">
      <p>Get an AI-assisted review of the request category, priority and next step.</p>
      <button type="button" className="button button--primary" onClick={onAnalyze} disabled={pending}>Analyze request</button>
    </div>}

    {showResult && <>
      {photoEvidence && <p className="ai-coordination__support">
        Photo evidence: {photoEvidence.analyzedPhotoCount === photoEvidence.suppliedPhotoCount
          ? `${photoEvidence.analyzedPhotoCount} ${photoEvidence.analyzedPhotoCount === 1 ? 'photo' : 'photos'} analyzed`
          : `${photoEvidence.analyzedPhotoCount} of ${photoEvidence.suppliedPhotoCount} photos analyzed`}.
      </p>}
      {reviewed && <div className="ai-coordination__reviewed" role="status">
        <strong>{accepted ? 'Recommendation accepted' : 'Recommendation rejected'}</strong>
        <p>{accepted ? 'The advisory review was accepted.' : 'The advisory review was rejected.'} The maintenance request has not been changed by this decision.</p>
      </div>}

      <dl className="ai-coordination__recommendations">
        <div className="ai-coordination__row">
          <dt>Suggested category</dt>
          <dd><strong>{result.suggestedCategory === null ? 'Insufficient information' : COORDINATION_CATEGORY_LABELS[result.suggestedCategory]}</strong>
            <ConfidenceBadge value={result.categoryConfidence} /></dd>
        </div>
        <div className="ai-coordination__row">
          <dt>Suggested priority</dt>
          <dd><strong>{result.suggestedPriority ?? 'Insufficient information'}</strong>
            <ConfidenceBadge value={result.priorityConfidence} /></dd>
        </div>
        <div className="ai-coordination__row">
          <dt>Required work</dt>
          <dd><strong>{result.recommendedTechnicianCategory === null ? 'More information needed' :
            `${COORDINATION_CATEGORY_LABELS[result.recommendedTechnicianCategory]} maintenance`}</strong>
            <small>Type of work required; individual technician skills must be checked separately.</small></dd>
        </div>
        <div className="ai-coordination__row">
          <dt>Recommended next step</dt>
          <dd><strong>{nextStep?.label ?? 'No AI workflow action suggested'}</strong>
            <small>Responsible: {nextStep?.actor ?? 'No action'}</small></dd>
        </div>
      </dl>

      {uncertain && <div className="ai-coordination__callout ai-coordination__callout--attention">
        <strong>More information may be needed</strong>
        <p>Low or unknown confidence means the available information may be insufficient. Review the request before deciding.</p>
      </div>}
      {emergency && <div className="ai-coordination__callout ai-coordination__callout--warning" role="alert">
        <strong>Urgent review needed</strong>
        <p>AI guidance cannot confirm safety. Confirm the situation and emergency handling with a human before taking action.</p>
      </div>}

      {result.validationFlags.length > 0 && <ul className="ai-coordination__flags" aria-label="Review considerations">
        {result.validationFlags.map((flag, index) => {
          const presentation = COORDINATION_FLAGS[flag.code]
          return <li key={`${flag.code}-${index}`} className={`ai-coordination__callout ai-coordination__callout--${presentation.tone}`}>
            <strong>{presentation.title}</strong><p>{flag.message}</p>
          </li>
        })}
      </ul>}

      <div className="ai-coordination__rationale">
        <h4>Why the AI suggested this</h4>
        <p>{result.rationale}</p>
      </div>

      <div className="ai-coordination__footer">
        <p>Accepting or rejecting this recommendation records your AI review only. Category, priority, assignment, estimates and request status remain under human control.</p>
        {canReview && <>
          <label className="ai-coordination__notes" htmlFor={notesId}>Review notes (optional)
            <textarea id={notesId} rows={2} maxLength={2000} value={decisionNotes} onChange={(event) => onDecisionNotesChange(event.target.value)} />
          </label>
          <div className="ai-coordination__actions">
            <button type="button" className="button button--quiet" onClick={() => onDecision('reject')} disabled={pending}>Reject recommendation</button>
            <button type="button" className="button button--primary" onClick={() => onDecision('approve')} disabled={pending}>Accept recommendation</button>
          </div>
          {pending && <p role="status">Recording your review?</p>}
        </>}
        {error && <p role="alert" className="ai-coordination__decision-error">Unable to record the recommendation review. Try again; the maintenance request can still be managed normally.</p>}
        <div className="ai-coordination__secondary">
          {onUseSuggestions && !rejected && <button type="button" className="button button--quiet" disabled={pending || (result.suggestedCategory === null && result.suggestedPriority === null)} onClick={() => onUseSuggestions(result)}>Use suggestion in triage</button>}
          <button type="button" className="button button--quiet" onClick={onAnalyze} disabled={pending}>Run again</button>
        </div>
        {notice && <p className="ai-coordination__notice" role="status">{notice}</p>}
      </div>
    </>}
  </section>
}
