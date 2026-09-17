import { ApiError, apiRequest } from '../../../core/api/apiClient.js'

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

async function requestJson(path) {
  try {
    return await apiRequest(path, {
      cache: 'no-store',
      errorMessage: 'The document request failed. Please try again.',
      networkErrorMessage: 'Unable to connect to the document service. Please try again.',
    })
  } catch (error) {
    if (error instanceof ApiError) throw new ApplicationDocumentApiError(error.message, error.statusCode)
    throw error
  }
}

export async function getApplicationDocuments(applicationId) {
  const documents = await requestJson(
    `/api/rental-applications/${encodeURIComponent(applicationId)}/documents`,
  )

  if (!Array.isArray(documents)) {
    throw new ApplicationDocumentApiError(
      'The document service returned an invalid response.',
    )
  }

  return documents
}

export function getApplicationDocument(documentId) {
  return requestJson(
    `/api/application-documents/${encodeURIComponent(documentId)}`,
  )
}

export async function downloadApplicationDocument(documentId) {
  const downloadWindow = window.open('', '_blank')
  if (!downloadWindow) {
    throw new ApplicationDocumentApiError(
      'Your browser blocked the download window. Allow pop-ups and try again.',
    )
  }

  downloadWindow.opener = null

  try {
    const response = await apiRequest(
      `/api/application-documents/${encodeURIComponent(documentId)}/download`,
      {
        cache: 'no-store',
        parse: 'response',
        errorMessage: 'Unable to open this document for download. Please try again.',
        networkErrorMessage: 'Unable to connect to the document service. Please try again.',
      },
    )
    const objectUrl = URL.createObjectURL(await response.blob())
    downloadWindow.location.replace(objectUrl)
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 60_000)
  } catch (error) {
    downloadWindow.close()
    if (error instanceof ApiError) {
      throw new ApplicationDocumentApiError(error.message, error.statusCode)
    }
    if (error instanceof ApplicationDocumentApiError) throw error
    throw new ApplicationDocumentApiError(
      'Unable to open this document for download. Please try again.',
    )
  }
}
