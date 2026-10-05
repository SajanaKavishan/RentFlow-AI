import { cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { tokenStorage } from '../../../core/auth/tokenStorage.js'
import TenantLeasePaymentsPage from './TenantLeasePaymentsPage.jsx'

const offer = { id: 'offer-1', propertyId: 'property-1', rentalApplicationId: 'application-1', monthlyRent: 1200, securityDeposit: 2400, proposedStartDate: '2026-11-01', proposedEndDate: '2027-10-31', expiresAt: '2099-10-01T00:00:00Z', status: 0, landlordNote: 'Welcome', createdAt: '2026-09-01T00:00:00Z' }
const lease = { id: 'lease-1', rentalOfferId: 'offer-1', propertyId: 'property-1', monthlyRent: 1200, securityDeposit: 2400, startDate: '2026-11-01', endDate: '2027-10-31', status: 1, createdAt: '2026-09-02T00:00:00Z' }
const schedule = { id: 'schedule-1', leaseAgreementId: 'lease-1', dueDate: '2026-11-01', amount: 1200, status: 0, createdAt: '2026-09-03T00:00:00Z' }
const payment = { id: 'payment-1', rentScheduleItemId: 'schedule-1', amount: 1200, status: 0, paymentMethod: 'Bank transfer', transactionReference: 'REF-1', createdAt: '2026-09-04T00:00:00Z' }
const json = (value, status = 200) => new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json' } })
let data

function renderPage() {
  return render(<MemoryRouter><TenantLeasePaymentsPage /></MemoryRouter>)
}

async function tab(name) {
  await userEvent.click(screen.getByRole('button', { name, exact: true }))
}

async function selectLease() {
  await tab('Rent Schedule')
  await screen.findByRole('option', { name: /Property property-1/ })
  await userEvent.selectOptions(screen.getByLabelText('Lease'), 'lease-1')
}

beforeEach(() => {
  tokenStorage.setToken('tenant-token')
  data = { offers: [offer], leases: [lease], schedule: [schedule], payments: [payment] }
  vi.stubGlobal('fetch', vi.fn(async (url, options = {}) => {
    const path = new URL(url, 'http://localhost').pathname
    if (path === '/api/rental-offers/mine') return json(data.offers)
    if (path === '/api/rental-offers/offer-1') return json(data.offers[0])
    if (path === '/api/rental-offers/offer-1/accept' || path === '/api/rental-offers/offer-1/reject') {
      const status = path.endsWith('/accept') ? 1 : 2
      data.offers = [{ ...offer, status }]
      return json(data.offers[0])
    }
    if (path === '/api/lease-agreements/mine') return json(data.leases)
    if (path === '/api/lease-agreements/lease-1') return json(data.leases[0])
    if (path === '/api/rent-schedules/lease/lease-1') return json(data.schedule)
    if (path === '/api/rent-schedules/schedule-1') return json(data.schedule[0])
    if (path === '/api/payments/mine') return json(data.payments)
    if (path === '/api/payments/payment-1') return json(data.payments[0])
    if (path === '/api/payments' && options.method === 'POST') {
      data.payments = [payment]
      return json(payment, 201)
    }
    throw new Error(`Unexpected request: ${path}`)
  }))
})
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('tenant Lease & Payments', () => {
  it('lists tenant offers from the authenticated API', async () => {
    renderPage()
    expect(await screen.findByText('Property property-1')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Refresh' })).not.toBeInTheDocument()
    expect(fetch).toHaveBeenCalledWith(expect.stringContaining('/api/rental-offers/mine'), expect.objectContaining({ headers: expect.objectContaining({ Authorization: 'Bearer tenant-token' }) }))
  })

  it('shows an empty offer state', async () => {
    data.offers = []
    renderPage()
    expect(await screen.findByText('No rental offers yet.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Refresh' })).not.toBeInTheDocument()
  })

  it.each([['accept', 'Accept offer', 'Accepted'], ['reject', 'Reject offer', 'Rejected']])('%ss a Pending offer and refreshes the list', async (action, label, status) => {
    renderPage()
    await userEvent.click(await screen.findByRole('button', { name: 'View details' }))
    expect(await screen.findByText('Welcome')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: label }))
    expect(await screen.findByText(new RegExp(`Rental offer ${action}ed`))).toBeInTheDocument()
    expect(within(screen.getByText('Offer details').closest('section')).getByText(status)).toBeInTheDocument()
    expect(fetch).toHaveBeenCalledWith(expect.stringContaining(`/api/rental-offers/offer-1/${action}`), expect.objectContaining({ method: 'PATCH' }))
    expect(fetch.mock.calls.filter(([url]) => url.endsWith('/api/rental-offers/mine')).length).toBeGreaterThan(1)
  })

  it('lists leases and opens read-only details', async () => {
    renderPage()
    await tab('My Leases')
    expect(screen.queryByRole('button', { name: 'Refresh' })).not.toBeInTheDocument()
    expect(await screen.findByText('Property property-1')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'View details' }))
    expect(await screen.findByText('Lease details')).toBeInTheDocument()
    expect(screen.getByText('2,400.00')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Activate|Terminate|Complete/ })).not.toBeInTheDocument()
  })

  it('shows an empty lease state', async () => {
    data.leases = []
    renderPage()
    await tab('My Leases')
    expect(await screen.findByText(/No leases yet/)).toBeInTheDocument()
  })

  it('loads a selected lease schedule and item details without generation controls', async () => {
    renderPage()
    await selectLease()
    expect(await screen.findByText('Due 2026-11-01')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Refresh' })).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'View details' }))
    expect(await screen.findByText('Schedule item details')).toBeInTheDocument()
    expect(fetch).toHaveBeenCalledWith(expect.stringContaining('/api/rent-schedules/lease/lease-1'), expect.anything())
    expect(screen.queryByRole('button', { name: /Generate/ })).not.toBeInTheDocument()
  })

  it('shows no selected lease and an empty schedule', async () => {
    data.schedule = []
    renderPage()
    await tab('Rent Schedule')
    expect(screen.getByText('Select a lease to view its rent schedule.')).toBeInTheDocument()
    await userEvent.selectOptions(await screen.findByLabelText('Lease'), 'lease-1')
    expect(await screen.findByText('No rent schedule has been generated for this lease yet.')).toBeInTheDocument()
  })

  it('lists payment history and opens payment detail without landlord controls', async () => {
    renderPage()
    await tab('Payments')
    expect(await screen.findByText('Bank transfer')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Refresh' })).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'View details' }))
    expect(await screen.findByText('Payment details')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Complete payment|Mark as failed/ })).not.toBeInTheDocument()
  })

  it('shows an empty payment history', async () => {
    data.payments = []
    renderPage()
    await tab('Payments')
    expect(await screen.findByText('No payments yet.')).toBeInTheDocument()
  })

  it('creates a Pending payment with only the supported request fields', async () => {
    renderPage()
    await selectLease()
    await screen.findByText('Due 2026-11-01')
    await tab('Payments')
    await userEvent.selectOptions(screen.getByLabelText('Rent schedule item'), 'schedule-1')
    await userEvent.type(screen.getByLabelText('Payment method'), 'Bank transfer')
    await userEvent.type(screen.getByLabelText('Transaction reference (optional)'), 'REF-1')
    await userEvent.click(screen.getByRole('button', { name: 'Create payment' }))
    expect(await screen.findByText(/Payment created as Pending/)).toBeInTheDocument()
    const [, options] = fetch.mock.calls.find(([url, init]) => url.endsWith('/api/payments') && init.method === 'POST')
    expect(JSON.parse(options.body)).toEqual({ rentScheduleItemId: 'schedule-1', paymentMethod: 'Bank transfer', transactionReference: 'REF-1' })
    expect(screen.queryByLabelText(/Payment amount/)).not.toBeInTheDocument()
  })

  it('shows frontend validation and backend conflict errors safely', async () => {
    renderPage()
    await selectLease()
    await screen.findByText('Due 2026-11-01')
    await tab('Payments')
    await userEvent.click(screen.getByRole('button', { name: 'Create payment' }))
    expect(screen.getByRole('alert')).toHaveTextContent('Select an unpaid schedule item')
    fetch.mockImplementation(async (url) => url.endsWith('/api/payments') ? json({ message: 'Internal database detail' }, 409) : json([]))
    await userEvent.selectOptions(screen.getByLabelText('Rent schedule item'), 'schedule-1')
    await userEvent.type(screen.getByLabelText('Payment method'), 'Bank transfer')
    await userEvent.click(screen.getByRole('button', { name: 'Create payment' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('This action is no longer available.')
    expect(screen.queryByText('Internal database detail')).not.toBeInTheDocument()
  })

  it.each([
    [400, 'Valid payment information is required.'],
    [401, 'Your session has expired. Please sign in again.'],
    [403, 'You do not have permission to access this resource.'],
    [404, 'The requested item could not be found. Refresh and try again.'],
    [409, 'This action is no longer available. Refresh and try again.'],
    [500, 'Unable to load details.'],
  ])('handles detail HTTP %s without exposing server internals', async (status, expected) => {
    renderPage()
    const button = await screen.findByRole('button', { name: 'View details' })
    const previous = fetch.getMockImplementation()
    fetch.mockImplementation((url, options) => url.endsWith('/api/rental-offers/offer-1')
      ? Promise.resolve(json({ message: status === 400 ? expected : 'Internal database detail' }, status))
      : previous(url, options))
    await userEvent.click(button)
    expect(await screen.findByRole('alert')).toHaveTextContent(expected)
    expect(screen.queryByText('Internal database detail')).not.toBeInTheDocument()
  })

  it('refreshes offer details after a completed action', async () => {
    renderPage()
    await userEvent.click(await screen.findByRole('button', { name: 'View details' }))
    await userEvent.click(await screen.findByRole('button', { name: 'Accept offer' }))
    await waitFor(() => expect(screen.queryByRole('button', { name: 'Accept offer' })).not.toBeInTheDocument())
  })
})
