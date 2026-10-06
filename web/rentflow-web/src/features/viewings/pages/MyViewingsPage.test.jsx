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
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const viewing = (status, extra = {}) => ({ id: `viewing-${status}`, tenantId, propertyId, propertyTitle,
  requestedDateTime: '2026-10-01T10:00:00Z', status, landlordResponse: null, ...extra })

function renderPage(role = 'Tenant', entry = '/modules/my-viewings') {
  const session = { user: { id: tenantId, fullName: 'Taylor Example', email: 'taylor@example.com', role },
    isAuthenticated: true, isLoading: false, logout: vi.fn() }
  return render(<MemoryRouter initialEntries={[entry]}><AuthContext.Provider value={session}><App /></AuthContext.Provider></MemoryRouter>)
}

beforeEach(() => {
  tokenStorage.setToken('tenant-token')
  vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
  vi.stubGlobal('fetch', vi.fn((url) => Promise.resolve(json(url.endsWith('/api/viewings') ? [] : { unreadCount: 0 }))))
})
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('Tenant My Viewings', () => {
  it('loads only the authenticated tenant endpoint and displays real details for every status', async () => {
    fetch.mockImplementation((url) => Promise.resolve(json(url.endsWith('/api/viewings')
      ? [viewing(0), viewing(1, { landlordResponse: 'See you at 10.' }), viewing(2), viewing(3), viewing(4)]
      : { unreadCount: 0 })))
    renderPage()
    const list = await screen.findByRole('region', { name: 'Your viewing requests' })
    for (const label of ['Pending', 'Approved', 'Rejected', 'Cancelled', 'Completed']) {
      expect(within(list).getByLabelText(`Viewing status: ${label}`)).toBeInTheDocument()
    }
    expect(screen.getByText('Viewing journey')).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 1, name: 'Your requests' })).toBeInTheDocument()
    expect(within(list).getAllByText('Property')).toHaveLength(5)
    expect(within(list).getAllByText(propertyTitle)).toHaveLength(5)
    expect(within(list).queryByText(propertyId)).not.toBeInTheDocument()
    expect(within(list).queryByText('Property reference')).not.toBeInTheDocument()
    expect(within(list).getAllByText('Requested date and time')).toHaveLength(5)
    expect(within(list).getAllByText('See you at 10.')).toHaveLength(1)
    expect(within(list).getAllByText('Landlord response')).toHaveLength(1)
    expect(within(list).getAllByRole('time')).toHaveLength(5)
    expect(fetch.mock.calls.filter(([url]) => url.endsWith('/api/viewings'))).toHaveLength(1)
    for (const [url, options] of fetch.mock.calls) {
      expect(options.headers.Authorization).toBe('Bearer tenant-token')
      expect(options.method).toBeUndefined()
      expect(url).not.toContain('tenantId')
      expect(url).not.toContain('propertyId')
      expect(url).not.toContain('/api/properties')
    }
    expect(screen.queryByRole('button', { name: /Approve|Reject|Cancel|Book/ })).not.toBeInTheDocument()
  })

  it('displays each viewing property title from the response', async () => {
    const secondPropertyId = '33333333-3333-3333-3333-333333333333'
    fetch.mockImplementation((url) => Promise.resolve(json(url.endsWith('/api/viewings')
      ? [viewing(0), viewing(1, { propertyId: secondPropertyId, propertyTitle: 'Lake View Apartment' })]
      : { unreadCount: 0 })))
    renderPage()
    const list = await screen.findByRole('region', { name: 'Your viewing requests' })
    const cards = within(list).getAllByRole('heading', { name: 'Viewing request' })
      .map((heading) => heading.closest('.my-viewing-card'))
    expect(within(cards[0]).getByText(propertyTitle)).toBeInTheDocument()
    expect(within(cards[1]).getByText('Lake View Apartment')).toBeInTheDocument()
    expect(list).not.toHaveTextContent(propertyId)
    expect(list).not.toHaveTextContent(secondPropertyId)
    expect(fetch.mock.calls.some(([url]) => url.includes('/api/properties'))).toBe(false)
  })

  it.each([undefined, null, '', '   '])('handles an unavailable title (%s) without exposing the UUID', async (title) => {
    fetch.mockImplementation((url) => Promise.resolve(json(url.endsWith('/api/viewings')
      ? [viewing(1, { propertyTitle: title })] : { unreadCount: 0 })))
    renderPage()
    const list = await screen.findByRole('region', { name: 'Your viewing requests' })
    expect(within(list).getByText('Property unavailable')).toBeInTheDocument()
    expect(list).not.toHaveTextContent(propertyId)
    expect(fetch.mock.calls.some(([url]) => url.includes('/api/properties'))).toBe(false)
  })

  it('does not display a record returned for another tenant', async () => {
    fetch.mockImplementation((url) => Promise.resolve(json(url.endsWith('/api/viewings')
      ? [viewing(1, { tenantId: '99999999-9999-9999-9999-999999999999' })] : { unreadCount: 0 })))
    renderPage()
    expect(await screen.findByRole('alert')).toHaveTextContent('Your viewings could not be loaded')
    expect(screen.queryByText(propertyId)).not.toBeInTheDocument()
  })

  it('shows loading, error and retry states without a refresh button', async () => {
    let finishFirst
    let requests = 0
    fetch.mockImplementation((url) => {
      if (!url.endsWith('/api/viewings')) return Promise.resolve(json({ unreadCount: 0 }))
      requests++
      if (requests === 1) return new Promise((resolve) => { finishFirst = resolve })
      if (requests === 2) return Promise.resolve(json([viewing(1, { landlordResponse: 'Confirmed.' })]))
      return Promise.resolve(json([]))
    })
    renderPage()
    expect(screen.getByRole('status')).toHaveTextContent('Loading your viewings')
    expect(screen.queryByRole('button', { name: 'Refresh' })).not.toBeInTheDocument()
    await act(async () => { finishFirst(json({ message: 'Unavailable' }, 503)) })
    expect(await screen.findByRole('alert')).toHaveTextContent('Viewings could not be loaded')
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByText('Confirmed.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Refresh' })).not.toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    expect(requests).toBe(2)
  })

  it('handles a network failure and retries successfully', async () => {
    let requests = 0
    fetch.mockImplementation((url) => {
      if (!url.endsWith('/api/viewings')) return Promise.resolve(json({ unreadCount: 0 }))
      return ++requests === 1 ? Promise.reject(new Error('offline')) : Promise.resolve(json([]))
    })
    renderPage()
    expect(await screen.findByRole('alert')).toHaveTextContent('Unable to connect to the viewing service')
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByRole('heading', { name: 'No viewing requests yet' })).toBeInTheDocument()
  })

  it('keeps selected property context across the property-aware handoff without mutating data', async () => {
    fetch.mockImplementation((url) => Promise.resolve(json(
      url.endsWith(`/api/properties/${propertyId}`)
        ? { id: propertyId, title: 'Lake View Apartment', address: '18 Lake Road', city: 'Colombo', isAvailable: true }
        : url.endsWith('/api/viewings')
          ? [viewing(1)]
          : { unreadCount: 0 },
    )))

    renderPage('Tenant', `/modules/my-viewings?propertyId=${propertyId}`)

    expect(await screen.findByRole('heading', { name: 'Lake View Apartment' })).toBeInTheDocument()
    expect(screen.getByText('18 Lake Road, Colombo')).toBeInTheDocument()
    expect(screen.getByText(/already have a viewing request/i)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Back to property/ }))
      .toHaveAttribute('href', `/properties/${propertyId}`)
    expect(fetch.mock.calls.some(([url]) => url.endsWith(`/api/properties/${propertyId}`))).toBe(true)
    expect(fetch.mock.calls.every(([, options = {}]) => !options.method || options.method === 'GET')).toBe(true)
  })

  it('blocks non-Tenant roles from the route without loading tenant viewings', async () => {
    renderPage('Landlord')
    expect(await screen.findByRole('heading', { name: 'Not accessible' })).toBeInTheDocument()
    await waitFor(() => expect(fetch.mock.calls.some(([url]) => url.endsWith('/api/viewings'))).toBe(false))
  })
})
