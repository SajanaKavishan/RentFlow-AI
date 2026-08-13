const API_BASE_URL = (
  import.meta.env.VITE_API_BASE_URL || 'http://localhost:5277'
).replace(/\/+$/, '')

export const RENTAL_APPLICATION_STATUS = Object.freeze({
  DRAFT: 0,
  SUBMITTED: 1,
  UNDER_REVIEW: 2,
  CHANGES_REQUESTED: 3,
  APPROVED: 4,
  REJECTED: 5,
  WITHDRAWN: 6,
})

export class RentalApplicationApiError extends Error {
  constructor(message, statusCode = null) {
    super(message)
    this.name = 'RentalApplicationApiError'
    this.statusCode = statusCode
  }
}

async function request(path, options = {}) {
  let response

  try {
    response = await fetch(`${API_BASE_URL}${path}`, {
      ...options,
      headers: {
        Accept: 'application/json',
        ...(options.body ? { 'Content-Type': 'application/json' } : {}),
        ...options.headers,
      },
    })
  } catch {
    throw new RentalApplicationApiError(
      'Unable to connect to the rental application service. Please try again.',
    )
  }

  if (!response.ok) {
    throw new RentalApplicationApiError(
      await readSafeErrorMessage(response),
      response.status,
    )
  }

  try {
    return await response.json()
  } catch {
    throw new RentalApplicationApiError(
      'The rental application service returned an invalid response.',
      response.status,
    )
  }
}

async function readSafeErrorMessage(response) {
  const fallback = 'The rental application request failed. Please try again.'

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
    // Never expose non-JSON bodies, stack traces, or proxy details.
  }

  return fallback
}

function applicationPath(id, action = '') {
  const encodedId = encodeURIComponent(id)
  return `/api/rental-applications/${encodedId}${action ? `/${action}` : ''}`
}

export function getApplicationsByProperty(propertyId) {
  return request(
    `/api/rental-applications/property/${encodeURIComponent(propertyId)}`,
  )
}

export function getApplicationById(id) {
  return request(applicationPath(id))
}

export function markUnderReview(id) {
  return request(applicationPath(id, 'review'), { method: 'PATCH' })
}

export function approveApplication(id, landlordResponse = '') {
  return request(applicationPath(id, 'approve'), {
    method: 'PATCH',
    body: JSON.stringify({
      landlordResponse: landlordResponse.trim() || null,
    }),
  })
}

export function rejectApplication(id, landlordReason) {
  return request(applicationPath(id, 'reject'), {
    method: 'PATCH',
    body: JSON.stringify({ landlordResponse: landlordReason.trim() }),
  })
}

export function requestChanges(id, landlordMessage) {
  return request(applicationPath(id, 'request-changes'), {
    method: 'PATCH',
    body: JSON.stringify({ landlordResponse: landlordMessage.trim() }),
  })
}
