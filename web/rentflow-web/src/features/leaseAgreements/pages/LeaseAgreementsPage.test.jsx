import { cleanup, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { tokenStorage } from '../../../core/auth/tokenStorage.js'
import LeaseAgreementsPage from './LeaseAgreementsPage.jsx'

const propertyId = '11111111-1111-1111-1111-111111111111'
const offerId = '22222222-2222-2222-2222-222222222222'
const otherOfferId = '33333333-3333-3333-3333-333333333333'
const leaseId = '44444444-4444-4444-4444-444444444444'
const tenantId = '55555555-5555-5555-5555-555555555555'

function lease(overrides = {}) {
  return { id: leaseId, rentalOfferId: offerId, tenantId, propertyId, monthlyRent: 85000, securityDeposit: 170000, startDate: '2026-11-01', endDate: '2027-10-31', status: 0, createdAt: '2026-09-27T10:00:00Z', updatedAt: null, ...overrides }
}

function offer(overrides = {}) {
  return { id: offerId, tenantId, propertyId, monthlyRent: 85000, proposedStartDate: '2026-11-01', proposedEndDate: '2027-10-31', status: 1, ...overrides }
}

function response(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

function setupApi({ leases = [], offers = [], leaseListStatus = 200 } = {}) {
  const fetchMock = vi.fn((url, options = {}) => {
    if (url.endsWith('/api/lease-agreements/landlord')) return Promise.resolve(response(leases, leaseListStatus))
    if (url.endsWith('/api/rental-offers/landlord')) return Promise.resolve(response(offers))
    if (url.endsWith('/api/properties/mine')) return Promise.resolve(response([{ id: propertyId, title: 'Lake House' }]))
    if (options.method === 'POST') return Promise.resolve(response(lease(), 201))
    if (options.method === 'PATCH') {
      const status = url.endsWith('/activate') ? 1 : url.endsWith('/terminate') ? 2 : 3
      return Promise.resolve(response(lease({ status, updatedAt: '2026-09-28T10:00:00Z' })))
    }
    if (url.endsWith(`/api/lease-agreements/${leaseId}`)) return Promise.resolve(response(lease(leases[0])))
    return Promise.resolve(response({ message: 'Not found' }, 404))
  })
  vi.stubGlobal('fetch', fetchMock)
  tokenStorage.setToken('landlord-token')
  render(<MemoryRouter initialEntries={['/modules/pricing-lease/leases']}><LeaseAgreementsPage /></MemoryRouter>)
  return fetchMock
}

afterEach(() => { cleanup(); vi.unstubAllGlobals(); tokenStorage.clearToken() })

describe('landlord lease agreements', () => {
  it('renders leases and opens details', async () => {
    const fetchMock = setupApi({ leases: [lease()] })
    expect(await screen.findByText(/Monthly rent 85,000/)).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'View details' }))
    expect(await screen.findByText('170,000')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining(`/api/lease-agreements/${leaseId}`), expect.any(Object))
  })

  it('shows empty lease and eligible offer states', async () => {
    setupApi()
    expect(await screen.findByText('No lease agreements yet.')).toBeInTheDocument()
    expect(await screen.findByText('No accepted rental offers without a lease are available.')).toBeInTheDocument()
  })

  it('creates a lease with only the selected accepted rental offer ID', async () => {
    const fetchMock = setupApi({ offers: [offer(), offer({ id: otherOfferId, status: 0 })] })
    const select = await screen.findByLabelText('Accepted rental offer')
    expect(select.options).toHaveLength(2)
    await userEvent.selectOptions(select, offerId)
    await userEvent.click(screen.getByRole('button', { name: 'Create lease' }))
    await waitFor(() => expect(fetchMock.mock.calls.some(([, options]) => options?.method === 'POST')).toBe(true))
    const [url, options] = fetchMock.mock.calls.find(([, request]) => request?.method === 'POST')
    expect(url).toContain('/api/lease-agreements')
    expect(options.headers.Authorization).toBe('Bearer landlord-token')
    expect(JSON.parse(options.body)).toEqual({ rentalOfferId: offerId })
    expect(await screen.findByText('Lease agreement created successfully.')).toBeInTheDocument()
  })

  it('excludes an accepted offer that already has a lease', async () => {
    setupApi({ leases: [lease()], offers: [offer(), offer({ id: otherOfferId })] })
    const select = await screen.findByLabelText('Accepted rental offer')
    expect(Array.from(select.options).map((option) => option.value)).toEqual(['', otherOfferId])
  })

  it('shows a safe list API error', async () => {
    setupApi({ leases: { detail: 'Database stack trace' }, leaseListStatus: 500 })
    expect(await screen.findByRole('alert')).toHaveTextContent('Unable to load lease agreements.')
    expect(screen.queryByText('Database stack trace')).not.toBeInTheDocument()
  })

  it('activates a pending lease through the ASP.NET PATCH endpoint', async () => {
    const fetchMock = setupApi({ leases: [lease()] })
    await userEvent.click(await screen.findByRole('button', { name: 'View details' }))
    await userEvent.click(await screen.findByRole('button', { name: 'Activate lease' }))
    expect(await screen.findByText('Lease agreement activated.')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining(`/api/lease-agreements/${leaseId}/activate`), expect.objectContaining({ method: 'PATCH' }))
  })

  it('offers terminate and complete only for active leases', async () => {
    const fetchMock = setupApi({ leases: [lease({ status: 1 })] })
    await userEvent.click(await screen.findByRole('button', { name: 'View details' }))
    expect(await screen.findByRole('button', { name: 'Terminate lease' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Complete lease' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Activate lease' })).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Complete lease' }))
    expect(await screen.findByText('Lease agreement completed.')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining(`/api/lease-agreements/${leaseId}/complete`), expect.objectContaining({ method: 'PATCH' }))
  })
})
