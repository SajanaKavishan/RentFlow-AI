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
        <div className="application-document-card__badges">
          <ApplicationDocumentTypeBadge
            documentType={applicationDocument.documentType}
          />
          <span className="application-document-card__state">Uploaded</span>
        </div>
        <div className="application-document-card__details">
          <h4 title={applicationDocument.originalFileName}>
            {applicationDocument.originalFileName || 'Unnamed document'}
          </h4>
          <dl>
            <div>
              <dt>File size</dt>
              <dd>{formatFileSize(applicationDocument.fileSizeBytes)}</dd>
            </div>
            {applicationDocument.contentType && (
              <div>
                <dt>File type</dt>
                <dd>{applicationDocument.contentType}</dd>
              </div>
            )}
            <div>
              <dt>Uploaded</dt>
              <dd>{formatUploadDate(applicationDocument.uploadedAt)}</dd>
            </div>
          </dl>
        </div>
      </div>
      <button
        type="button"
        className="application-button application-button--quiet application-document-card__download"
        onClick={() => onDownload(applicationDocument)}
        disabled={isDownloading}
      >
        {isDownloading ? 'Opening...' : 'Open document'}
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
