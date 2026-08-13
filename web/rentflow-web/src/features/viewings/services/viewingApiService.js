const API_BASE_URL = (
  import.meta.env.VITE_API_BASE_URL || 'http://localhost:5277'
).replace(/\/+$/, '')

export const VIEWING_STATUS = Object.freeze({
  PENDING: 0,
  APPROVED: 1,
  REJECTED: 2,
  CANCELLED: 3,
  COMPLETED: 4,
})

export class ViewingApiError extends Error {
  constructor(message, statusCode = null) {
    super(message)
    this.name = 'ViewingApiError'
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
    throw new ViewingApiError(
      'Unable to connect to the viewing service. Please try again.',
    )
  }

  if (!response.ok) {
    throw new ViewingApiError(
      await readSafeErrorMessage(response),
      response.status,
    )
  }

  try {
    return await response.json()
  } catch {
    throw new ViewingApiError(
      'The viewing service returned an invalid response.',
      response.status,
    )
  }
}

async function readSafeErrorMessage(response) {
  const fallback = 'The viewing request failed. Please try again.'

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
    // Do not expose non-JSON response bodies, server traces, or proxy details.
  }

  return fallback
}

export function getViewingsByProperty(propertyId) {
  return request(`/api/viewings/property/${encodeURIComponent(propertyId)}`)
}

export function getViewingById(id) {
  return request(`/api/viewings/${encodeURIComponent(id)}`)
}

export function approveViewing(id, landlordResponse = '') {
  return request(`/api/viewings/${encodeURIComponent(id)}/approve`, {
    method: 'PATCH',
    body: JSON.stringify({
      status: VIEWING_STATUS.APPROVED,
      landlordResponse: landlordResponse.trim() || null,
    }),
  })
}

export function rejectViewing(id, landlordResponse) {
  return request(`/api/viewings/${encodeURIComponent(id)}/reject`, {
    method: 'PATCH',
    body: JSON.stringify({
      status: VIEWING_STATUS.REJECTED,
      landlordResponse: landlordResponse.trim(),
    }),
  })
}
