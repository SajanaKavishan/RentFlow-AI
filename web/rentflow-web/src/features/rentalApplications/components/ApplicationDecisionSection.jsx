import { useState } from 'react'

export default function ApplicationDecisionSection({
  application,
  isUpdating,
  actionError,
  onReview,
  onApprove,
  onReject,
  onRequestChanges,
}) {
  const [action, setAction] = useState(null)
  const [response, setResponse] = useState('')
  const [validationError, setValidationError] = useState('')

  function openAction(nextAction) {
    setAction(nextAction)
    setResponse('')
    setValidationError('')
  }

  function closeAction() {
    if (isUpdating) return
    setAction(null)
    setResponse('')
    setValidationError('')
  }

  async function submitAction(event) {
    event.preventDefault()
    const trimmedResponse = response.trim()
    const responseRequired = action === 'reject' || action === 'changes'

    if (responseRequired && !trimmedResponse) {
      setValidationError(
        action === 'reject'
          ? 'Enter a reason before rejecting this application.'
          : 'Enter a message describing the requested changes.',
      )
      return
    }

    setValidationError('')
    let succeeded = false
    if (action === 'approve') {
      succeeded = await onApprove(application.id, trimmedResponse)
    } else if (action === 'reject') {
      succeeded = await onReject(application.id, trimmedResponse)
    } else if (action === 'changes') {
      succeeded = await onRequestChanges(application.id, trimmedResponse)
    }

    if (succeeded) closeAction()
  }

  return (
    <section className="application-card__decision-panel" aria-label="Landlord decision">
      <div className="application-card__decision-header">
        <div>
          <p className="application-card__eyebrow">Your decision</p>
          <h3>Choose the next step</h3>
        </div>
        <p>Review the application and advisory findings before making the final decision.</p>
      </div>

      {!action && (
        <div className="application-card__actions">
          {onReview && <button type="button" className="application-button application-button--quiet"
            onClick={() => onReview(application.id)} disabled={isUpdating}>
            {isUpdating ? 'Saving...' : 'Start review'}
          </button>}
          <button type="button" className="application-button application-button--primary"
            onClick={() => openAction('approve')} disabled={isUpdating}>Approve</button>
          <button type="button" className="application-button application-button--quiet"
            onClick={() => openAction('changes')} disabled={isUpdating}>Request more information</button>
          <button type="button" className="application-button application-button--danger-quiet"
            onClick={() => openAction('reject')} disabled={isUpdating}>Reject</button>
        </div>
      )}

      {action && (
        <form className="application-card__decision" onSubmit={submitAction}>
          <div>
            <h3>{action === 'approve' ? 'Approve application?' : action === 'reject' ? 'Reject application' : 'Request more information'}</h3>
            <p>{action === 'approve'
              ? 'You may include an optional response for the tenant.'
              : action === 'reject'
                ? 'Explain why this application cannot be approved.'
                : 'Tell the tenant exactly what information or changes are required.'}</p>
          </div>
          <label htmlFor={`${action}-response-${application.id}`}>
            {action === 'approve' ? 'Response (optional)' : action === 'reject' ? 'Rejection reason' : 'Information required'}
          </label>
          <textarea id={`${action}-response-${application.id}`} value={response}
            onChange={(event) => setResponse(event.target.value)} rows="4" maxLength="1000"
            disabled={isUpdating} aria-describedby={validationError ? `${application.id}-decision-error` : undefined} />
          {validationError && <p className="application-form-error" id={`${application.id}-decision-error`} role="alert">{validationError}</p>}
          {actionError && <p className="application-form-error" role="alert">{actionError}</p>}
          <div className="application-card__actions">
            <button type="submit" className={action === 'reject'
              ? 'application-button application-button--danger'
              : 'application-button application-button--primary'} disabled={isUpdating}>
              {isUpdating ? 'Saving...' : 'Confirm'}
            </button>
            <button type="button" className="application-button application-button--quiet"
              onClick={closeAction} disabled={isUpdating}>Go back</button>
          </div>
        </form>
      )}

      {actionError && !action && <p className="application-form-error" role="alert">{actionError}</p>}
    </section>
  )
}
