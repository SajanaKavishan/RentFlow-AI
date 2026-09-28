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
const propertyId = 'property-one'
const property = { id: propertyId, title: 'Lake View Apartment', address: '10 Lake Road', city: 'Colombo' }
const applications = [0, 1, 2, 2, 3, 4, 5, 6].map((status, index) => ({
  id: `application-${index}`,
  propertyId,
  tenantId: tenant.id,
  status,
  createdAt: `2026-09-${String(index + 1).padStart(2, '0')}T10:00:00Z`,
  submittedAt: status === 0 ? null : `2026-09-${String(index + 1).padStart(2, '0')}T10:00:00Z`,
}))
const viewings = [
  { id: 'later', propertyId, tenantId: tenant.id, status: 1, requestedDateTime: '2099-03-20T10:00:00Z' },
  { id: 'next', propertyId, tenantId: tenant.id, status: 1, requestedDateTime: '2099-02-10T10:00:00Z' },
  { id: 'past', propertyId, tenantId: tenant.id, status: 1, requestedDateTime: '2000-01-01T10:00:00Z' },
  ...[0, 2, 3, 4].map((status) => ({ id: `viewing-${status}`, propertyId, tenantId: tenant.id, status, requestedDateTime: '2099-01-01T10:00:00Z' })),
  { id: 'invalid-date', propertyId, tenantId: tenant.id, status: 1, requestedDateTime: 'invalid' },
]
const notifications = {
  items: [{
    id: 'notice-1',
    title: 'Viewing approved',
    message: 'Your viewing request was approved.',
    createdAt: '2026-09-20T10:00:00Z',
    isRead: false,
    eventType: 'viewing.approved',
    relatedResourceType: 'ViewingRequest',
    relatedResourceId: 'next',
  }],
  pagination: { page: 1, totalPages: 1, totalCount: 1, hasNextPage: false, hasPreviousPage: false },
}
const lease = { id: 'lease-one', status: 1 }
const schedule = [{ id: 'schedule-one', leaseAgreementId: lease.id, dueDate: '2099-01-05', amount: 85000, status: 0 }]
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

function responseFor(url, overrides = {}) {
  const path = new URL(url, 'http://localhost').pathname
  if (path === '/api/rental-applications') return overrides.applications ?? applications
  if (path === '/api/viewings') return overrides.viewings ?? viewings
  if (path === '/api/notifications') return overrides.notifications ?? notifications
  if (path === '/api/lease-agreements/mine') return overrides.leases ?? [lease]
  if (path === `/api/rent-schedules/lease/${lease.id}`) return overrides.schedule ?? schedule
  if (path === `/api/properties/${propertyId}`) return overrides.property ?? property
  if (path === '/api/tenant/property-preferences') return overrides.matchPreferences ?? { isConfigured: false, preferredAmenities: [] }
  if (path === '/api/rental-offers/mine' || path === '/api/payments/mine') return []
  return []
}

function appWithSession(user = tenant, path = '/dashboard') {
  const session = { user, isAuthenticated: true, isLoading: false, logout: vi.fn() }
  return <MemoryRouter initialEntries={[path]}><AuthContext.Provider value={session}><App /></AuthContext.Provider></MemoryRouter>
}

const renderApp = (user, path) => render(appWithSession(user, path))

beforeEach(() => {
  tokenStorage.setToken('tenant-token')
  vi.stubGlobal('fetch', vi.fn((url) => Promise.resolve(json(responseFor(url)))))
})

afterEach(() => {
  cleanup()
  tokenStorage.clearToken()
  vi.restoreAllMocks()
  vi.unstubAllGlobals()
})

