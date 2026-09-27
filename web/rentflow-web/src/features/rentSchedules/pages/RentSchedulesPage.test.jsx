import { cleanup, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { tokenStorage } from '../../../core/auth/tokenStorage.js'
import RentSchedulesPage from './RentSchedulesPage.jsx'

const firstLeaseId = '11111111-1111-1111-1111-111111111111'
const secondLeaseId = '22222222-2222-2222-2222-222222222222'
const itemId = '33333333-3333-3333-3333-333333333333'

function lease(id, status = 1) {
  return { id, propertyId: '44444444-4444-4444-4444-444444444444', tenantId: '55555555-5555-5555-5555-555555555555', monthlyRent: 85000, startDate: '2026-10-01', endDate: '2027-09-30', status }
}

function scheduleItem(overrides = {}) {
  return { id: itemId, leaseAgreementId: firstLeaseId, dueDate: '2026-10-01', amount: 85000, status: 0, createdAt: '2026-09-27T10:00:00Z', updatedAt: null, ...overrides }
}

function response(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

function setupApi({ leases = [lease(firstLeaseId)], schedules = {}, listStatus = 200, scheduleStatus = 200, generateStatus = 200 } = {}) {
  const fetchMock = vi.fn((url, options = {}) => {
    if (url.endsWith('/api/lease-agreements/landlord')) return Promise.resolve(response(leases, listStatus))
    if (url.endsWith('/generate') && options.method === 'POST') return Promise.resolve(response(generateStatus === 200 ? [scheduleItem()] : { message: 'A rent schedule already exists.' }, generateStatus))
    if (url.endsWith(`/api/rent-schedules/${itemId}`)) return Promise.resolve(response(scheduleItem()))
    if (url.includes('/api/rent-schedules/lease/')) {
      const id = url.split('/').at(-1)
      return Promise.resolve(response(scheduleStatus === 200 ? schedules[id] ?? [] : { detail: 'Database stack trace' }, scheduleStatus))
    }
    return Promise.resolve(response({ message: 'Not found' }, 404))
  })
  vi.stubGlobal('fetch', fetchMock)
  tokenStorage.setToken('landlord-token')
  render(<MemoryRouter initialEntries={['/modules/pricing-lease/schedules']}><RentSchedulesPage /></MemoryRouter>)
  return fetchMock
}

afterEach(() => { cleanup(); vi.unstubAllGlobals(); tokenStorage.clearToken() })

describe('landlord rent schedules', () => {
  it('renders schedule items and fetches detail by item ID', async () => {
    const fetchMock = setupApi({ schedules: { [firstLeaseId]: [scheduleItem()] } })
    await userEvent.selectOptions(await screen.findByLabelText('Lease agreement'), firstLeaseId)
    expect(await screen.findByText('2026-10-01')).toBeInTheDocument()
    expect(screen.getAllByText('85,000.00')).toHaveLength(2)
    await userEvent.click(screen.getByRole('button', { name: 'View details' }))
    expect(await screen.findByText('Schedule item details')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining(`/api/rent-schedules/${itemId}`), expect.any(Object))
  })

  it('shows no lease and no selection states', async () => {
    setupApi({ leases: [] })
    expect(await screen.findByText('No lease agreements yet.')).toBeInTheDocument()
    cleanup()
    setupApi()
    expect(await screen.findByText('Select a lease to view its rent schedule.')).toBeInTheDocument()
  })

  it('loads the selected lease schedule and handles an empty schedule', async () => {
    const fetchMock = setupApi({ leases: [lease(firstLeaseId), lease(secondLeaseId)], schedules: { [firstLeaseId]: [scheduleItem()] } })
    const selector = await screen.findByLabelText('Lease agreement')
    await userEvent.selectOptions(selector, firstLeaseId)
    expect(await screen.findByText('2026-10-01')).toBeInTheDocument()
    await userEvent.selectOptions(selector, secondLeaseId)
    expect(await screen.findByText('No rent schedule has been generated for this lease.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'View details' })).not.toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining(`/api/rent-schedules/lease/${secondLeaseId}`), expect.any(Object))
  })

  it('generates only for an active lease using the POST endpoint', async () => {
    const fetchMock = setupApi()
    await userEvent.selectOptions(await screen.findByLabelText('Lease agreement'), firstLeaseId)
    await userEvent.click(await screen.findByRole('button', { name: 'Generate rent schedule' }))
    expect(await screen.findByText('Rent schedule generated successfully.')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining(`/api/rent-schedules/lease/${firstLeaseId}/generate`), expect.objectContaining({ method: 'POST', headers: expect.objectContaining({ Authorization: 'Bearer landlord-token' }) }))
    expect(screen.getByRole('button', { name: 'View details' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Generate rent schedule' })).not.toBeInTheDocument()
  })

  it('does not offer generation for a pending lease', async () => {
    setupApi({ leases: [lease(firstLeaseId, 0)] })
    await userEvent.selectOptions(await screen.findByLabelText('Lease agreement'), firstLeaseId)
    expect(await screen.findByText('Only an active lease can have a schedule generated.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Generate rent schedule' })).not.toBeInTheDocument()
  })

  it('shows a safe schedule API error without server detail', async () => {
    setupApi({ scheduleStatus: 500 })
    await userEvent.selectOptions(await screen.findByLabelText('Lease agreement'), firstLeaseId)
    expect(await screen.findByRole('alert')).toHaveTextContent('Unable to load the rent schedule.')
    expect(screen.queryByText('Database stack trace')).not.toBeInTheDocument()
  })

  it('shows a conflict when generation is rejected', async () => {
    setupApi({ generateStatus: 409 })
    await userEvent.selectOptions(await screen.findByLabelText('Lease agreement'), firstLeaseId)
    await userEvent.click(await screen.findByRole('button', { name: 'Generate rent schedule' }))
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('a rent schedule already exists'))
  })
})
