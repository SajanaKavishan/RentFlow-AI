import { act, cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../../App.jsx'
import { AuthContext } from '../../auth/useAuth.js'
import { tokenStorage } from '../../../core/auth/tokenStorage.js'

const tenantId = '11111111-1111-1111-1111-111111111111'
const propertyId = '22222222-2222-2222-2222-222222222222'
const propertyTitle = 'Port city residence'
const firstId = '33333333-3333-3333-3333-333333333333'
const secondId = '44444444-4444-4444-4444-444444444444'
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const application = (id, status, extra = {}) => ({
  id, tenantId, propertyId, propertyTitle, status, createdAt: '2026-09-01T12:00:00Z', submittedAt: null,
  landlordResponse: null, ...extra,
})

function renderPage(role = 'Tenant', entry = '/modules/my-applications') {
  const session = { user: { id: tenantId, fullName: 'Taylor Example', email: 'taylor@example.com', role },
    isAuthenticated: true, isLoading: false, logout: vi.fn() }
  return render(<MemoryRouter initialEntries={[entry]}><AuthContext.Provider value={session}><App /></AuthContext.Provider></MemoryRouter>)
}

beforeEach(() => {
  tokenStorage.setToken('tenant-token')
  vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
  vi.stubGlobal('fetch', vi.fn((url) => Promise.resolve(json(url.endsWith('/api/rental-applications') ? [] : { unreadCount: 0 }))))
})
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('Tenant My Applications', () => {
  it('shows real property titles, statuses, dates and feedback in newest first order with authorized detail links', async () => {
    fetch.mockImplementation((url) => Promise.resolve(json(url.endsWith(`/api/rental-applications/${secondId}`)
      ? application(secondId, 3, { submittedAt: '2026-09-15T09:00:00Z', landlordResponse: 'Please add proof of income.' })
      : url.endsWith('/api/rental-applications') ? [
      application(firstId, 0, { propertyId: '55555555-5555-5555-5555-555555555555', propertyTitle: 'Lake View Apartment' }),
      application(secondId, 3, { submittedAt: '2026-09-15T09:00:00Z', landlordResponse: 'Please add proof of income.' }),
    ] : { unreadCount: 0 })))
    renderPage()
    const list = await screen.findByRole('region', { name: 'Your rental applications' })
    const cards = list.querySelectorAll('.my-application-card')
    expect(cards[0]).toHaveTextContent('Please add proof of income.')
    expect(within(cards[0]).getByRole('heading', { name: propertyTitle })).toBeInTheDocument()
    expect(list).not.toHaveTextContent(propertyId)
    expect(within(list).getAllByText('Property')).toHaveLength(2)
    expect(within(list).queryByText('Property reference')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Refresh' })).not.toBeInTheDocument()
    expect(within(cards[0]).getByLabelText('Application status: Changes requested')).toBeInTheDocument()
    expect(within(cards[0]).getByText('Landlord feedback')).toBeInTheDocument()
    expect(within(cards[0]).getByRole('time')).toHaveAttribute('dateTime', '2026-09-15T09:00:00Z')
    expect(within(cards[0]).getByRole('link', { name: 'View application' })).toHaveAttribute('href', `/notifications/rental-application/${secondId}`)
    expect(within(cards[1]).getByLabelText('Application status: Draft')).toBeInTheDocument()
    expect(within(cards[1]).getByRole('heading', { name: 'Lake View Apartment' })).toBeInTheDocument()
    expect(list).not.toHaveTextContent('55555555-5555-5555-5555-555555555555')
    expect(within(cards[1]).getByText('Not submitted')).toBeInTheDocument()
    expect(within(cards[1]).queryByText('Landlord feedback')).not.toBeInTheDocument()
    expect(fetch.mock.calls.filter(([url]) => url.endsWith('/api/rental-applications'))).toHaveLength(1)
    for (const [url, options] of fetch.mock.calls) {
      expect(options.headers.Authorization).toBe('Bearer tenant-token')
      expect(options.method).toBeUndefined()
      expect(url).not.toContain('tenantId')
      expect(url).not.toContain('/api/properties')
    }
    expect(screen.queryByRole('button', { name: /Create|Edit|Submit|Upload|Resubmit/ })).not.toBeInTheDocument()

    await userEvent.click(within(cards[0]).getByRole('link', { name: 'View application' }))
    expect(await screen.findByRole('heading', { name: 'Rental application' })).toBeInTheDocument()
    expect(await screen.findByText('Please add proof of income.')).toBeInTheDocument()
    await waitFor(() => expect(fetch.mock.calls.some(([url]) => url.endsWith(`/api/rental-applications/${secondId}`))).toBe(true))
  })

  it('filters by supported status and shows a filtered empty state', async () => {
    fetch.mockImplementation((url) => Promise.resolve(json(url.endsWith('/api/rental-applications')
      ? [application(firstId, 0), application(secondId, 3)] : { unreadCount: 0 })))
    renderPage()
    const filter = await screen.findByRole('combobox', { name: 'Status' })
    await userEvent.selectOptions(filter, '3')
    expect(within(screen.getByRole('region', { name: 'Your rental applications' })).getAllByRole('link', { name: 'View application' })).toHaveLength(1)
    await userEvent.selectOptions(filter, '4')
    expect(screen.getByRole('heading', { name: 'No applications with this status' })).toBeInTheDocument()
    await userEvent.selectOptions(filter, 'all')
    expect(within(screen.getByRole('region', { name: 'Your rental applications' })).getAllByRole('link', { name: 'View application' })).toHaveLength(2)
  })

  it('shows loading, error and retry states without a refresh button', async () => {
    let finishFirst
    let requests = 0
    fetch.mockImplementation((url) => {
      if (!url.endsWith('/api/rental-applications')) return Promise.resolve(json({ unreadCount: 0 }))
      requests++
      if (requests === 1) return new Promise((resolve) => { finishFirst = resolve })
      if (requests === 2) return Promise.resolve(json([application(firstId, 1, { submittedAt: '2026-09-12T10:00:00Z' })]))
      return Promise.resolve(json([]))
    })
    renderPage()
    expect(screen.getByRole('status')).toHaveTextContent('Loading your applications')
    expect(screen.queryByRole('button', { name: 'Refresh' })).not.toBeInTheDocument()
    await act(async () => { finishFirst(json({ message: 'Unavailable' }, 503)) })
    expect(await screen.findByRole('alert')).toHaveTextContent('Applications could not be loaded')
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByRole('region', { name: 'Your rental applications' })).toHaveTextContent(propertyTitle)
    expect(screen.queryByRole('button', { name: 'Refresh' })).not.toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    expect(requests).toBe(2)
  })

  it.each([undefined, null, '', '   '])('handles an unavailable title (%s) without exposing the UUID', async (title) => {
    fetch.mockImplementation((url) => Promise.resolve(json(url.endsWith('/api/rental-applications')
      ? [application(firstId, 1, { propertyTitle: title })] : { unreadCount: 0 })))
    renderPage()
    const list = await screen.findByRole('region', { name: 'Your rental applications' })
    expect(within(list).getByRole('heading', { name: 'Property unavailable' })).toBeInTheDocument()
    expect(list).not.toHaveTextContent(propertyId)
    expect(fetch.mock.calls.some(([url]) => url.includes('/api/properties'))).toBe(false)
  })

  it('shows the empty state without a refresh button', async () => {
    renderPage()
    expect(await screen.findByRole('heading', { name: 'No applications yet' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Refresh' })).not.toBeInTheDocument()
  })

  it('keeps selected property context across the property-aware handoff without creating an application', async () => {
    fetch.mockImplementation((url) => Promise.resolve(json(
      url.endsWith(`/api/properties/${propertyId}`)
        ? { id: propertyId, title: 'Lake View Apartment', address: '18 Lake Road', city: 'Colombo', isAvailable: false }
        : url.endsWith('/rental-application-eligibility')
          ? { canApply: false, hasCompletedViewing: true, existingApplicationId: firstId, existingApplicationStatus: 2 }
        : url.endsWith('/api/rental-applications')
          ? [application(firstId, 2, { submittedAt: '2026-09-12T10:00:00Z' })]
          : { unreadCount: 0 },
    )))

    renderPage('Tenant', `/modules/my-applications?propertyId=${propertyId}`)

    expect(await screen.findByRole('heading', { name: 'Lake View Apartment' })).toBeInTheDocument()
    expect(screen.getByText('18 Lake Road, Colombo')).toBeInTheDocument()
    expect(await screen.findByText(/Your existing application remains available/i)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Back to property/ }))
      .toHaveAttribute('href', `/properties/${propertyId}`)
    expect(fetch.mock.calls.some(([url]) => url.endsWith(`/api/properties/${propertyId}`))).toBe(true)
    expect(fetch.mock.calls.every(([, options = {}]) => !options.method || options.method === 'GET')).toBe(true)
  })

  it('rejects another tenant record and blocks non-tenant roles', async () => {
    fetch.mockImplementation((url) => Promise.resolve(json(url.endsWith('/api/rental-applications')
      ? [application(firstId, 1, { tenantId: '99999999-9999-9999-9999-999999999999' })] : { unreadCount: 0 })))
    renderPage()
    expect(await screen.findByRole('alert')).toHaveTextContent('Applications could not be loaded')
    expect(screen.queryByText(propertyId)).not.toBeInTheDocument()
    cleanup()
    fetch.mockClear()
    renderPage('Landlord')
    expect(await screen.findByRole('heading', { name: 'Not accessible' })).toBeInTheDocument()
    expect(fetch.mock.calls.some(([url]) => url.endsWith('/api/rental-applications'))).toBe(false)
  })
})
