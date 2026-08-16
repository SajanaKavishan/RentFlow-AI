const API_BASE_URL = (
  import.meta.env.VITE_API_BASE_URL || 'http://localhost:5277'
).replace(/\/+$/, '')

// TODO(auth): Replace this development tenant ID with the authenticated
// tenant/authorized landlord identity once authentication is available.
const TEMPORARY_TENANT_ID = '11111111-1111-1111-1111-111111111111'

export const APPLICATION_DOCUMENT_TYPE = Object.freeze({
  IDENTITY_DOCUMENT: 0,
  INCOME_PROOF: 1,
  EMPLOYMENT_LETTER: 2,
  OTHER: 3,
})

export class ApplicationDocumentApiError extends Error {
  constructor(message, statusCode = null) {
    super(message)
    this.name = 'ApplicationDocumentApiError'
    this.statusCode = statusCode
  }
}

function withTenantId(path) {
  const separator = path.includes('?') ? '&' : '?'
  return `${path}${separator}tenantId=${encodeURIComponent(TEMPORARY_TENANT_ID)}`
}

async function readSafeErrorMessage(response) {
  const fallback = 'The document request failed. Please try again.'

  try {
    const body = await response.json()
    const directMessage = [body.detail, body.title, body.message].find(
      (value) => typeof value === 'string' && value.trim(),
    )

    if (directMessage) return directMessage.trim()

    if (body.errors && typeof body.errors === 'object') {
      const validationMessage = Object.values(body.errors)
        .flatMap((value) => (Array.isArray(value) ? value : [value]))
        .find((value) => typeof value === 'string' && value.trim())

      if (validationMessage) return validationMessage.trim()
    }
  } catch {
    // Never expose R2/XML responses, proxy details, or server traces.
  }

  return fallback
}

async function requestJson(path) {
  let response

  try {
    response = await fetch(`${API_BASE_URL}${withTenantId(path)}`, {
      headers: { Accept: 'application/json' },
      cache: 'no-store',
    })
  } catch {
    throw new ApplicationDocumentApiError(
      'Unable to connect to the document service. Please try again.',
    )
  }

  if (!response.ok) {
    throw new ApplicationDocumentApiError(
      await readSafeErrorMessage(response),
      response.status,
    )
  }

  try {
    return await response.json()
  } catch {
    throw new ApplicationDocumentApiError(
      'The document service returned an invalid response.',
      response.status,
    )
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
    // Validate access first so API failures can be shown safely in the UI.
    await getApplicationDocument(documentId)
    downloadWindow.location.replace(
      `${API_BASE_URL}${withTenantId(
        `/api/application-documents/${encodeURIComponent(documentId)}/download`,
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
