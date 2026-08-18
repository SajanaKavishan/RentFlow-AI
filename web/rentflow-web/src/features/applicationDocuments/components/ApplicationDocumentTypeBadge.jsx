import { APPLICATION_DOCUMENT_TYPE } from '../services/applicationDocumentApiService.js'

const DOCUMENT_TYPE_DETAILS = {
  [APPLICATION_DOCUMENT_TYPE.IDENTITY_DOCUMENT]: {
    label: 'Identity document',
    className: 'identity',
  },
  [APPLICATION_DOCUMENT_TYPE.INCOME_PROOF]: {
    label: 'Income proof',
    className: 'income',
  },
  [APPLICATION_DOCUMENT_TYPE.EMPLOYMENT_LETTER]: {
    label: 'Employment letter',
    className: 'employment',
  },
  [APPLICATION_DOCUMENT_TYPE.OTHER]: {
    label: 'Other',
    className: 'other',
  },
}

function ApplicationDocumentTypeBadge({ documentType }) {
  const details = DOCUMENT_TYPE_DETAILS[documentType] || {
    label: 'Document',
    className: 'other',
  }

  return (
    <span
      className={`application-document-type application-document-type--${details.className}`}
    >
      {details.label}
    </span>
  )
}

export default ApplicationDocumentTypeBadge
