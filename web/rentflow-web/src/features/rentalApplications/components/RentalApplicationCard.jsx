import { useState } from 'react'
import ApplicationDocumentCard from '../../applicationDocuments/components/ApplicationDocumentCard.jsx'
import {
  ApplicationDocumentApiError,
  downloadApplicationDocument,
  getApplicationDocuments,
} from '../../applicationDocuments/services/applicationDocumentApiService.js'
import '../../applicationDocuments/applicationDocuments.css'
import { RENTAL_APPLICATION_STATUS } from '../services/rentalApplicationApiService.js'
import RentalApplicationStatusBadge from './RentalApplicationStatusBadge.jsx'

const dateFormatter = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' })
const dateTimeFormatter = new Intl.DateTimeFormat(undefined, {
  dateStyle: 'medium',
  timeStyle: 'short',
})
const incomeFormatter = new Intl.NumberFormat(undefined, {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
})

function formatDateOnly(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value || '')
  if (!match) return 'Date unavailable'
  const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
  return Number.isNaN(date.getTime()) ? 'Date unavailable' : dateFormatter.format(date)
}

function formatDateTime(value) {
  const date = new Date(value)
  return Number.isNaN(date.getTime())
    ? 'Date unavailable'
    : dateTimeFormatter.format(date)
}

function formatIncome(value) {
  const income = Number(value)
  return Number.isFinite(income) ? incomeFormatter.format(income) : 'Unavailable'
}

