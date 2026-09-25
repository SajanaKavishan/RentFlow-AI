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

export async function updateProfile(details) {
  return parseCurrentUser(await apiRequest('/api/auth/profile', {
    method: 'PUT', body: JSON.stringify(details),
    errorMessage: 'Your profile could not be updated.',
  }))
}

function parseChangePasswordResponse(response) {
  if (!response || typeof response.accessToken !== 'string' || !response.accessToken.trim()
    || typeof response.message !== 'string' || typeof response.expiresAt !== 'string') {
    throw new TypeError('The server returned an invalid password-change response.')
  }
  return response
}

export async function changePassword(details) {
  return parseChangePasswordResponse(await apiRequest('/api/auth/change-password', {
    method: 'PUT', body: JSON.stringify(details),
    errorMessage: 'Your password could not be changed.',
  }))
}

export async function uploadProfileImage(file) {
  const body = new FormData()
  body.append('file', file)
  return parseCurrentUser(await apiRequest('/api/auth/profile-image', {
    method: 'POST', body,
    errorMessage: 'Your profile image could not be uploaded.',
  }))
}

export async function getProfileImage() {
  const response = await apiRequest('/api/auth/profile-image', {
    parse: 'response',
    errorMessage: 'Your profile image could not be loaded.',
  })
  return response.blob()
}
