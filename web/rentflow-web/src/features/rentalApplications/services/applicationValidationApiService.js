import { ApiError, apiRequest } from '../../../core/api/apiClient.js'

export class ApplicationValidationApiError extends ApiError {
  constructor(message, statusCode = null) {
    super(message)
    this.name = 'ApplicationValidationApiError'
    this.statusCode = statusCode
  }
}

async function request(path, options = {}) {
  try {
    return await apiRequest(path, {
      ...options,
      errorMessage: 'The validation request failed. Please try again.',
      networkErrorMessage: 'Unable to connect to the validation service. Please try again.',
    })
  } catch (error) {
    if (error instanceof ApiError) throw new ApplicationValidationApiError(error.message, error.statusCode)
    throw error
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