function RentalApplicationCard({
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
  const [documentsExpanded, setDocumentsExpanded] = useState(false)
  const [documentsState, setDocumentsState] = useState({
    status: 'idle',
    items: [],
    error: '',
  })
  const [downloadingId, setDownloadingId] = useState(null)
  const [downloadError, setDownloadError] = useState({ id: null, message: '' })
  const isSubmitted = application.status === RENTAL_APPLICATION_STATUS.SUBMITTED
  const isUnderReview =
    application.status === RENTAL_APPLICATION_STATUS.UNDER_REVIEW
  const canAct = isSubmitted || isUnderReview

  async function loadDocuments() {
    setDocumentsState((current) => ({
      ...current,
      status: 'loading',
      error: '',
    }))

    try {
      const documents = await getApplicationDocuments(
        application.id,
        application.tenantId,
      )
      setDocumentsState({ status: 'success', items: documents, error: '' })
    } catch (error) {
      setDocumentsState({
        status: 'error',
        items: [],
        error:
          error instanceof ApplicationDocumentApiError
            ? error.message
            : 'Unable to load documents. Please try again.',
      })
    }
  }

  function toggleDocuments() {
    const shouldExpand = !documentsExpanded
    setDocumentsExpanded(shouldExpand)
    setDownloadError({ id: null, message: '' })
    if (shouldExpand && documentsState.status === 'idle') loadDocuments()
  }

  async function handleDownload(applicationDocument) {
    if (downloadingId) return

    setDownloadingId(applicationDocument.id)
    setDownloadError({ id: null, message: '' })
    try {
      await downloadApplicationDocument(
        applicationDocument.id,
        application.tenantId,
      )
    } catch (error) {
      setDownloadError({
        id: applicationDocument.id,
        message:
          error instanceof ApplicationDocumentApiError
            ? error.message
            : 'Unable to download this document. Please try again.',
      })
    } finally {
      setDownloadingId(null)
    }
  }

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
    <article
      className={`application-card${canAct ? ' application-card--priority' : ''}`}
    >
      <div className="application-card__heading">
        <div>
          <p className="application-card__eyebrow">
            {isSubmitted
              ? 'New rental application'
              : isUnderReview
                ? 'Review in progress'
                : 'Rental application'}
          </p>
          <h2>Move in {formatDateOnly(application.moveInDate)}</h2>
          <p className="application-card__tenant">
            Tenant ID: <span>{application.tenantId}</span>
          </p>
        </div>
        <RentalApplicationStatusBadge status={application.status} />
      </div>

      <dl className="application-card__facts">
        <div>
          <dt>Monthly income</dt>
          <dd>{formatIncome(application.monthlyIncome)}</dd>
        </div>
        <div>
          <dt>Occupation</dt>
          <dd>{application.occupation || 'Not provided'}</dd>
        </div>
        <div>
          <dt>Occupants</dt>
          <dd>{application.numberOfOccupants}</dd>
        </div>
        <div>
          <dt>Submitted</dt>
          <dd>
            {application.submittedAt
              ? formatDateTime(application.submittedAt)
              : 'Not submitted'}
          </dd>
        </div>
      </dl>

      <div className="application-card__notes">
        <div>
          <span>Tenant note</span>
          <p>{application.tenantNote?.trim() || 'No note provided.'}</p>
        </div>
        {application.landlordResponse?.trim() && (
          <div className="application-card__response">
            <span>Your response</span>
            <p>{application.landlordResponse}</p>
          </div>
        )}
      </div>

      <div className="application-card__document-action">
        <button
          type="button"
          className="application-button application-button--quiet"
          onClick={toggleDocuments}
          aria-expanded={documentsExpanded}
          aria-controls={`application-documents-${application.id}`}
        >
          {documentsExpanded ? 'Hide documents' : 'View documents'}
        </button>
      </div>

      {documentsExpanded && (
        <section
          className="application-documents"
          id={`application-documents-${application.id}`}
          aria-label="Application documents"
        >
          <div className="application-documents__header">
            <div>
              <h3>Supporting documents</h3>
              <p>Private files supplied with this rental application.</p>
            </div>
          </div>

          {documentsState.status === 'loading' && (
            <div className="application-documents__state" aria-live="polite">
              <span
                className="application-documents__spinner"
                aria-hidden="true"
              />
              Loading documents...
            </div>
          )}

          {documentsState.status === 'error' && (
            <div
              className="application-documents__state application-documents__state--error"
              role="alert"
            >
              <p>{documentsState.error}</p>
              <button
                type="button"
                className="application-button application-button--quiet"
                onClick={loadDocuments}
              >
                Try again
              </button>
            </div>
          )}

          {documentsState.status === 'success' &&
            documentsState.items.length === 0 && (
              <p className="application-documents__state application-documents__state--empty">
                No documents have been added to this application.
              </p>
            )}

          {documentsState.status === 'success' &&
            documentsState.items.length > 0 && (
              <div className="application-documents__list">
                {documentsState.items.map((applicationDocument) => (
                  <ApplicationDocumentCard
                    key={applicationDocument.id}
                    document={applicationDocument}
                    isDownloading={downloadingId === applicationDocument.id}
                    downloadError={
                      downloadError.id === applicationDocument.id
                        ? downloadError.message
                        : ''
                    }
                    onDownload={handleDownload}
                  />
                ))}
              </div>
            )}
        </section>
      )}

      {canAct && !action && (
        <div className="application-card__actions">
          {isSubmitted && (
            <button
              type="button"
              className="application-button application-button--quiet"
              onClick={() => onReview(application.id)}
              disabled={isUpdating}
            >
              {isUpdating ? 'Saving...' : 'Start review'}
            </button>
          )}
          <button
            type="button"
            className="application-button application-button--primary"
            onClick={() => openAction('approve')}
            disabled={isUpdating}
          >
            Approve
          </button>
          <button
            type="button"
            className="application-button application-button--danger-quiet"
            onClick={() => openAction('reject')}
            disabled={isUpdating}
          >
            Reject
          </button>
          <button
            type="button"
            className="application-button application-button--quiet"
            onClick={() => openAction('changes')}
            disabled={isUpdating}
          >
            Request changes
          </button>
        </div>
      )}

      {canAct && action && (
        <form className="application-card__decision" onSubmit={submitAction}>
          <div>
            <h3>
              {action === 'approve'
                ? 'Approve application?'
                : action === 'reject'
                  ? 'Reject application'
                  : 'Request changes'}
            </h3>
            <p>
              {action === 'approve'
                ? 'You may include an optional response for the tenant.'
                : action === 'reject'
                  ? 'Explain why this application cannot be approved.'
                  : 'Tell the tenant exactly what needs to be updated.'}
            </p>
          </div>
          <label htmlFor={`${action}-response-${application.id}`}>
            {action === 'approve'
              ? 'Response (optional)'
              : action === 'reject'
                ? 'Rejection reason'
                : 'Changes required'}
          </label>
          <textarea
            id={`${action}-response-${application.id}`}
            value={response}
            onChange={(event) => setResponse(event.target.value)}
            rows="4"
            maxLength="1000"
            disabled={isUpdating}
            aria-describedby={
              validationError ? `${application.id}-decision-error` : undefined
            }
          />
          {validationError && (
            <p
              className="application-form-error"
              id={`${application.id}-decision-error`}
              role="alert"
            >
              {validationError}
            </p>
          )}
          {actionError && (
            <p className="application-form-error" role="alert">
              {actionError}
            </p>
          )}
          <div className="application-card__actions">
            <button
              type="submit"
              className={
                action === 'reject'
                  ? 'application-button application-button--danger'
                  : 'application-button application-button--primary'
              }
              disabled={isUpdating}
            >
              {isUpdating ? 'Saving...' : 'Confirm'}
            </button>
            <button
              type="button"
              className="application-button application-button--quiet"
              onClick={closeAction}
              disabled={isUpdating}
            >
              Go back
            </button>
          </div>
        </form>
      )}

      {actionError && !action && (
        <p className="application-form-error" role="alert">
          {actionError}
        </p>
      )}
    </article>
  )
}

export default RentalApplicationCard
