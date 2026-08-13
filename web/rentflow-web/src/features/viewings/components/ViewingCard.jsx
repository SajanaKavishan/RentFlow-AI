import { useState } from 'react'
import { VIEWING_STATUS } from '../services/viewingApiService.js'
import ViewingStatusBadge from './ViewingStatusBadge.jsx'

const viewingDateFormatter = new Intl.DateTimeFormat(undefined, {
  dateStyle: 'full',
  timeStyle: 'short',
})

function formatViewingDate(value) {
  const date = new Date(value)
  return Number.isNaN(date.getTime())
    ? 'Date unavailable'
    : viewingDateFormatter.format(date)
}

function ViewingCard({ viewing, isUpdating, actionError, onApprove, onReject }) {
  const [action, setAction] = useState(null)
  const [response, setResponse] = useState('')
  const [validationError, setValidationError] = useState('')
  const isPending = viewing.status === VIEWING_STATUS.PENDING

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

    if (action === 'reject' && !trimmedResponse) {
      setValidationError('Enter a reason before rejecting this request.')
      return
    }

    setValidationError('')
    const succeeded =
      action === 'approve'
        ? await onApprove(viewing.id, trimmedResponse)
        : await onReject(viewing.id, trimmedResponse)

    if (succeeded) closeAction()
  }

  return (
    <article className={`viewing-card${isPending ? ' viewing-card--pending' : ''}`}>
      <div className="viewing-card__heading">
        <div>
          <p className="viewing-card__eyebrow">
            {isPending ? 'New viewing request' : 'Viewing request'}
          </p>
          <h2>{formatViewingDate(viewing.requestedDateTime)}</h2>
        </div>
        <ViewingStatusBadge status={viewing.status} />
      </div>

      <div className="viewing-card__details">
        <div>
          <span>Tenant message</span>
          <p>{viewing.tenantMessage?.trim() || 'No message provided.'}</p>
        </div>
        {viewing.landlordResponse?.trim() && (
          <div className="viewing-card__response">
            <span>Your response</span>
            <p>{viewing.landlordResponse}</p>
          </div>
        )}
      </div>

      {isPending && !action && (
        <div className="viewing-card__actions">
          <button
            type="button"
            className="button button--primary"
            onClick={() => openAction('approve')}
            disabled={isUpdating}
          >
            Approve
          </button>
          <button
            type="button"
            className="button button--danger-quiet"
            onClick={() => openAction('reject')}
            disabled={isUpdating}
          >
            Reject
          </button>
        </div>
      )}

      {isPending && action && (
        <form className="viewing-card__decision" onSubmit={submitAction}>
          <div>
            <h3>{action === 'approve' ? 'Approve request?' : 'Reject request'}</h3>
            <p>
              {action === 'approve'
                ? 'You can include an optional note for the tenant.'
                : 'Tell the tenant why this viewing cannot be accepted.'}
            </p>
          </div>
          <label htmlFor={`${action}-response-${viewing.id}`}>
            {action === 'approve' ? 'Response (optional)' : 'Rejection reason'}
          </label>
          <textarea
            id={`${action}-response-${viewing.id}`}
            value={response}
            onChange={(event) => setResponse(event.target.value)}
            rows="3"
            maxLength="500"
            disabled={isUpdating}
            aria-describedby={validationError ? `${viewing.id}-error` : undefined}
          />
          {validationError && (
            <p className="form-error" id={`${viewing.id}-error`} role="alert">
              {validationError}
            </p>
          )}
          {actionError && (
            <p className="form-error" role="alert">
              {actionError}
            </p>
          )}
          <div className="viewing-card__actions">
            <button
              type="submit"
              className={
                action === 'approve'
                  ? 'button button--primary'
                  : 'button button--danger'
              }
              disabled={isUpdating}
            >
              {isUpdating
                ? 'Saving…'
                : action === 'approve'
                  ? 'Confirm approval'
                  : 'Confirm rejection'}
            </button>
            <button
              type="button"
              className="button button--quiet"
              onClick={closeAction}
              disabled={isUpdating}
            >
              Go back
            </button>
          </div>
        </form>
      )}
    </article>
  )
}

export default ViewingCard
