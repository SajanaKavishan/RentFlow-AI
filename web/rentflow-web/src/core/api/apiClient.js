import { tokenStorage } from '../auth/tokenStorage.js'
import { API_BASE_URL } from './apiConfig.js'

let unauthorizedHandler = null
let isHandlingUnauthorized = false

export class ApiError extends Error {
  constructor(message, statusCode = null) {
    super(message)
    this.name = 'ApiError'
    this.statusCode = statusCode
  }
}

export function setUnauthorizedHandler(handler) {
  unauthorizedHandler = handler
  return () => {
    if (unauthorizedHandler === handler) unauthorizedHandler = null
  }
}

export async function readSafeErrorMessage(response, fallback) {
  try {
    const body = await response.clone().json()
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
    // Non-JSON bodies and server traces are intentionally not exposed.
  }
  return fallback
}

async function handleUnauthorized() {
  tokenStorage.clearToken()
  if (isHandlingUnauthorized || !unauthorizedHandler) return
  isHandlingUnauthorized = true
  try {
    await unauthorizedHandler()
  } finally {
    isHandlingUnauthorized = false
  }
}

export async function apiRequest(path, options = {}) {
  const {
    authenticated = true,
    handleUnauthorized: shouldHandleUnauthorized = authenticated,
    parse = 'json',
    errorMessage = 'The request failed. Please try again.',
    networkErrorMessage = 'Unable to connect to the service. Please try again.',
    headers,
    ...fetchOptions
  } = options
  const token = authenticated ? tokenStorage.getToken() : null
  let response
  try {
    response = await fetch(`${API_BASE_URL}${path}`, {
      ...fetchOptions,
      headers: {
        Accept: 'application/json',
        ...(fetchOptions.body && !(fetchOptions.body instanceof FormData)
          ? { 'Content-Type': 'application/json' }
          : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...headers,
      },
    })
  } catch {
    throw new ApiError(networkErrorMessage)
  }
  if (response.status === 401 && shouldHandleUnauthorized) await handleUnauthorized()
  if (!response.ok) {
    throw new ApiError(await readSafeErrorMessage(response, errorMessage), response.status)
  }
  if (parse === 'response') return response
  if (parse === 'none' || response.status === 204) return undefined
  try {
    return await response.json()
  } catch {
    throw new ApiError('The service returned an invalid response.', response.status)
  }
}
