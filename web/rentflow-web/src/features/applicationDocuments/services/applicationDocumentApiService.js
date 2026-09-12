import { ApiError, apiRequest } from '../../../core/api/apiClient.js'
import { API_BASE_URL } from '../../../core/api/apiConfig.js'

export const APPLICATION_DOCUMENT_TYPE = Object.freeze({
  IDENTITY_DOCUMENT: 0,
  INCOME_PROOF: 1,
  EMPLOYMENT_LETTER: 2,
  OTHER: 3,
})

export class ApplicationDocumentApiError extends ApiError {
  constructor(message, statusCode = null) {
    super(message)
    this.name = 'ApplicationDocumentApiError'
    this.statusCode = statusCode
  }
}

// TODO(auth): Remove this temporary tenantId query parameter once JWT
// role-based authorization supplies the authorized identity.
function withTenantId(path, tenantId) {
  const separator = path.includes('?') ? '&' : '?'
  return `${path}${separator}tenantId=${encodeURIComponent(tenantId)}`
}

async function requestJson(path, tenantId) {
  try {
    return await apiRequest(withTenantId(path, tenantId), {
      cache: 'no-store',
      errorMessage: 'The document request failed. Please try again.',
      networkErrorMessage: 'Unable to connect to the document service. Please try again.',
    })
  } catch (error) {
    if (error instanceof ApiError) throw new ApplicationDocumentApiError(error.message, error.statusCode)
    throw error
  }
}

export async function getApplicationDocuments(applicationId, tenantId) {
  const documents = await requestJson(
    `/api/rental-applications/${encodeURIComponent(applicationId)}/documents`,
    tenantId,
  )

  if (!Array.isArray(documents)) {
    throw new ApplicationDocumentApiError(
      'The document service returned an invalid response.',
    )
  }

  return documents
}

export function getApplicationDocument(documentId, tenantId) {
  return requestJson(
    `/api/application-documents/${encodeURIComponent(documentId)}`,
    tenantId,
  )
}

export async function downloadApplicationDocument(documentId, tenantId) {
  const downloadWindow = window.open('', '_blank')
  if (!downloadWindow) {
    throw new ApplicationDocumentApiError(
      'Your browser blocked the download window. Allow pop-ups and try again.',
    )
  }

  downloadWindow.opener = null

  try {
    // Authenticate the access check centrally, then preserve the existing
    // browser navigation so private-storage redirects keep working.
    await getApplicationDocument(documentId, tenantId)
    downloadWindow.location.replace(
      `${API_BASE_URL}${withTenantId(
        `/api/application-documents/${encodeURIComponent(documentId)}/download`,
        tenantId,
      )}`,
    )
  } catch (error) {
    downloadWindow.close()
    if (error instanceof ApplicationDocumentApiError) throw error
    throw new ApplicationDocumentApiError(
      'Unable to open this document for download. Please try again.',
    )
  }
}
