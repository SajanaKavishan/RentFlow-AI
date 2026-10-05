import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { apiRequest } from '../../../core/api/apiClient.js'
import { tokenStorage } from '../../../core/auth/tokenStorage.js'
import {
  downloadApplicationDocument,
  getApplicationDocuments,
} from '../../applicationDocuments/services/applicationDocumentApiService.js'
import {
  getApplicationValidationRuns,
  runApplicationValidation,
} from './applicationValidationApiService.js'
import {
  approveApplication,
  getApplicationsByProperty,
  getApplicationEligibility,
} from './rentalApplicationApiService.js'

const applicationId = '33333333-3333-3333-3333-333333333333'
const propertyId = '22222222-2222-2222-2222-222222222222'

function jsonResponse(body = [], status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

describe('JWT client contracts', () => {
  beforeEach(() => {
    tokenStorage.setToken('test-token')
    vi.stubGlobal('fetch', vi.fn().mockImplementation(() => Promise.resolve(jsonResponse())))
  })

  afterEach(() => {
    tokenStorage.clearToken()
    vi.unstubAllGlobals()
  })

  it('uses the authenticated shared client for validation routes', async () => {
    await getApplicationValidationRuns(applicationId)
    await runApplicationValidation(applicationId)

    expect(fetch).toHaveBeenCalledTimes(2)
    for (const [url, options] of fetch.mock.calls) {
      expect(url).toContain(
        `/api/rental-applications/${applicationId}/validation-runs`,
      )
      expect(url).not.toContain('tenantId')
      expect(options.headers.Authorization).toBe('Bearer test-token')
    }
    expect(fetch.mock.calls[0][1].method).toBeUndefined()
    expect(fetch.mock.calls[1][1].method).toBe('POST')
  })

  it('checks property eligibility with JWT and no supplied tenant identity', async () => {
    fetch.mockResolvedValueOnce(jsonResponse({ canApply: true, hasCompletedViewing: true, reason: null }))
    expect(await getApplicationEligibility(propertyId)).toMatchObject({ canApply: true })
    const [url, options] = fetch.mock.calls[0]
    expect(url).toContain(`/api/properties/${propertyId}/rental-application-eligibility`)
    expect(url).not.toContain('tenantId')
    expect(options.headers.Authorization).toBe('Bearer test-token')
  })

  it.each([{}, { canApply: true, hasCompletedViewing: false }, { canApply: false, hasCompletedViewing: true, existingApplicationId: applicationId }])('rejects malformed eligibility %j', async (body) => {
    fetch.mockResolvedValueOnce(jsonResponse(body))
    await expect(getApplicationEligibility(propertyId)).rejects.toThrow('Unable to check application eligibility. Please try again.')
  })

  it('displays the backend viewing business rejection safely', async () => {
    const message = 'Complete a viewing for this property before starting a rental application.'
    fetch.mockResolvedValueOnce(jsonResponse({ detail: message }, 409))
    await expect(getApplicationEligibility(propertyId)).rejects.toMatchObject({ message, statusCode: 409 })
  })

  it('keeps landlord review resource IDs without tenant identity parameters', async () => {
    await getApplicationsByProperty(propertyId)
    await approveApplication(applicationId, 'Approved')

    expect(fetch.mock.calls[0][0]).toContain(
      `/api/rental-applications/property/${propertyId}`,
    )
    expect(fetch.mock.calls[1][0]).toContain(
      `/api/rental-applications/${applicationId}/approve`,
    )
    for (const [url, options] of fetch.mock.calls) {
      expect(url).not.toContain('tenantId')
      expect(options.headers.Authorization).toBe('Bearer test-token')
    }
  })

  it('loads application documents without a tenantId query parameter', async () => {
    await getApplicationDocuments(applicationId)

    const [url, options] = fetch.mock.calls[0]
    expect(url).toContain(
      `/api/rental-applications/${applicationId}/documents`,
    )
    expect(url).not.toContain('tenantId')
    expect(options.headers.Authorization).toBe('Bearer test-token')
  })

  it('opens an authenticated document response without exposing a storage key', async () => {
    const documentId = '44444444-4444-4444-4444-444444444444'
    const replace = vi.fn()
    const downloadWindow = {
      opener: window,
      location: { replace },
      close: vi.fn(),
    }
    const createObjectURL = vi.fn(() => 'blob:rentflow-document')
    const revokeObjectURL = vi.fn()
    const documentResponse = new Response('private document', { status: 200 })
    vi.spyOn(window, 'open').mockReturnValue(downloadWindow)
    vi.spyOn(window, 'setTimeout').mockImplementation(() => 1)
    vi.stubGlobal('URL', { createObjectURL, revokeObjectURL })
    fetch.mockResolvedValueOnce(documentResponse)

    await downloadApplicationDocument(documentId)

    const [url, options] = fetch.mock.calls[0]
    expect(url).toContain(`/api/application-documents/${documentId}/download`)
    expect(url).not.toContain('storageKey')
    expect(options.headers.Authorization).toBe('Bearer test-token')
    expect(downloadWindow.opener).toBeNull()
    expect(createObjectURL).toHaveBeenCalledOnce()
    expect(replace).toHaveBeenCalledWith('blob:rentflow-document')
  })

  it.each([
    [403, 'You do not have permission to access this resource.'],
    [404, 'The requested resource is unavailable.'],
    [409, 'This action conflicts with the current application state.'],
  ])('returns a safe message for HTTP %s', async (status, message) => {
    fetch.mockResolvedValueOnce(
      jsonResponse(
        {
          detail:
            status === 409
              ? 'This action conflicts with the current application state.'
              : 'private implementation detail',
        },
        status,
      ),
    )

    await expect(apiRequest('/api/test')).rejects.toMatchObject({
      message,
      statusCode: status,
    })
  })
})
