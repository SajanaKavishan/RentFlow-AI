import { cleanup, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { tokenStorage } from '../../../core/auth/tokenStorage.js'
import PaymentsPage from './PaymentsPage.jsx'

const pendingId = '11111111-1111-1111-1111-111111111111'
const completedId = '22222222-2222-2222-2222-222222222222'
const failedId = '33333333-3333-3333-3333-333333333333'
const scheduleId = '44444444-4444-4444-4444-444444444444'

function payment(overrides = {}) {
  return { id: pendingId, rentScheduleItemId: scheduleId, tenantId: '55555555-5555-5555-5555-555555555555', amount: 85000, paymentMethod: 'BankTransfer', transactionReference: 'TXN-001', status: 0, paidAt: null, createdAt: '2026-09-27T10:00:00Z', updatedAt: null, ...overrides }
}

function response(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

function setupApi({ payments = [payment()], listStatus = 200, detailStatus = 200, actionStatus = 200, entry = '/modules/payments' } = {}) {
  let records = payments
  const fetchMock = vi.fn((url, options = {}) => {
    if (url.endsWith('/api/payments/landlord')) return Promise.resolve(response(listStatus === 200 ? records : { detail: 'Database stack trace' }, listStatus))
    const id = url.match(/\/api\/payments\/([^/]+)/)?.[1]
    if (options.method === 'PATCH') {
      if (actionStatus !== 200) return Promise.resolve(response({ message: 'Only pending payments can be completed.' }, actionStatus))
      const updated = { ...records.find((item) => item.id === id), status: url.endsWith('/complete') ? 1 : 2, updatedAt: '2026-09-28T10:00:00Z', paidAt: url.endsWith('/complete') ? '2026-09-28T10:00:00Z' : null }
      records = records.map((item) => item.id === id ? updated : item)
      return Promise.resolve(response(updated))
    }
    if (id) return Promise.resolve(response(detailStatus === 200 ? records.find((item) => item.id === id) : { message: 'Payment was not found.' }, detailStatus))
    return Promise.resolve(response({ message: 'Not found' }, 404))
  })
  vi.stubGlobal('fetch', fetchMock)
  tokenStorage.setToken('landlord-token')
  render(<MemoryRouter initialEntries={[entry]}><PaymentsPage /></MemoryRouter>)
  return fetchMock
}

afterEach(() => { cleanup(); vi.unstubAllGlobals(); tokenStorage.clearToken() })

describe('landlord payments', () => {
  it('opens the payment referenced by a notification and excludes Stripe manual actions', async () => {
    setupApi({ payments: [payment({ provider: 1 })], entry: `/modules/payments?paymentId=${pendingId}` })
    expect(await screen.findByRole('heading', { name: 'Payment details' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Complete payment' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Fail payment' })).not.toBeInTheDocument()
  })
  it('renders the landlord payment list', async () => {
    const fetchMock = setupApi()
    expect(await screen.findByText('BankTransfer')).toBeInTheDocument()
    expect(screen.getByText('85,000.00')).toBeInTheDocument()
    expect(screen.getByText('Pending')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining('/api/payments/landlord'), expect.objectContaining({ headers: expect.objectContaining({ Authorization: 'Bearer landlord-token' }) }))
  })

  it('shows an empty payment state', async () => {
    setupApi({ payments: [] })
    expect(await screen.findByText('No payments have been recorded for your rentals.')).toBeInTheDocument()
  })

  it('opens payment details from the discovered list', async () => {
    const fetchMock = setupApi()
    await userEvent.click(await screen.findByRole('button', { name: 'View details' }))
    expect(await screen.findByText('TXN-001')).toBeInTheDocument()
    expect(screen.getByText(scheduleId)).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining(`/api/payments/${pendingId}`), expect.any(Object))
  })

  it('shows a safe list API error', async () => {
    setupApi({ listStatus: 500 })
    expect(await screen.findByRole('alert')).toHaveTextContent('Unable to load payments.')
    expect(screen.queryByText('Database stack trace')).not.toBeInTheDocument()
  })

  it('shows a missing payment detail error', async () => {
    setupApi({ detailStatus: 404 })
    await userEvent.click(await screen.findByRole('button', { name: 'View details' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('This payment could not be found.')
  })

  it.each([
    ['complete', 'Complete payment', 'Payment completed successfully.', 1],
    ['fail', 'Mark as failed', 'Payment marked as failed.', 2],
  ])('uses the %s PATCH action and refreshes list and details', async (action, button, notice, status) => {
    const fetchMock = setupApi()
    await userEvent.click(await screen.findByRole('button', { name: 'View details' }))
    await userEvent.click(await screen.findByRole('button', { name: button }))
    expect(await screen.findByText(notice)).toBeInTheDocument()
    await waitFor(() => expect(screen.getAllByText(status === 1 ? 'Completed' : 'Failed').length).toBeGreaterThanOrEqual(2))
    expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining(`/api/payments/${pendingId}/${action}`), expect.objectContaining({ method: 'PATCH' }))
    expect(fetchMock.mock.calls.filter(([url]) => url.endsWith('/api/payments/landlord'))).toHaveLength(2)
    expect(fetchMock.mock.calls.filter(([url]) => url.endsWith(`/api/payments/${pendingId}`))).toHaveLength(2)
    expect(screen.queryByRole('button', { name: 'Complete payment' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Mark as failed' })).not.toBeInTheDocument()
  })

  it('hides actions for completed and failed payments', async () => {
    setupApi({ payments: [payment({ id: completedId, status: 1 }), payment({ id: failedId, status: 2 })] })
    const buttons = await screen.findAllByRole('button', { name: 'View details' })
    await userEvent.click(buttons[0])
    expect(await screen.findByRole('heading', { name: 'Payment details' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Complete payment' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Mark as failed' })).not.toBeInTheDocument()
    await userEvent.click(buttons[1])
    expect(await screen.findByRole('heading', { name: 'Payment details' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Complete payment' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Mark as failed' })).not.toBeInTheDocument()
  })

  it('shows a safe conflict for an action rejected by the backend', async () => {
    setupApi({ actionStatus: 409 })
    await userEvent.click(await screen.findByRole('button', { name: 'View details' }))
    await userEvent.click(await screen.findByRole('button', { name: 'Complete payment' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('can no longer be updated')
  })
})
