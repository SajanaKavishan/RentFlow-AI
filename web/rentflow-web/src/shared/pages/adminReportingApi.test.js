import { beforeEach, expect, it, vi } from 'vitest'
import { apiRequest } from '../../core/api/apiClient.js'
import { getAdminReport } from './adminReportingApi.js'
vi.mock('../../core/api/apiClient.js', async (importOriginal) => ({ ...(await importOriginal()), apiRequest: vi.fn() }))
beforeEach(() => vi.resetAllMocks())
it('uses only the authenticated Admin aggregate endpoint', async () => {
  apiRequest.mockResolvedValue({ propertyCount: 0, activeApplicationCount: 0, monthlyVolume: 0, month: '2026-10' })
  const controller = new AbortController()
  expect((await getAdminReport('summary', controller.signal)).propertyCount).toBe(0)
  expect(apiRequest).toHaveBeenCalledWith('/api/admin/dashboard/summary', expect.objectContaining({ signal: controller.signal, cache: 'no-store' }))
  expect(apiRequest.mock.calls[0][1].authenticated).toBeUndefined()
})
it.each([
  ['summary', { propertyCount: -1, activeApplicationCount: 0, monthlyVolume: 0, month: '2026-10' }],
  ['activity', [{ kind: 'Event', description: 'Text', occurredAt: 'bad-date' }]],
  ['workflows', []],
  ['health', { checkedAt: '2026-10-06T10:00:00Z', services: [{ name: 'Agent', status: 'pretend', detail: 'Text' }] }],
])('rejects invalid %s reporting instead of inventing values', async (kind, data) => {
  apiRequest.mockResolvedValue(data)
  await expect(getAdminReport(kind)).rejects.toThrow('invalid report')
})
