import { act, cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { AuthProvider } from '../../features/auth/AuthContext.jsx'
import { AuthContext } from '../../features/auth/useAuth.js'
import { tokenStorage } from '../../core/auth/tokenStorage.js'

vi.mock('../../features/notifications/notificationsApi.js', async (importOriginal) => ({
  ...(await importOriginal()), getUnreadCount: vi.fn().mockResolvedValue(0),
}))

const tenant = { id: 'tenant-one', fullName: 'Amara Silva', email: 'amara@example.com', phoneNumber: '', role: 'Tenant' }
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const applications = [0, 1, 2, 2, 3, 4, 5, 6].map((status, index) => ({ id: `application-${index}`, status }))
const viewings = [
  { id: 'later', status: 1, requestedDateTime: '2099-03-20T10:00:00Z' },
  { id: 'next', status: 1, requestedDateTime: '2099-02-10T10:00:00Z' },
  { id: 'past', status: 1, requestedDateTime: '2000-01-01T10:00:00Z' },
  ...[0, 2, 3, 4].map((status) => ({ id: `viewing-${status}`, status, requestedDateTime: '2099-01-01T10:00:00Z' })),
  { id: 'invalid-date', status: 1, requestedDateTime: 'invalid' },
]

function appWithSession(user = tenant, path = '/dashboard') {
  const session = { user, isAuthenticated: true, isLoading: false, logout: vi.fn() }
  return <MemoryRouter initialEntries={[path]}><AuthContext.Provider value={session}><App /></AuthContext.Provider></MemoryRouter>
}

const renderApp = (user, path) => render(appWithSession(user, path))

beforeEach(() => {
  tokenStorage.setToken('tenant-token')
  vi.stubGlobal('fetch', vi.fn().mockImplementation((url) => Promise.resolve(json(url.endsWith('/api/viewings') ? viewings : applications))))
})
afterEach(() => { cleanup(); vi.unstubAllGlobals() })

describe('tenant dashboard', () => {
  it('uses the session name and authenticated tenant endpoints to summarize actual records', async () => {
    renderApp()
    expect(screen.getByRole('heading', { name: 'Welcome, Amara Silva' })).toBeInTheDocument()
    const apps = screen.getByRole('region', { name: 'Applications' })
    const visits = screen.getByRole('region', { name: 'Upcoming viewings' })
    expect(await within(apps).findByText('8')).toBeInTheDocument()
    expect(apps).toHaveTextContent('2 under review')
    expect(apps).toHaveTextContent('1 requesting changes')
    expect(await within(visits).findByText('2')).toBeInTheDocument()
    expect(visits).toHaveTextContent('1 awaiting confirmation')
    expect(visits.querySelector('time')).toHaveAttribute('dateTime', '2099-02-10T10:00:00Z')
    expect(fetch).toHaveBeenCalledTimes(2)
    expect(fetch.mock.calls.map(([url]) => new URL(url, 'http://localhost').pathname).sort()).toEqual(['/api/rental-applications', '/api/viewings'])
    for (const [url, options] of fetch.mock.calls) {
      expect(options.headers.Authorization).toBe('Bearer tenant-token')
      expect(options.method).toBeUndefined()
      expect(url).not.toContain('tenantId')
    }
  })

  it('keeps loading distinct from a successful empty account', async () => {
    let finish
    fetch.mockImplementation(() => new Promise((resolve) => { finish = resolve }))
    renderApp()
    expect(screen.getAllByText('Loading summary…')).toHaveLength(2)
    expect(screen.queryByText('0')).not.toBeInTheDocument()
    // Only the viewing request resolves; applications remain independently busy.
    await act(async () => { finish(json([])) })
    expect(screen.getByText('No viewings yet.')).toBeInTheDocument()
    expect(screen.getAllByText('Loading summary…')).toHaveLength(1)
  })

  it('shows empty summaries without fabricated property, payment or activity data', async () => {
    fetch.mockImplementation(() => Promise.resolve(json([])))
    renderApp()
    expect(await screen.findByText('No applications yet.')).toBeInTheDocument()
    expect(await screen.findByText('No viewings yet.')).toBeInTheDocument()
    expect(screen.getAllByText('Integration pending')).toHaveLength(2)
    expect(screen.getByRole('link', { name: /Open Lease & Payments/ })).toHaveAttribute('href', '/modules/lease-payments')
    expect(screen.queryByText(/\$|match score|Recent Activity|Sarah Chen/)).not.toBeInTheDocument()
  })

  it('preserves a successful viewing summary when applications fail and retries only the failed request', async () => {
    let appAttempts = 0
    fetch.mockImplementation((url) => Promise.resolve(url.endsWith('/api/viewings') ? json(viewings) : ++appAttempts === 1 ? json({}, 500) : json(applications)))
    renderApp()
    expect(await screen.findByRole('alert')).toHaveTextContent('The rental application request failed.')
    expect(within(screen.getByRole('region', { name: 'Applications' })).queryByText('0')).not.toBeInTheDocument()
    expect(screen.getByText('Next confirmed viewing')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Retry applications' }))
    expect(await screen.findByText('8')).toBeInTheDocument()
    expect(fetch.mock.calls.filter(([url]) => url.endsWith('/api/viewings'))).toHaveLength(1)
  })

  it('handles viewing failures and malformed application responses without reporting zero', async () => {
    fetch.mockImplementation((url) => url.endsWith('/api/viewings') ? Promise.reject(new TypeError('offline')) : Promise.resolve(json({ items: [] })))
    renderApp()
    expect(await screen.findByText('Unable to connect to the viewing service. Please try again.')).toBeInTheDocument()
    expect(await screen.findByText('The service returned an invalid summary. Please try again.')).toBeInTheDocument()
    expect(screen.queryByText('0')).not.toBeInTheDocument()
  })

  it('does not show another tenant’s records when an old request finishes after an account change', async () => {
    const finishOldRequests = []
    fetch.mockImplementation(() => new Promise((resolve) => { finishOldRequests.push(resolve) }))
    const { rerender } = renderApp()
    fetch.mockImplementation(() => Promise.resolve(json([])))
    rerender(appWithSession({ ...tenant, id: 'tenant-two', fullName: 'Nila Perera' }))
    expect(screen.getByRole('heading', { name: 'Welcome, Nila Perera' })).toBeInTheDocument()
    expect(await screen.findByText('No applications yet.')).toBeInTheDocument()
    await act(async () => {
      finishOldRequests[0](json(applications))
      finishOldRequests[1](json(viewings))
    })
    expect(screen.getByText('No applications yet.')).toBeInTheDocument()
    expect(screen.getByText('No viewings yet.')).toBeInTheDocument()
    expect(screen.queryByText('8')).not.toBeInTheDocument()
    expect(screen.queryByText('Next confirmed viewing')).not.toBeInTheDocument()
  })

  it('does not treat pending, past or completed appointments as upcoming confirmed viewings', async () => {
    vi.spyOn(Date, 'now').mockReturnValue(Date.parse('2026-09-21T12:00:00Z'))
    fetch.mockImplementation((url) => Promise.resolve(json(url.endsWith('/api/viewings') ? [
      { id: 'boundary', status: 1, requestedDateTime: '2026-09-21T12:00:00Z' },
      { id: 'pending', status: 0, requestedDateTime: '2026-09-22T12:00:00Z' },
      { id: 'completed', status: 4, requestedDateTime: '2026-09-22T12:00:00Z' },
    ] : [])))
    renderApp()
    const visits = screen.getByRole('region', { name: 'Upcoming viewings' })
    expect(await within(visits).findByText('0')).toBeInTheDocument()
    expect(visits).toHaveTextContent('No upcoming confirmed viewings.')
    expect(visits).toHaveTextContent('1 awaiting confirmation')
    expect(visits.querySelector('time')).toBeNull()
  })

  it('opens My Applications from the dashboard quick action', async () => {
    fetch.mockImplementation(() => Promise.resolve(json([])))
    renderApp()
    const actions = screen.getByRole('region', { name: 'Quick actions' })
    const link = within(actions).getByRole('link', { name: /My Applications/ })
    expect(link).toHaveAttribute('href', '/modules/my-applications')
    expect(link).toHaveTextContent('Open your workspace')
    await userEvent.click(link)
    expect(await screen.findByRole('heading', { name: 'No applications yet' })).toBeInTheDocument()
    const sidebarLink = within(screen.getByRole('navigation', { name: 'Primary navigation' })).getByRole('link', { name: 'My Applications' })
    expect(sidebarLink).toHaveAttribute('href', '/modules/my-applications')
    expect(sidebarLink).not.toHaveTextContent('Soon')
  })

  it('opens My Applications from the tenant sidebar', async () => {
    fetch.mockImplementation(() => Promise.resolve(json([])))
    renderApp()
    const sidebarLink = within(screen.getByRole('navigation', { name: 'Primary navigation' })).getByRole('link', { name: 'My Applications' })
    expect(sidebarLink).not.toHaveTextContent('Soon')
    await userEvent.click(sidebarLink)
    expect(await screen.findByRole('heading', { name: 'No applications yet' })).toBeInTheDocument()
  })

  it('opens the available read-only My Viewings page from the dashboard', async () => {
    fetch.mockImplementation(() => Promise.resolve(json([])))
    renderApp()
    const actions = screen.getByRole('region', { name: 'Quick actions' })
    const link = within(actions).getByRole('link', { name: /My Viewings/ })
    expect(link).toHaveAttribute('href', '/modules/my-viewings')
    expect(link).toHaveTextContent('Open your workspace')
    await userEvent.click(link)
    expect(await screen.findByRole('heading', { name: 'No viewing requests yet' })).toBeInTheDocument()
    const sidebarLink = within(screen.getByRole('navigation', { name: 'Primary navigation' })).getByRole('link', { name: 'My Viewings' })
    expect(sidebarLink).not.toHaveTextContent('Soon')
  })

  it('opens the tenant lease and payments workspace from the sidebar', async () => {
    renderApp()
    await userEvent.click(within(screen.getByRole('navigation', { name: 'Primary navigation' })).getByRole('link', { name: 'Lease & Payments' }))
    expect(screen.getByRole('heading', { name: 'Lease & Payments' })).toBeInTheDocument()
    expect(screen.getByRole('navigation', { name: 'Lease and payment sections' })).toBeInTheDocument()
  })

  it('keeps the maintenance destination pending', async () => {
    renderApp()
    await userEvent.click(within(screen.getByRole('navigation', { name: 'Primary navigation' })).getByRole('link', { name: /Maintenance/ }))
    expect(screen.getByRole('heading', { name: 'Maintenance' })).toBeInTheDocument()
    expect(screen.getByText('Integration pending')).toBeInTheDocument()
  })

  it.each(['Landlord', 'Admin', 'MaintenanceTechnician'])('does not call tenant APIs for %s', async (role) => {
    if (role === 'Admin') {
      fetch.mockResolvedValue(json({
        items: [],
        pagination: {
          page: 1, pageSize: 1, totalCount: 0, totalPages: 0,
          hasNextPage: false, hasPreviousPage: false,
        },
      }))
    }
    renderApp({ ...tenant, role })
    expect(screen.getByRole('heading', { name: role === 'Admin' ? 'System Overview' : 'Welcome, Amara Silva' })).toBeInTheDocument()
    await act(async () => {})
    const requestedPaths = fetch.mock.calls.map(([url]) => new URL(url, 'http://localhost').pathname)
    expect(requestedPaths).not.toContain('/api/rental-applications')
    expect(requestedPaths).not.toContain('/api/viewings')
    expect(requestedPaths).toEqual(role === 'Admin' ? Array(5).fill('/api/admin/users') : [])
    if (role === 'Admin') {
      const roleFilters = fetch.mock.calls
        .map(([url]) => new URL(url, 'http://localhost').searchParams.get('role'))
        .filter(Boolean)
        .sort()
      expect(roleFilters).toEqual(['Admin', 'Landlord', 'MaintenanceTechnician', 'Tenant'])
    }
  })

  it('uses the existing session expiry handling when a summary returns 401', async () => {
    fetch.mockImplementation(() => Promise.resolve(json({}, 401)))
    const api = { getCurrentUser: vi.fn().mockResolvedValue(tenant) }
    render(<MemoryRouter initialEntries={['/dashboard']}><AuthProvider api={api}><App /></AuthProvider></MemoryRouter>)
    expect(await screen.findByRole('heading', { name: 'Sign in to RentFlow' })).toBeInTheDocument()
    expect(tokenStorage.getToken()).toBeNull()
  })
})
