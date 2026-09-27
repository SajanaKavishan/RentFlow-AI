import { act, cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter, RouterProvider } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { tokenStorage } from '../../core/auth/tokenStorage.js'

vi.mock('../../features/notifications/notificationsApi.js', async (importOriginal) => ({
  ...(await importOriginal()), getUnreadCount: vi.fn().mockResolvedValue(0),
}))
import { AuthProvider } from '../../features/auth/AuthContext.jsx'
import { AuthContext } from '../../features/auth/useAuth.js'
import { getApplicationValidationRuns } from '../../features/rentalApplications/services/applicationValidationApiService.js'
import { getMyProperties } from '../../features/properties/services/propertyApiService.js'

vi.mock('../../features/rentalApplications/services/applicationValidationApiService.js', async (importOriginal) => ({
  ...(await importOriginal()), getApplicationValidationRuns: vi.fn(),
}))

vi.mock('../../features/properties/services/propertyApiService.js', async (importOriginal) => ({
  ...(await importOriginal()), getMyProperties: vi.fn(),
}))

const propertyId = '88888888-8888-8888-8888-888888888888'
const otherPropertyId = '99999999-9999-9999-9999-999999999999'
const landlord = { id: 'landlord-one', fullName: 'Nila Perera', email: 'nila@example.com', phoneNumber: '', role: 'Landlord' }
const ownedProperty = {
  id: propertyId,
  landlordId: landlord.id,
  title: 'Lake View Apartment',
  description: 'Owned property',
  address: '12 Lake Road',
  city: 'Colombo',
  monthlyRent: 120000,
  bedrooms: 2,
  bathrooms: 2,
  isAvailable: true,
  amenities: [],
}
const otherOwnedProperty = {
  ...ownedProperty,
  id: otherPropertyId,
  title: 'Garden House',
  address: '44 Green Lane',
  monthlyRent: 180000,
  isAvailable: false,
}
const viewings = [0, 0, 1, 2, 3, 4].map((status, index) => ({ id: `viewing-${index}`, propertyId, status }))
const applications = [0, 1, 1, 2, 3, 4, 5, 6].map((status, index) => ({
  id: `application-${index}`,
  tenantId: `tenant-${index}-reference`,
  propertyId,
  monthlyIncome: 75000 + (index * 5000),
  createdAt: `2026-09-${String(index + 1).padStart(2, '0')}T12:00:00Z`,
  status,
}))
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const scopedDashboard = (id = propertyId) => `/dashboard?propertyId=${id}`
const isViewing = (url) => url.includes('/api/viewings/property/')

function renderApp(entry = scopedDashboard(), user = landlord) {
  const router = createMemoryRouter([{ path: '*', element: <App /> }], { initialEntries: [entry] })
  const tree = (account) => (
    <AuthContext.Provider value={{ user: account, isAuthenticated: true, isLoading: false, logout: vi.fn() }}>
      <RouterProvider router={router} />
    </AuthContext.Provider>
  )
  const result = render(tree(user))
  return { router, changeUser: (account) => result.rerender(tree(account)) }
}

beforeEach(() => {
  tokenStorage.setToken('landlord-token')
  getMyProperties.mockReset().mockResolvedValue([ownedProperty, otherOwnedProperty])
  getApplicationValidationRuns.mockReset().mockResolvedValue([])
  vi.stubGlobal('fetch', vi.fn((url) => Promise.resolve(json(isViewing(url) ? viewings : applications))))
})

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

