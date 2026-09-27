import { useState } from 'react'
import ApplicationDocumentCard from '../../applicationDocuments/components/ApplicationDocumentCard.jsx'
import {
  ApplicationDocumentApiError,
  downloadApplicationDocument,
  getApplicationDocuments,
} from '../../applicationDocuments/services/applicationDocumentApiService.js'
import '../../applicationDocuments/applicationDocuments.css'
import { RENTAL_APPLICATION_STATUS } from '../services/rentalApplicationApiService.js'
import ApplicationDecisionSection from './ApplicationDecisionSection.jsx'
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
  const isChangesRequested =
    application.status === RENTAL_APPLICATION_STATUS.CHANGES_REQUESTED
  const canAct = isSubmitted || isUnderReview

  async function loadDocuments() {
    setDocumentsState((current) => ({
      ...current,
      status: 'loading',
      error: '',
    }))

    try {
      const documents = await getApplicationDocuments(application.id)
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
      await downloadApplicationDocument(applicationDocument.id)
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

  return (
    <article
      className={`application-card${canAct ? ' application-card--priority' : ''}${isChangesRequested ? ' application-card--changes' : ''}`}
    >
      <div className="application-card__heading">
        <div>
          <p className="application-card__eyebrow">
            {isSubmitted
              ? 'Needs landlord review'
              : isUnderReview
                ? 'Review in progress'
                : isChangesRequested
                  ? 'Waiting for tenant updates'
                : 'Rental application'}
          </p>
          <h2>Move in {formatDateOnly(application.moveInDate)}</h2>
        </div>
        <RentalApplicationStatusBadge status={application.status} />
      </div>

      {isChangesRequested && (
        <div className="application-card__attention" role="status">
          <div className="application-card__attention-icon" aria-hidden="true">
            !
          </div>
          <div>
            <strong>Tenant update required</strong>
            <span>
              This application is waiting for the tenant to update and
              resubmit it before another landlord decision.
            </span>
          </div>
        </div>
      )}

      <dl className="application-card__references">
        <div>
          <dt>Application reference</dt>
          <dd>{application.id}</dd>
        </div>
        <div>
          <dt>Tenant reference</dt>
          <dd>{application.tenantId}</dd>
        </div>
        <div>
          <dt>Property reference</dt>
          <dd>{application.propertyId}</dd>
        </div>
      </dl>

      <dl className="application-card__facts">
        <div>
          <dt>Move-in date</dt>
          <dd>{formatDateOnly(application.moveInDate)}</dd>
        </div>
        <div>
          <dt>Monthly income</dt>
          <dd>{formatIncome(application.monthlyIncome)}</dd>
        </div>
        <div>
          <dt>Occupants</dt>
          <dd>{application.numberOfOccupants}</dd>
        </div>
        <div>
          <dt>Created</dt>
          <dd>{formatDateTime(application.createdAt)}</dd>
        </div>
      </dl>

      {(application.submittedAt || application.updatedAt) && (
        <dl className="application-card__timeline" aria-label="Application activity">
          {application.submittedAt && (
            <div>
              <dt>Submitted</dt>
              <dd>{formatDateTime(application.submittedAt)}</dd>
            </div>
          )}
          {application.updatedAt && (
            <div>
              <dt>Last updated</dt>
              <dd>{formatDateTime(application.updatedAt)}</dd>
            </div>
          )}
        </dl>
      )}

      <div className="application-card__notes">
        <div>
          <span>Occupation</span>
          <p>{application.occupation || 'Not provided'}</p>
        </div>
        <div>
          <span>Tenant note</span>
          <p>{application.tenantNote?.trim() || 'No note provided.'}</p>
        </div>
        {application.landlordResponse?.trim() && (
          <div className="application-card__response application-card__notes--wide">
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
          aria-label={`${documentsExpanded ? 'Hide' : 'Review'} documents for application ${application.id}`}
        >
          {documentsExpanded ? 'Hide documents' : 'Review documents'}
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
              <p className="application-documents__eyebrow">Document review</p>
              <h3>Tenant-provided documents</h3>
              <p>Review the files supplied with this application.</p>
            </div>
            {documentsState.status === 'success' && (
              <span className="application-documents__count">
                {documentsState.items.length}{' '}
                {documentsState.items.length === 1 ? 'document' : 'documents'}
              </span>
            )}
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

      {canAct && (
        <ApplicationDecisionSection application={application} isUpdating={isUpdating}
          actionError={actionError} onApprove={onApprove} onReject={onReject}
          onRequestChanges={onRequestChanges} onReview={isSubmitted ? onReview : undefined} />
      )}
    </article>
  )
}

export default RentalApplicationCard
