import { useState } from 'react'
import { VIEWING_STATUS } from '../services/viewingApiService.js'
import ViewingStatusBadge from './ViewingStatusBadge.jsx'

const viewingDateFormatter = new Intl.DateTimeFormat(undefined, {
  dateStyle: 'full',
})
const viewingTimeFormatter = new Intl.DateTimeFormat(undefined, {
  timeStyle: 'short',
})

function parseViewingDate(value) {
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? null : date
}

function displayValue(...values) {
  return values.find((value) => typeof value === 'string' && value.trim())?.trim() || null
}

function ViewingCard({ viewing, isUpdating, actionError, onApprove, onReject }) {
  const [action, setAction] = useState(null)
  const [response, setResponse] = useState('')
  const [validationError, setValidationError] = useState('')
  const [hasSubmitted, setHasSubmitted] = useState(false)
  const isPending = viewing.status === VIEWING_STATUS.PENDING
  const requestedDate = parseViewingDate(viewing.requestedDateTime)
  const tenantMessage = viewing.tenantMessage?.trim()
  const landlordResponse = viewing.landlordResponse?.trim()
  const tenantName = displayValue(viewing.tenantName, viewing.tenant?.name)
  const tenantEmail = displayValue(viewing.tenantEmail, viewing.tenant?.email)
  const propertyName = displayValue(viewing.propertyName, viewing.property?.name)
  const propertyLocation = displayValue(viewing.propertyLocation, viewing.property?.location)
  const createdDate = parseViewingDate(viewing.createdAt)

  function openAction(nextAction) {
    setAction(nextAction)
    setResponse('')
    setValidationError('')
    setHasSubmitted(false)
  }

  function closeAction() {
    if (isUpdating) return
    setAction(null)
    setResponse('')
    setValidationError('')
    setHasSubmitted(false)
  }

  async function submitAction(event) {
    event.preventDefault()
    const trimmedResponse = response.trim()

    if (action === 'reject' && !trimmedResponse) {
      setValidationError('Enter a reason before rejecting this request.')
      return
    }

    setValidationError('')
    setHasSubmitted(true)
    const succeeded =
      action === 'approve'
        ? await onApprove(viewing.id, trimmedResponse)
        : await onReject(viewing.id, trimmedResponse)

    if (succeeded) closeAction()
  }

  return (
    <article
      className={`viewing-card${isPending ? ' viewing-card--pending' : ''}`}
      aria-label={`Viewing request ${viewing.id}`}
    >
      <div className="viewing-card__heading">
        <div>
          <p className="viewing-card__eyebrow">
            {isPending ? 'New viewing request' : 'Viewing request'}
          </p>
          <h2>{isPending ? 'Awaiting your response' : 'Viewing details'}</h2>
        </div>
        <ViewingStatusBadge status={viewing.status} />
      </div>

      <div className="viewing-card__overview">
        <div className="viewing-card__schedule">
          <span className="viewing-card__schedule-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24" focusable="false">
              <path d="M7 3v3m10-3v3M4.5 9h15M6 5h12a2 2 0 0 1 2 2v12H4V7a2 2 0 0 1 2-2Z" />
            </svg>
          </span>
          <div>
            <span>Requested appointment</span>
            {requestedDate ? (
              <time dateTime={viewing.requestedDateTime}>
                <strong>{viewingDateFormatter.format(requestedDate)}</strong>
                <small>{viewingTimeFormatter.format(requestedDate)}</small>
              </time>
            ) : (
              <strong>Date and time unavailable</strong>
            )}
          </div>
        </div>

        <dl className="viewing-card__references">
          <div>
            <dt>Tenant</dt>
            <dd title={tenantEmail || viewing.tenantId}>
              {tenantName || tenantEmail || viewing.tenantId || 'Unavailable'}
              {tenantName && tenantEmail && <small>{tenantEmail}</small>}
            </dd>
          </div>
          <div>
            <dt>Property</dt>
            <dd title={propertyLocation || viewing.propertyId}>
              {propertyName || propertyLocation || viewing.propertyId || 'Unavailable'}
              {propertyName && propertyLocation && <small>{propertyLocation}</small>}
            </dd>
          </div>
        </dl>
      </div>

      {createdDate && (
        <p className="viewing-card__created">
          Requested on <time dateTime={viewing.createdAt}>{viewingDateFormatter.format(createdDate)}</time>
        </p>
      )}

      <div className="viewing-card__conversation">
        <div className="viewing-card__message">
          <span>Tenant message</span>
          <p>{tenantMessage || 'No message was included with this request.'}</p>
        </div>
        {landlordResponse && (
          <div className="viewing-card__response">
            <span>Your response</span>
            <p>{landlordResponse}</p>
          </div>
        )}
      </div>

      {isPending && !action && (
        <div className="viewing-card__actions viewing-card__actions--primary">
          <button
            type="button"
            className="button button--primary"
            onClick={() => openAction('approve')}
            disabled={isUpdating}
          >
            Approve request
          </button>
          <button
            type="button"
            className="button button--danger-quiet"
            onClick={() => openAction('reject')}
            disabled={isUpdating}
          >
            Reject request
          </button>
        </div>
      )}

      {isPending && action && (
        <form
          className="viewing-card__decision"
          onSubmit={submitAction}
          aria-busy={isUpdating}
        >
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
          <p className="viewing-card__character-count" aria-live="polite">
            {response.length}/500 characters
          </p>
          {validationError && (
            <p className="form-error" id={`${viewing.id}-error`} role="alert">
              {validationError}
            </p>
          )}
          {hasSubmitted && actionError && (
            <div className="viewing-card__action-error" role="alert">
              <span aria-hidden="true">!</span>
              <p>{actionError}</p>
            </div>
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