describe('landlord dashboard redesign', () => {
  it('uses the requested welcome copy, compact property selector, and quick actions', async () => {
    renderApp()

    expect(screen.getByRole('heading', { name: 'Welcome, Nila' })).toBeInTheDocument()
    expect(screen.getByText('Manage your properties, review tenant activity, and keep your rental workflow moving.')).toBeInTheDocument()
    expect(await screen.findByRole('combobox', { name: 'Currently viewing' })).toHaveValue(propertyId)
    expect(screen.getByText('Choose one of your properties to review its current activity.')).toBeInTheDocument()

    const actions = screen.getByRole('navigation', { name: 'Quick actions' })
    expect(within(actions).getByRole('link', { name: 'Manage Properties' })).toHaveAttribute('href', '/modules/manage-properties')
    expect(within(actions).getByRole('link', { name: 'Viewing Requests' })).toHaveAttribute('href', `/viewing-requests?propertyId=${propertyId}`)
    expect(within(actions).getByRole('link', { name: 'Rental Applications' })).toHaveAttribute('href', `/rental-applications?propertyId=${propertyId}`)
    expect(within(actions).getByRole('link', { name: 'AI Review' })).toHaveAttribute('href', `/ai-review?propertyId=${propertyId}`)
  })

  it('shows truthful summary cards and integration-pending revenue copy', async () => {
    renderApp()
    const active = screen.getByRole('region', { name: 'Active Properties' })
    const viewing = screen.getByRole('region', { name: 'Pending Viewings' })
    const application = screen.getByRole('region', { name: 'Applications' })

    expect(await within(viewing).findByText('2')).toBeInTheDocument()
    expect(within(viewing).getByText('For Lake View Apartment')).toBeInTheDocument()
    expect(await within(application).findByText('8')).toBeInTheDocument()
    expect(within(application).getByText('3 awaiting review')).toBeInTheDocument()
    expect(await within(active).findByText('1')).toBeInTheDocument()
    expect(within(active).getByText('2 total properties')).toBeInTheDocument()

    const revenue = screen.getByRole('region', { name: 'Revenue This Month' })
    expect(within(revenue).getByText('Integration pending')).toBeInTheDocument()
    expect(within(revenue).getByText('Revenue data will appear when the Payments and Lease module is connected.')).toBeInTheDocument()
    expect(within(revenue).queryByText(/Rs\.|last month|%/i)).not.toBeInTheDocument()
  })

  it('derives only real availability and rent metrics for the portfolio', async () => {
    renderApp()
    const portfolio = screen.getByRole('region', { name: 'Portfolio Overview' })

    await waitFor(() => expect(portfolio).toHaveTextContent('Available properties1 / 2'))
    expect(portfolio).toHaveTextContent('Unavailable properties1 / 2')
    expect(portfolio).toHaveTextContent('Average monthly rentRs. 150,000')
    expect(portfolio).not.toHaveTextContent(/occupied|occupancy/i)
  })

  it('omits average rent unless all owned-property rent values are usable', async () => {
    getMyProperties.mockResolvedValue([{ ...ownedProperty, monthlyRent: null }, otherOwnedProperty])
    renderApp()
    const portfolio = screen.getByRole('region', { name: 'Portfolio Overview' })
    await waitFor(() => expect(portfolio).toHaveTextContent('Available properties1 / 2'))
    expect(within(portfolio).queryByText('Average monthly rent')).not.toBeInTheDocument()
  })

  it('keeps maintenance honest without invented requests or an unavailable route action', () => {
    renderApp()
    const maintenance = screen.getByRole('region', { name: 'Maintenance' })
    expect(within(maintenance).getByText('Integration pending')).toBeInTheDocument()
    expect(within(maintenance).getByText('Maintenance activity will appear here when the Maintenance module is connected.')).toBeInTheDocument()
    expect(within(maintenance).queryByRole('link')).not.toBeInTheDocument()
    expect(within(maintenance).queryByText(/urgent|scheduled|plumbing/i)).not.toBeInTheDocument()
  })

  it('shows only real, selected-property actions in Needs Attention', async () => {
    renderApp()
    const attention = screen.getByRole('region', { name: 'Needs Attention' })

    expect(await within(attention).findByText('3 applications awaiting review')).toBeInTheDocument()
    expect(within(attention).getByText('Review submitted applications for Lake View Apartment.')).toBeInTheDocument()
    expect(within(attention).getByText('2 viewing requests pending approval')).toBeInTheDocument()
    expect(within(attention).getByText('Respond to requested viewing appointments.')).toBeInTheDocument()
    const reviewLinks = within(attention).getAllByRole('link', { name: 'Review' })
    expect(reviewLinks.map((link) => link.getAttribute('href'))).toEqual([
      `/rental-applications?propertyId=${propertyId}`,
      `/viewing-requests?propertyId=${propertyId}`,
    ])
    expect(within(attention).queryByRole('link', { name: /approve|reject/i })).not.toBeInTheDocument()
  })

  it('shows the caught-up state when the selected property has no urgent actions', async () => {
    fetch.mockImplementation((url) => Promise.resolve(json(isViewing(url)
      ? viewings.filter((item) => item.status !== 0)
      : applications.filter((item) => ![1, 2].includes(item.status)))))
    renderApp()
    const attention = screen.getByRole('region', { name: 'Needs Attention' })

    expect(await within(attention).findByText("You're all caught up")).toBeInTheDocument()
    expect(within(attention).getByText('No urgent landlord actions for this property right now.')).toBeInTheDocument()
    expect(getApplicationValidationRuns).not.toHaveBeenCalled()
  })

  it('renders recent applications with real property, income, status, and tenant references', async () => {
    const records = applications.map((application, index) => index === 7
      ? { ...application, applicantName: 'Ayesha Fernando' }
      : application)
    fetch.mockImplementation((url) => Promise.resolve(json(isViewing(url) ? [] : records)))
    renderApp()
    const recent = screen.getByRole('region', { name: 'Recent Applications' })

    expect(await within(recent).findByText('Showing applications for Lake View Apartment')).toBeInTheDocument()
    const rows = (await within(recent).findAllByRole('row')).slice(1)
    expect(rows).toHaveLength(5)
    expect(within(rows[0]).getByText('Ayesha Fernando')).toBeInTheDocument()
    expect(within(rows[0]).getByText('Rs. 110,000')).toBeInTheDocument()
    expect(within(rows[0]).getByLabelText('Application status: Withdrawn')).toBeInTheDocument()
    expect(within(rows[1]).getByText('Tenant tenant6r')).toBeInTheDocument()
    expect(rows.every((row) => within(row).getByText('Lake View Apartment'))).toBe(true)
    expect(within(rows[0]).getByRole('link', { name: 'Review application application-7' })).toHaveAttribute(
      'href',
      `/notifications/rental-application/application-7?propertyId=${propertyId}`,
    )
  })

  it('shows AI review actions only for confirmed human-review workflows', async () => {
    getApplicationValidationRuns.mockImplementation((id) => Promise.resolve(id === 'application-3'
      ? [{ id: 'run-three', applicationId: id, status: 2 }]
      : []))
    renderApp()
    const attention = screen.getByRole('region', { name: 'Needs Attention' })

    expect(await within(attention).findByText('AI validation requires human review')).toBeInTheDocument()
    expect(within(attention).getByRole('link', { name: 'Open AI Review' })).toHaveAttribute('href', `/ai-review?propertyId=${propertyId}`)
    const recent = screen.getByRole('region', { name: 'Recent Applications' })
    expect(within(recent).getByRole('link', { name: 'AI Review application application-3' })).toHaveAttribute(
      'href',
      `/rental-applications/application-3/validation?propertyId=${propertyId}`,
    )
  })

  it.each(['/dashboard', '/dashboard?propertyId=invalid'])('shows selection-required states at %s without scoped requests', async (entry) => {
    renderApp(entry)
    expect(await screen.findByRole('combobox', { name: 'Currently viewing' })).toHaveValue('')
    expect(screen.getAllByText('Select a property').length).toBeGreaterThanOrEqual(3)
    expect(screen.getAllByText('Choose one of your properties above to view applications and landlord activity.')).toHaveLength(2)

    const viewing = screen.getByRole('region', { name: 'Pending Viewings' })
    const application = screen.getByRole('region', { name: 'Applications' })
    expect(within(viewing).getByText('Choose a property to view pending requests.')).toBeInTheDocument()
    expect(within(application).getByText('Choose a property to review applications.')).toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
    expect(getApplicationValidationRuns).not.toHaveBeenCalled()
  })

  it('changes the selected property from the dashboard selector and reloads only scoped endpoints', async () => {
    fetch.mockImplementation(() => Promise.resolve(json([])))
    const { router } = renderApp()
    const selector = await screen.findByRole('combobox', { name: 'Currently viewing' })
    await userEvent.selectOptions(selector, otherPropertyId)

    expect(router.state.location.pathname).toBe('/dashboard')
    expect(router.state.location.search).toBe(`?propertyId=${otherPropertyId}`)
    expect(await within(screen.getByRole('region', { name: 'Applications' })).findByText('0')).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Applications' })).getByText('For Garden House')).toBeInTheDocument()
    expect(fetch.mock.calls.slice(-2).every(([url]) => url.endsWith(otherPropertyId))).toBe(true)
  })

  it('shows the exact no-property state and real zero portfolio metrics', async () => {
    getMyProperties.mockResolvedValue([])
    renderApp('/dashboard')

    expect(await screen.findByRole('heading', { name: 'No properties yet' })).toBeInTheDocument()
    expect(screen.getByText('Add your first property to start receiving viewing requests and rental applications.')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Add Property' })).toHaveAttribute('href', '/properties/new')
    const active = screen.getByRole('region', { name: 'Active Properties' })
    expect(within(active).getByText('0')).toBeInTheDocument()
    expect(within(active).getByText('No properties yet')).toBeInTheDocument()
    const portfolio = screen.getByRole('region', { name: 'Portfolio Overview' })
    expect(portfolio).toHaveTextContent('Available properties0 / 0')
    expect(portfolio).toHaveTextContent('Unavailable properties0 / 0')
    expect(within(portfolio).queryByText('Average monthly rent')).not.toBeInTheDocument()
  })

  it('uses honest empty copy for an application-free selected property', async () => {
    fetch.mockImplementation(() => Promise.resolve(json([])))
    renderApp()
    const recent = screen.getByRole('region', { name: 'Recent Applications' })

    expect(await within(recent).findByText('No applications yet')).toBeInTheDocument()
    expect(within(recent).getByText('Rental applications for this property will appear here.')).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Needs Attention' })).getByText("You're all caught up")).toBeInTheDocument()
  })

  it.each(['viewings', 'applications'])('shows and retries the %s error without inventing a zero summary', async (failed) => {
    let attempts = 0
    fetch.mockImplementation((url) => {
      const viewing = isViewing(url)
      if (viewing === (failed === 'viewings') && ++attempts === 1) return Promise.resolve(json({}, 500))
      return Promise.resolve(json(viewing ? viewings : applications))
    })
    renderApp()
    const failedCard = screen.getByRole('region', { name: failed === 'viewings' ? 'Pending Viewings' : 'Applications' })

    expect(await within(failedCard).findByText('Summary unavailable')).toBeInTheDocument()
    expect(within(failedCard).getByText('Something went wrong while loading the latest landlord data.')).toBeInTheDocument()
    expect(within(failedCard).queryByText('0')).not.toBeInTheDocument()
    await userEvent.click(within(failedCard).getByRole('button', { name: 'Try again' }))
    expect(await within(failedCard).findByText(failed === 'viewings' ? '2' : '8')).toBeInTheDocument()
    expect(fetch).toHaveBeenCalledTimes(3)
  })

  it('rejects mismatched or duplicate scoped records and does not request AI validation', async () => {
    fetch.mockImplementation(() => Promise.resolve(json([
      { ...applications[1], propertyId: otherPropertyId },
      { ...applications[1], propertyId: otherPropertyId },
    ])))
    renderApp()

    const applicationCard = screen.getByRole('region', { name: 'Applications' })
    expect(await within(applicationCard).findByText('Summary unavailable')).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Recent Applications' })).getByText("We couldn't load this section")).toBeInTheDocument()
    expect(getApplicationValidationRuns).not.toHaveBeenCalled()
  })

  it('uses only the authenticated selected-property endpoints', async () => {
    renderApp()
    await within(screen.getByRole('region', { name: 'Applications' })).findByText('8')

    expect(fetch).toHaveBeenCalledTimes(2)
    expect(fetch.mock.calls.map(([url]) => new URL(url, 'http://localhost').pathname).sort()).toEqual([
      `/api/rental-applications/property/${propertyId}`,
      `/api/viewings/property/${propertyId}`,
    ])
    for (const [, options] of fetch.mock.calls) {
      expect(options.headers.Authorization).toBe('Bearer landlord-token')
      expect(options.method).toBeUndefined()
      expect(options.body).toBeUndefined()
    }
  })

  it('discards late responses after changing properties', async () => {
    const oldRequests = []
    fetch.mockImplementation(() => new Promise((resolve) => { oldRequests.push(resolve) }))
    const { router } = renderApp()
    await waitFor(() => expect(oldRequests).toHaveLength(2))
    fetch.mockImplementation(() => Promise.resolve(json([])))

    await act(async () => { await router.navigate(scopedDashboard(otherPropertyId)) })
    expect(await within(screen.getByRole('region', { name: 'Applications' })).findByText('0')).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Applications' })).getByText('For Garden House')).toBeInTheDocument()
    await act(async () => {
      oldRequests[0](json(viewings))
      oldRequests[1](json(applications))
    })
    expect(within(screen.getByRole('region', { name: 'Applications' })).queryByText('8')).not.toBeInTheDocument()
    expect(fetch.mock.calls.slice(2).every(([url]) => url.endsWith(otherPropertyId))).toBe(true)
  })

  it('publishes selected-property pending counts to the existing sidebar badges', async () => {
    renderApp()
    const navigation = screen.getByRole('navigation', { name: 'Primary navigation' })
    expect(await within(navigation).findByRole('link', { name: 'Viewing Requests, 2 pending' })).toBeInTheDocument()
    expect(within(navigation).getByRole('link', { name: 'Rental Applications, 3 pending' })).toBeInTheDocument()
  })

  it.each(['Tenant', 'Admin', 'MaintenanceTechnician'])('does not load landlord-scoped data for %s', async (role) => {
    renderApp(scopedDashboard(), { ...landlord, role })
    await act(async () => {})
    expect(fetch.mock.calls.some(([url]) => url.includes('/property/'))).toBe(false)
    expect(screen.queryByRole('navigation', { name: 'Quick actions' })).not.toBeInTheDocument()
  })

  it('uses the existing session-expiry behavior for a 401 response', async () => {
    fetch.mockImplementation(() => Promise.resolve(json({}, 401)))
    const api = { getCurrentUser: vi.fn().mockResolvedValue(landlord) }
    const router = createMemoryRouter(
      [{ path: '*', element: <AuthProvider api={api}><App /></AuthProvider> }],
      { initialEntries: [scopedDashboard()] },
    )
    render(<RouterProvider router={router} />)

    expect(await screen.findByRole('heading', { name: 'Sign in to RentFlow' })).toBeInTheDocument()
    expect(tokenStorage.getToken()).toBeNull()
  })
})
