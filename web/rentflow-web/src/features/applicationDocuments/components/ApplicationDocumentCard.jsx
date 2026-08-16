import ApplicationDocumentTypeBadge from './ApplicationDocumentTypeBadge.jsx'

const uploadDateFormatter = new Intl.DateTimeFormat(undefined, {
  dateStyle: 'medium',
  timeStyle: 'short',
})

function formatFileSize(bytes) {
  const size = Number(bytes)
  if (!Number.isFinite(size) || size < 0) return 'Size unavailable'
  if (size < 1024) return `${size} B`

  const units = ['KB', 'MB', 'GB']
  let value = size / 1024
  let unitIndex = 0
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024
    unitIndex += 1
  }

  return `${value.toFixed(value >= 10 ? 1 : 2)} ${units[unitIndex]}`
}

function formatUploadDate(value) {
  const date = new Date(value)
  return Number.isNaN(date.getTime())
    ? 'Upload date unavailable'
    : uploadDateFormatter.format(date)
}

function ApplicationDocumentCard({
  document: applicationDocument,
  isDownloading,
  downloadError,
  onDownload,
}) {
  return (
    <article className="application-document-card">
      <div className="application-document-card__main">
        <ApplicationDocumentTypeBadge
          documentType={applicationDocument.documentType}
        />
        <div className="application-document-card__details">
          <h4 title={applicationDocument.originalFileName}>
            {applicationDocument.originalFileName || 'Unnamed document'}
          </h4>
          <p>
            <span>{formatFileSize(applicationDocument.fileSizeBytes)}</span>
            {applicationDocument.contentType && (
              <>
                <span aria-hidden="true">&bull;</span>
                <span>{applicationDocument.contentType}</span>
              </>
            )}
          </p>
          <p>Uploaded {formatUploadDate(applicationDocument.uploadedAt)}</p>
        </div>
      </div>
      <button
        type="button"
        className="application-button application-button--quiet application-document-card__download"
        onClick={() => onDownload(applicationDocument)}
        disabled={isDownloading}
      >
        {isDownloading ? 'Downloading...' : 'Download'}
      </button>
      {downloadError && (
        <p className="application-document-error" role="alert">
          {downloadError}
        </p>
      )}
    </article>
  )
}

export default ApplicationDocumentCard
