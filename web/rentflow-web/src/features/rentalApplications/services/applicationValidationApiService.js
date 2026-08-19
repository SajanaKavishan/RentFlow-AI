const API_BASE_URL = (
  import.meta.env.VITE_API_BASE_URL || 'http://localhost:5277'
).replace(/\/+$/, '')

export class ApplicationValidationApiError extends Error {
  constructor(message, statusCode = null) {
    super(message)
    this.name = 'ApplicationValidationApiError'
    this.statusCode = statusCode
  }
}

async function readSafeErrorMessage(response) {
  const fallback = 'The validation request failed. Please try again.'

  try {
    const body = await response.json()
    const message = [body.detail, body.title, body.message].find(
      (value) => typeof value === 'string' && value.trim(),
    )
    return message?.trim() || fallback
  } catch {
    return fallback
  }
}

async function request(path, options = {}) {
  let response

  try {
    response = await fetch(`${API_BASE_URL}${path}`, {
      ...options,
      headers: {
        Accept: 'application/json',
        ...options.headers,
      },
    })
  } catch {
    throw new ApplicationValidationApiError(
      'Unable to connect to the validation service. Please try again.',
    )
  }

  if (!response.ok) {
    throw new ApplicationValidationApiError(
      await readSafeErrorMessage(response),
      response.status,
    )
  }

  try {
    return await response.json()
  } catch {
    throw new ApplicationValidationApiError(
      'The validation service returned an invalid response.',
      response.status,
    )
  }
}

function validationRunsPath(applicationId) {
  return `/api/rental-applications/${encodeURIComponent(applicationId)}/validation-runs`
}

export function getApplicationValidationRuns(applicationId) {
  return request(validationRunsPath(applicationId))
}

export function runApplicationValidation(applicationId) {
  return request(validationRunsPath(applicationId), { method: 'POST' })
}
