import { beforeEach, expect, it, vi } from 'vitest'
import { apiRequest } from '../../core/api/apiClient.js'
import { getLandlordActionSummary } from './useLandlordActionSummary.js'
vi.mock('../../core/api/apiClient.js', () => ({ apiRequest: vi.fn() }))
beforeEach(() => vi.resetAllMocks())
it('uses one authenticated no-store request with no caller-supplied Landlord ID', async () => {
  apiRequest.mockResolvedValue({ maintenanceCount: 0, maintenanceByProperty: [], leaseCount: 0, paymentCount: 0 })
  const signal = new AbortController().signal
  await getLandlordActionSummary(signal)
  expect(apiRequest).toHaveBeenCalledTimes(1)
  expect(apiRequest).toHaveBeenCalledWith('/api/landlord/actions/summary', expect.objectContaining({ signal, cache: 'no-store' }))
  expect(apiRequest.mock.calls[0][1].authenticated).toBeUndefined()
})
it.each([
  { maintenanceCount: 1, maintenanceByProperty: [], leaseCount: 0, paymentCount: 0 },
  { maintenanceCount: 0, maintenanceByProperty: [], leaseCount: -1, paymentCount: 0 },
  { maintenanceCount: 2, maintenanceByProperty: [{ propertyId: 'home', count: 1 }, { propertyId: 'HOME', count: 1 }], leaseCount: 0, paymentCount: 0 },
])('rejects inconsistent counts instead of displaying fabricated values', async (data) => {
  apiRequest.mockResolvedValue(data)
  await expect(getLandlordActionSummary()).rejects.toThrow('Invalid action summary')
})