describe('tenant dashboard', () => {
  it('renders real tenant summaries, activity, payment, property and application data', async () => {
    renderApp()
    expect(screen.getByRole('heading', { name: 'Welcome, Amara Silva' })).toBeInTheDocument()

    const apps = screen.getByRole('region', { name: 'Applications' })
    const visits = screen.getByRole('region', { name: 'Upcoming Viewing summary' })
    expect(await within(apps).findByText('8')).toBeInTheDocument()
    expect(apps).toHaveTextContent('2 under review')
    expect(await within(visits).findByText('3')).toBeInTheDocument()
    expect(visits).toHaveTextContent('Awaiting approval')
    expect(visits.querySelector('time')).toHaveAttribute('dateTime', '2099-01-01T10:00:00Z')

    expect(await screen.findAllByText('Lake View Apartment')).not.toHaveLength(0)
    expect(screen.getByText('Viewing approved')).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Next Payment' })).getByText('Rs. 85,000')).toBeInTheDocument()
    expect(screen.getByRole('table')).toHaveTextContent('10 Lake Road, Colombo')

    const authenticatedPaths = [
      '/api/rental-applications', '/api/viewings', '/api/notifications',
      '/api/lease-agreements/mine', `/api/rent-schedules/lease/${lease.id}`,
    ]
    for (const [url, options] of fetch.mock.calls.filter(([url]) => authenticatedPaths.includes(new URL(url, 'http://localhost').pathname))) {
      expect(options.headers.Authorization).toBe('Bearer tenant-token')
      expect(options.method).toBeUndefined()
      expect(url).not.toContain('tenantId')
    }
  })

  it('shows truthful empty and pending states without fabricated business data', async () => {
    const overrides = { applications: [], viewings: [], notifications: { ...notifications, items: [] }, leases: [] }
    fetch.mockImplementation((url) => Promise.resolve(json(responseFor(url, overrides))))
    renderApp()

    expect(await within(screen.getByRole('region', { name: 'Applications' })).findByText('No applications yet')).toBeInTheDocument()
    expect(await within(screen.getByRole('region', { name: 'Upcoming Viewing summary' })).findByText('No upcoming viewings')).toBeInTheDocument()
    expect(screen.getByText('No payment due')).toBeInTheDocument()
    expect(screen.getByText('No recent activity')).toBeInTheDocument()
    expect(screen.getByText('No upcoming viewing scheduled')).toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Open Request' })).toHaveTextContent('Integration pending')
    expect(screen.getByRole('region', { name: 'Recommended for You' })).toHaveTextContent('Get personalized property recommendations')
    expect(screen.queryByText(/Sarah Chen|match score|\$/)).not.toBeInTheDocument()
  })

  it('keeps independent loading and failure states and retries only applications', async () => {
    let applicationAttempt = 0
    fetch.mockImplementation((url) => {
      const path = new URL(url, 'http://localhost').pathname
      if (path === '/api/rental-applications') {
        applicationAttempt += 1
        return Promise.resolve(applicationAttempt === 1 ? json({}, 500) : json(applications))
      }
      return Promise.resolve(json(responseFor(url)))
    })
    renderApp()

    const apps = screen.getByRole('region', { name: 'Applications' })
    expect(await within(apps).findByRole('alert')).toHaveTextContent('The rental application request failed.')
    expect(await within(screen.getByRole('region', { name: 'Upcoming Viewing summary' })).findByText('3')).toBeInTheDocument()
    await userEvent.click(within(apps).getByRole('button', { name: 'Retry applications' }))
    expect(await within(apps).findByText('8')).toBeInTheDocument()
    expect(fetch.mock.calls.filter(([url]) => new URL(url, 'http://localhost').pathname === '/api/viewings')).toHaveLength(1)
  })

  it('does not report failed or malformed summaries as zero', async () => {
    fetch.mockImplementation((url) => {
      const path = new URL(url, 'http://localhost').pathname
      if (path === '/api/viewings') return Promise.reject(new TypeError('offline'))
      if (path === '/api/rental-applications') return Promise.resolve(json({ items: [] }))
      return Promise.resolve(json(responseFor(url, { leases: [] })))
    })
    renderApp()

    expect(await screen.findAllByText('Unable to connect to the viewing service. Please try again.')).not.toHaveLength(0)
    expect(await screen.findAllByText('The service returned an invalid summary. Please try again.')).not.toHaveLength(0)
    expect(within(screen.getByRole('region', { name: 'Applications' })).queryByText('0')).not.toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Upcoming Viewing summary' })).queryByText('0')).not.toBeInTheDocument()
  })

  it('uses pending or approved future requests and ignores boundary, past, and completed viewings', async () => {
    vi.spyOn(Date, 'now').mockReturnValue(Date.parse('2026-09-21T12:00:00Z'))
    const candidateViewings = [
      { id: 'boundary', propertyId, tenantId: tenant.id, status: 1, requestedDateTime: '2026-09-21T12:00:00Z' },
      { id: 'pending', propertyId, tenantId: tenant.id, status: 0, requestedDateTime: '2026-09-22T12:00:00Z' },
      { id: 'approved', propertyId, tenantId: tenant.id, status: 1, requestedDateTime: '2026-09-23T12:00:00Z' },
      { id: 'completed', propertyId, tenantId: tenant.id, status: 4, requestedDateTime: '2026-09-24T12:00:00Z' },
    ]
    fetch.mockImplementation((url) => Promise.resolve(json(responseFor(url, { applications: [], viewings: candidateViewings, leases: [] }))))
    renderApp()

    const visits = screen.getByRole('region', { name: 'Upcoming Viewing summary' })
    expect(await within(visits).findByText('2')).toBeInTheDocument()
    expect(visits).toHaveTextContent('Awaiting approval')
    expect(visits.querySelector('time')).toHaveAttribute('dateTime', '2026-09-22T12:00:00Z')
  })

  it('ignores stale tenant data after the authenticated account changes', async () => {
    const pending = []
    fetch.mockImplementation((url) => {
      const path = new URL(url, 'http://localhost').pathname
      if (path === '/api/rental-applications' || path === '/api/viewings') {
        return new Promise((resolve) => pending.push({ path, resolve }))
      }
      return Promise.resolve(json(responseFor(url, { notifications: { ...notifications, items: [] }, leases: [] })))
    })
    const { rerender } = renderApp()

    const emptyOverrides = { applications: [], viewings: [], notifications: { ...notifications, items: [] }, leases: [] }
    fetch.mockImplementation((url) => Promise.resolve(json(responseFor(url, emptyOverrides))))
    rerender(appWithSession({ ...tenant, id: 'tenant-two', fullName: 'Nila Perera' }))
    expect(screen.getByRole('heading', { name: 'Welcome, Nila Perera' })).toBeInTheDocument()
    expect(await within(screen.getByRole('region', { name: 'Applications' })).findByText('No applications yet')).toBeInTheDocument()

    await act(async () => {
      pending.find((item) => item.path === '/api/rental-applications').resolve(json(applications))
      pending.find((item) => item.path === '/api/viewings').resolve(json(viewings))
    })
    expect(within(screen.getByRole('region', { name: 'Applications' })).queryByText('8')).not.toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Upcoming Viewing summary' })).queryByText('3')).not.toBeInTheDocument()
  })

  it('preserves dashboard links to applications and viewings workspaces', async () => {
    renderApp()
    const applicationsSection = screen.getByRole('region', { name: 'My Applications' })
    const applicationsLink = within(applicationsSection).getByRole('link', { name: 'View all' })
    expect(applicationsLink).toHaveAttribute('href', '/modules/my-applications')
    await userEvent.click(applicationsLink)
    expect(await screen.findByRole('heading', { name: 'My Applications' })).toBeInTheDocument()

    cleanup()
    renderApp()
    const viewingLink = await screen.findByRole('link', { name: 'View request' })
    expect(viewingLink).toHaveAttribute('href', '/modules/my-viewings')
    await userEvent.click(viewingLink)
    expect(await screen.findByRole('heading', { name: 'My Viewings' })).toBeInTheDocument()
  })

  it('keeps recommendation, property discovery, and maintenance destinations honest', async () => {
    renderApp()
    expect(within(document.querySelector('.tenant-dashboard__greeting')).queryByRole('link', { name: 'Browse properties' })).not.toBeInTheDocument()
    expect(await screen.findByRole('link', { name: 'Set match preferences' })).toHaveAttribute('href', '/modules/properties?preferences=edit')
    expect(screen.getByRole('link', { name: 'Browse properties' })).toHaveAttribute('href', '/modules/properties')
    expect(screen.getByRole('region', { name: 'Open Request' })).toHaveTextContent('Maintenance request summaries are not yet available')

    await userEvent.click(within(screen.getByRole('navigation', { name: 'Primary navigation' })).getByRole('link', { name: /Maintenance/ }))
    expect(screen.getByRole('heading', { name: 'Maintenance' })).toBeInTheDocument()
    expect(screen.getByText('Integration pending')).toBeInTheDocument()
  })

  it('shows the highest-ranked real available property recommendations', async () => {
    const recommended = {
      id: 'recommended-one',
      title: 'Garden House',
      address: '2 Lake Road',
      city: 'Kurunegala',
      monthlyRent: 120000,
      bedrooms: 3,
      bathrooms: 2,
      amenities: ['Parking'],
      isAvailable: true,
    }
    fetch.mockImplementation((url) => {
      const path = new URL(url, 'http://localhost').pathname
      if (path === '/api/tenant/property-preferences') return Promise.resolve(json({ isConfigured: true, preferredCity: 'Kurunegala', preferredAmenities: ['Parking'] }))
      if (path === '/api/properties/matches') return Promise.resolve(json({ matches: [{ propertyId: recommended.id, matchScore: 92, matchReasons: ['Preferred city matches.'] }] }))
      if (path === '/api/properties') return Promise.resolve(json([recommended]))
      if (path === `/api/properties/${recommended.id}/images`) return Promise.resolve(json([]))
      return Promise.resolve(json(responseFor(url)))
    })
    renderApp()

    const recommendations = screen.getByRole('region', { name: 'Recommended for You' })
    expect(await within(recommendations).findByRole('heading', { name: 'Garden House' })).toBeInTheDocument()
    expect(within(recommendations).getByLabelText('92 percent match')).toBeInTheDocument()
    expect(within(recommendations).getByText('Rs. 120,000/month')).toBeInTheDocument()
    expect(within(recommendations).getByRole('link', { name: /View property/ })).toHaveAttribute('href', '/properties/recommended-one')
  })

  it.each(['Landlord', 'Admin', 'MaintenanceTechnician'])('does not call tenant dashboard APIs for %s', async (role) => {
    fetch.mockImplementation((url) => {
      const path = new URL(url, 'http://localhost').pathname
      if (path === '/api/admin/users') return Promise.resolve(json({
        items: [], pagination: { page: 1, pageSize: 1, totalCount: 0, totalPages: 0, hasNextPage: false, hasPreviousPage: false },
      }))
      return Promise.resolve(json([]))
    })
    renderApp({ ...tenant, role })
    await act(async () => {})
    const requestedPaths = fetch.mock.calls.map(([url]) => new URL(url, 'http://localhost').pathname)
    expect(requestedPaths).not.toContain('/api/rental-applications')
    expect(requestedPaths).not.toContain('/api/viewings')
    expect(requestedPaths).not.toContain('/api/lease-agreements/mine')
    expect(requestedPaths).not.toContain('/api/notifications')
  })

  it('uses the existing session expiry handling when a dashboard source returns 401', async () => {
    fetch.mockImplementation(() => Promise.resolve(json({}, 401)))
    const api = { getCurrentUser: vi.fn().mockResolvedValue(tenant) }
    render(<MemoryRouter initialEntries={['/dashboard']}><AuthProvider api={api}><App /></AuthProvider></MemoryRouter>)
    expect(await screen.findByRole('heading', { name: 'Sign in to RentFlow' })).toBeInTheDocument()
    expect(tokenStorage.getToken()).toBeNull()
  })
})
