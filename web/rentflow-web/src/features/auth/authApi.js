import { apiRequest } from '../../core/api/apiClient.js'
import { parseCurrentUser } from './authModel.js'

function parseAuthResponse(response) {
  if (!response || typeof response.accessToken !== 'string') {
    throw new TypeError('The server returned an invalid authentication response.')
  }
  return { ...response, user: parseCurrentUser(response.user) }
}

export async function login(credentials) {
  return parseAuthResponse(await apiRequest('/api/auth/login', {
    method: 'POST', body: JSON.stringify(credentials), authenticated: false,
    handleUnauthorized: false, errorMessage: 'Email or password is incorrect.',
    networkErrorMessage: 'Unable to connect. Please try again.',
  }))
}

export async function register(details) {
  return parseAuthResponse(await apiRequest('/api/auth/register', {
    method: 'POST', body: JSON.stringify(details), authenticated: false,
    handleUnauthorized: false, errorMessage: 'Registration could not be completed.',
    networkErrorMessage: 'Unable to connect. Please try again.',
  }))
}

export async function getCurrentUser() {
  return parseCurrentUser(await apiRequest('/api/auth/me', {
    errorMessage: 'Your session is no longer valid.',
  }))
}
