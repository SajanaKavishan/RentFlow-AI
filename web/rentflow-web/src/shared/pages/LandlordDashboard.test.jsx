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

// Fixture IDs are only used by tests; production always uses the existing context.
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
  isAvailable: false,
}
const viewings = [0, 0, 1, 2, 3, 4].map((status, index) => ({ id: `viewing-${index}`, propertyId, status }))
const applications = [0, 1, 1, 2, 3, 4, 5, 6].map((status, index) => ({ id: `application-${index}`, propertyId, status }))
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const scopedDashboard = (id = propertyId) => `/dashboard?propertyId=${id}`
const isViewing = (url) => url.includes('/api/viewings/property/')

function renderApp(entry = scopedDashboard(), user = landlord) {
  const router = createMemoryRouter([{ path: '*', element: <App /> }], { initialEntries: [entry] })
  const tree = (account) => <AuthContext.Provider value={{ user: account, isAuthenticated: true, isLoading: false, logout: vi.fn() }}><RouterProvider router={router} /></AuthContext.Provider>
  const result = render(tree(user))
  return { router, changeUser: (account) => result.rerender(tree(account)) }
}

beforeEach(() => {
  tokenStorage.setToken('landlord-token')
  getMyProperties.mockReset().mockResolvedValue([ownedProperty, otherOwnedProperty])
  getApplicationValidationRuns.mockReset().mockResolvedValue([])
  vi.stubGlobal('fetch', vi.fn((url) => Promise.resolve(json(isViewing(url) ? viewings : applications))))
})
afterEach(() => { cleanup(); vi.unstubAllGlobals() })

describe('landlord dashboard', () => {
  it.each(['/dashboard', '/dashboard?propertyId=invalid'])('requires property context at %s without fetching or displaying fake counts', async (entry) => {
    renderApp(entry)
    expect(screen.getByRole('heading', { name: 'Welcome, Nila Perera' })).toBeInTheDocument()
    expect(await screen.findByRole('heading', { name: 'Select a property' })).toBeInTheDocument()
    expect(screen.getByText(/Choose one of your owned properties/)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Lake View Apartment/ })).toHaveAttribute('href', `/dashboard?propertyId=${propertyId}`)
    expect(screen.queryByText('Property required')).not.toBeInTheDocument()
    expect(screen.getAllByText('Summary unavailable')).toHaveLength(2)
    const cards = document.querySelector('.landlord-dashboard__summaries')
    expect(within(cards).getAllByRole('region').map((card) => card.getAttribute('aria-label'))).toEqual([
      'Active Properties', 'Pending Viewings', 'Applications', 'Revenue This Month',
    ])
    expect(within(cards).getAllByText('Integration pending')).toHaveLength(1)
    expect(document.querySelector('.landlord-dashboard__summaries--unavailable')).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Needs Attention' })).not.toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Recent Applications' })).not.toBeInTheDocument()
    expect(getApplicationValidationRuns).not.toHaveBeenCalled()
    expect(within(screen.getByRole('region', { name: 'Active Properties' })).getByText('1')).toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
    expect(screen.queryByLabelText(/Viewing Requests, \d+ pending/)).not.toBeInTheDocument()
    expect(screen.queryByLabelText(/Rental Applications, \d+ pending/)).not.toBeInTheDocument()
  })

  it('summarizes status counts using only the existing authenticated property endpoints', async () => {
    renderApp()
    const cards = document.querySelector('.landlord-dashboard__summaries')
    expect(within(cards).getAllByRole('region').map((card) => card.getAttribute('aria-label'))).toEqual([
      'Active Properties', 'Pending Viewings', 'Applications', 'Revenue This Month',
    ])
    const visits = screen.getByRole('region', { name: 'Pending Viewings' })
    const apps = screen.getByRole('region', { name: 'Applications' })
    expect(await within(visits).findByText('2')).toBeInTheDocument()
    expect(within(visits).getByText('2').tagName).toBe('STRONG')
    expect(within(visits).getByText('6 total requests')).toBeInTheDocument()
    expect(within(visits).getByRole('link', { name: 'Open Viewing Requests' })).toHaveAttribute('href', `/viewing-requests?propertyId=${propertyId}`)
    expect(within(visits).queryByText('Open Viewing Requests')).not.toBeInTheDocument()
    expect(await within(apps).findByText('8')).toBeInTheDocument()
    expect(within(apps).getByText('8').tagName).toBe('STRONG')
    expect(within(apps).getByRole('heading', { name: 'Applications' })).toBeInTheDocument()
    expect(within(apps).getByRole('link', { name: 'Open Rental Applications' })).toHaveAttribute('href', `/rental-applications?propertyId=${propertyId}`)
    expect(within(apps).queryByText('Open Rental Applications')).not.toBeInTheDocument()
    for (const [label, count] of [['Submitted', '2'], ['Under review', '1'], ['Changes requested', '1']]) {
      expect(within(apps).getByText(label).nextElementSibling).toHaveTextContent(count)
    }
    expect(screen.getByRole('region', { name: 'Property context' })).toHaveTextContent('Lake View Apartment')
    expect(screen.getByRole('region', { name: 'Property context' })).toHaveTextContent('12 Lake Road, Colombo')
    const active = screen.getByRole('region', { name: 'Active Properties' })
    expect(within(active).getByText('1')).toBeInTheDocument()
    expect(within(active).getByText('2 total owned properties')).toBeInTheDocument()
    expect(within(active).getByRole('link', { name: 'Open Manage Properties' })).toHaveAttribute('href', '/modules/manage-properties')
    const revenue = screen.getByRole('region', { name: 'Revenue This Month' })
    expect(within(revenue).getByText('Integration pending')).toBeInTheDocument()
    expect(within(revenue).queryByRole('link')).not.toBeInTheDocument()
    expect(fetch).toHaveBeenCalledTimes(2)
    expect(fetch.mock.calls.map(([url]) => new URL(url, 'http://localhost').pathname).sort()).toEqual([
      `/api/rental-applications/property/${propertyId}`, `/api/viewings/property/${propertyId}`,
    ])
    for (const [, options] of fetch.mock.calls) {
      expect(options.headers.Authorization).toBe('Bearer landlord-token')
      expect(options.method).toBeUndefined()
      expect(options.body).toBeUndefined()
    }
  })

  it('shows the scoped pending viewing count in the sidebar and hides it after opening the workflow', async () => {
    const { router } = renderApp()
    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    const viewingLink = await within(nav).findByRole('link', { name: 'Viewing Requests, 2 pending' })
    expect(within(viewingLink).getByText('2')).toHaveClass('shared-nav-link__pending')
    await userEvent.click(viewingLink)
    expect(await screen.findByRole('heading', { name: 'Viewing Requests' })).toBeInTheDocument()
    expect(router.state.location.search).toBe(`?propertyId=${propertyId}`)
    expect(within(nav).getByRole('link', { name: 'Viewing Requests' })).not.toHaveTextContent('2')
    await userEvent.click(within(nav).getByRole('link', { name: 'Dashboard' }))
    await screen.findByText('6 total requests')
    expect(within(nav).getByRole('link', { name: 'Viewing Requests' })).not.toHaveTextContent('2')
  })

  it('shows only reviewable applications in the sidebar and dismisses that badge independently', async () => {
    const { router } = renderApp()
    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    const applicationLink = await within(nav).findByRole('link', { name: 'Rental Applications, 3 pending' })
    expect(within(applicationLink).getByText('3')).toHaveClass('shared-nav-link__pending')
    expect(within(nav).getByRole('link', { name: 'Viewing Requests, 2 pending' })).toBeInTheDocument()
    await userEvent.click(applicationLink)
    expect(await screen.findByRole('heading', { name: 'Rental Applications' })).toBeInTheDocument()
    expect(router.state.location.search).toBe(`?propertyId=${propertyId}`)
    expect(within(nav).getByRole('link', { name: 'Rental Applications' })).not.toHaveTextContent('3')
    expect(within(nav).getByRole('link', { name: 'Viewing Requests, 2 pending' })).toBeInTheDocument()
    await userEvent.click(within(nav).getByRole('link', { name: 'Dashboard' }))
    await screen.findByText('8')
    expect(within(nav).getByRole('link', { name: 'Rental Applications' })).not.toHaveTextContent('3')
  })

  it('uses router-state property context and retains it in all three workflow shortcuts', async () => {
    renderApp({ pathname: '/dashboard', state: { propertyId } })
    await screen.findByRole('region', { name: 'Recent Applications' })
    const dashboard = screen.getByRole('main')
    for (const [label, path] of [['Viewing Requests', '/viewing-requests'], ['Rental Applications', '/rental-applications'], ['AI Review', '/ai-review']]) {
      const links = within(dashboard).getAllByRole('link', { name: `Open ${label}` })
      expect(links).toHaveLength(1)
      expect(links[0]).toHaveAttribute('href', `${path}?propertyId=${propertyId}`)
    }
  })

  it('keeps each summary loading independently and distinguishes an empty result from missing data', async () => {
    let finishViewings
    fetch.mockImplementation((url) => isViewing(url) ? new Promise((resolve) => { finishViewings = resolve }) : new Promise(() => {}))
    renderApp()
    await waitFor(() => expect(screen.getAllByText('Loading summary…')).toHaveLength(2))
    expect(screen.queryByText('0')).not.toBeInTheDocument()
    await act(async () => { finishViewings(json([])) })
    expect(screen.getByText('No viewing requests for this property yet.')).toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Pending Viewings' })).toHaveAttribute('aria-busy', 'false')
    expect(screen.getByRole('region', { name: 'Applications' })).toHaveAttribute('aria-busy', 'true')
    expect(screen.getAllByText('Loading summary…')).toHaveLength(1)
  })

  it('shows successful empty summaries without invented AI findings or decisions', async () => {
    fetch.mockImplementation(() => Promise.resolve(json([])))
    renderApp()
    expect(await screen.findByText('No viewing requests for this property yet.')).toBeInTheDocument()
    expect(await screen.findByText('No rental applications for this property yet.')).toBeInTheDocument()
    expect(screen.getAllByText('0')).toHaveLength(2)
    expect(fetch).toHaveBeenCalledTimes(2)
    expect(screen.queryByText(/AI score|match score|approved automatically/i)).not.toBeInTheDocument()
  })

  it.each(['viewings', 'applications'])('retries a failed %s summary without reloading its successful sibling', async (failed) => {
    let attempts = 0
    fetch.mockImplementation((url) => {
      const viewing = isViewing(url)
      if (viewing === (failed === 'viewings') && ++attempts === 1) return Promise.resolve(json({}, 500))
      return Promise.resolve(json(viewing ? viewings : applications))
    })
    renderApp()
    expect(await screen.findByRole('alert')).toHaveTextContent('request failed')
    expect(await within(screen.getByRole('region', { name: failed === 'viewings' ? 'Applications' : 'Pending Viewings' })).findByText(failed === 'viewings' ? '8' : '2')).toBeInTheDocument()
    expect(screen.queryByText('0')).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: failed === 'viewings' ? 'Retry pending viewings' : 'Retry applications' }))
    expect(await within(screen.getByRole('region', { name: failed === 'viewings' ? 'Pending Viewings' : 'Applications' })).findByText(failed === 'viewings' ? '2' : '8')).toBeInTheDocument()
    expect(fetch).toHaveBeenCalledTimes(3)
  })

  it.each([403, 404])('respects a %s property authorization response without falling back to unscoped requests', async (status) => {
    fetch.mockImplementation(() => Promise.resolve(json({ detail: 'Do not expose this detail' }, status)))
    renderApp()
    const alerts = await screen.findAllByRole('alert')
    expect(alerts).toHaveLength(2)
    expect(alerts[0]).toHaveTextContent(status === 403 ? 'You do not have permission' : 'The requested resource is unavailable')
    expect(screen.queryByText('0')).not.toBeInTheDocument()
    expect(screen.queryByText('Do not expose this detail')).not.toBeInTheDocument()
    expect(fetch).toHaveBeenCalledTimes(2)
    expect(fetch.mock.calls.every(([url]) => url.includes(`/property/${propertyId}`))).toBe(true)
  })

  it('handles network failures and malformed records as errors, not empty summaries', async () => {
    fetch.mockImplementation((url) => isViewing(url) ? Promise.reject(new TypeError('offline')) : Promise.resolve(json([{ id: 'missing-status' }])))
    renderApp()
    expect(await screen.findByText('Unable to connect to the viewing service. Please try again.')).toBeInTheDocument()
    expect(await screen.findByText('The service returned an invalid summary. Please try again.')).toBeInTheDocument()
    expect(screen.queryByText('0')).not.toBeInTheDocument()
  })

  it('discards late responses after switching properties and clears counts when selection is removed', async () => {
    const oldRequests = []
    fetch.mockImplementation(() => new Promise((resolve) => { oldRequests.push(resolve) }))
    const { router } = renderApp()
    await waitFor(() => expect(oldRequests).toHaveLength(2))
    fetch.mockImplementation(() => Promise.resolve(json([])))
    await act(async () => { await router.navigate(scopedDashboard(otherPropertyId)) })
    expect(await screen.findByText('No rental applications for this property yet.')).toBeInTheDocument()
    await act(async () => { oldRequests[0](json(viewings)); oldRequests[1](json(applications)) })
    expect(screen.queryByText('6 total requests')).not.toBeInTheDocument()
    expect(screen.queryByText('8')).not.toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Property context' })).toHaveTextContent('Garden House')
    expect(fetch.mock.calls.slice(2).every(([url]) => url.endsWith(otherPropertyId))).toBe(true)
    await act(async () => { await router.navigate('/dashboard') })
    expect(screen.getByRole('heading', { name: 'Select a property' })).toBeInTheDocument()
    expect(screen.queryByText('0')).not.toBeInTheDocument()
    expect(fetch).toHaveBeenCalledTimes(4)
  })

  it('clears already-loaded summaries immediately while a different property loads', async () => {
    const { router } = renderApp()
    await screen.findByText('8')
    fetch.mockImplementation(() => new Promise(() => {}))
    await act(async () => { await router.navigate(scopedDashboard(otherPropertyId)) })
    expect(screen.getAllByText('Loading summary…')).toHaveLength(2)
    expect(screen.queryByText('8')).not.toBeInTheDocument()
    expect(screen.queryByText('6 total requests')).not.toBeInTheDocument()
  })

  it('discards the previous account’s requests when the authenticated landlord changes', async () => {
    const oldRequests = []
    fetch.mockImplementation(() => new Promise((resolve) => { oldRequests.push(resolve) }))
    const { changeUser } = renderApp()
    await waitFor(() => expect(oldRequests).toHaveLength(2))
    fetch.mockImplementation(() => Promise.resolve(json([])))
    tokenStorage.setToken('second-landlord-token')
    changeUser({ ...landlord, id: 'landlord-two', fullName: 'Amara Silva' })
    expect(await screen.findByText('No rental applications for this property yet.')).toBeInTheDocument()
    await act(async () => { oldRequests[0](json(viewings)); oldRequests[1](json(applications)) })
    expect(screen.getByRole('heading', { name: 'Welcome, Amara Silva' })).toBeInTheDocument()
    expect(screen.queryByText('8')).not.toBeInTheDocument()
    expect(fetch.mock.calls.slice(2).every(([, options]) => options.headers.Authorization === 'Bearer second-landlord-token')).toBe(true)
  })

  it.each([
    ['Viewing Requests', '/viewing-requests', 'Viewing Requests'],
    ['Rental Applications', '/rental-applications', 'Rental Applications'],
    ['AI Review', '/ai-review', 'AI Review'],
  ])('opens the existing %s screen with the selected property', async (label, path, heading) => {
    fetch.mockImplementation(() => Promise.resolve(json([])))
    const { router } = renderApp()
    await screen.findByText('No viewing requests for this property yet.')
    await userEvent.click(within(screen.getByRole('main')).getByRole('link', { name: `Open ${label}` }))
    expect(await screen.findByRole('heading', { name: heading })).toBeInTheDocument()
    expect(router.state.location.pathname).toBe(path)
    expect(router.state.location.search).toBe(`?propertyId=${propertyId}`)
    expect(await screen.findByText(label === 'Viewing Requests' ? 'No viewing requests yet' : 'No rental applications yet')).toBeInTheDocument()
  })

  it('keeps shortcuts usable without a selection and lets existing screens request property context', async () => {
    renderApp('/dashboard')
    const link = within(screen.getByRole('main')).getByRole('link', { name: 'Open Viewing Requests' })
    expect(link).toHaveAttribute('href', '/viewing-requests')
    await userEvent.click(link)
    expect(screen.getByRole('heading', { name: 'Viewing Requests' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Select a property' })).toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
  })

  it.each(['Tenant', 'Admin', 'MaintenanceTechnician'])('does not call property summary endpoints for %s', async (role) => {
    fetch.mockImplementation(() => Promise.resolve(json([])))
    renderApp(scopedDashboard(), { ...landlord, role })
    await act(async () => {})
    expect(screen.getByRole('heading', { name: role === 'Admin' ? 'System Overview' : 'Welcome, Nila Perera' })).toBeInTheDocument()
    expect(fetch.mock.calls.some(([url]) => url.includes('/property/'))).toBe(false)
    expect(screen.queryByRole('link', { name: 'Open AI Review' })).not.toBeInTheDocument()
  })

  it('uses the existing session-expiry behavior for a 401 response', async () => {
    fetch.mockImplementation(() => Promise.resolve(json({}, 401)))
    const api = { getCurrentUser: vi.fn().mockResolvedValue(landlord) }
    const router = createMemoryRouter([{ path: '*', element: <AuthProvider api={api}><App /></AuthProvider> }], { initialEntries: [scopedDashboard()] })
    render(<RouterProvider router={router} />)
    expect(await screen.findByRole('heading', { name: 'Sign in to RentFlow' })).toBeInTheDocument()
    expect(tokenStorage.getToken()).toBeNull()
  })

  it('shows only pending viewings and reviewable applications as attention actions', async () => {
    renderApp()
    const attention = await screen.findByRole('region', { name: 'Needs Attention' })
    expect(within(attention).getByText('2 pending viewing requests')).toBeInTheDocument()
    expect(within(attention).getByText('3 applications ready for review')).toBeInTheDocument()
    expect(within(attention).queryByText(/changes requested/i)).not.toBeInTheDocument()
    expect(within(attention).getByRole('link', { name: 'Review viewings' })).toHaveAttribute('href', `/viewing-requests?propertyId=${propertyId}`)
    expect(within(attention).getByRole('link', { name: 'Review applications' })).toHaveAttribute('href', `/rental-applications?propertyId=${propertyId}`)
    expect(getApplicationValidationRuns.mock.calls.map(([id]) => id)).toEqual(['application-1', 'application-2', 'application-3'])
  })

  it('omits attention when loaded records have no landlord actions', async () => {
    fetch.mockImplementation((url) => Promise.resolve(json(isViewing(url) ? viewings.filter((item) => item.status !== 0) : applications.filter((item) => ![1, 2].includes(item.status)))))
    renderApp()
    await screen.findByRole('region', { name: 'Recent Applications' })
    expect(screen.queryByRole('heading', { name: 'Needs Attention' })).not.toBeInTheDocument()
    expect(getApplicationValidationRuns).not.toHaveBeenCalled()
  })

  it('shows five recent references, real dates and statuses without private tenant details', async () => {
    const records = applications.map((item, index) => ({ ...item, createdAt: `2026-09-${String(index + 1).padStart(2, '0')}T12:00:00Z`, monthlyIncome: 987654, occupation: 'Private occupation', tenantNote: 'Private note', tenantId: 'private-tenant' }))
    // Submitted date takes precedence over creation date.
    records[0].submittedAt = '2026-09-20T12:00:00Z'
    fetch.mockImplementation((url) => Promise.resolve(json(isViewing(url) ? [] : records)))
    renderApp()
    const recent = await screen.findByRole('region', { name: 'Recent Applications' })
    const rows = within(recent).getAllByRole('row').slice(1)
    expect(rows).toHaveLength(5)
    expect(rows.map((row) => within(row).getByRole('rowheader').textContent)).toEqual(['application-0', 'application-7', 'application-6', 'application-5', 'application-4'])
    expect(rows[0].querySelector('time')).toHaveAttribute('dateTime', records[0].submittedAt)
    expect(within(rows[0]).getByLabelText('Application status: Draft')).toBeInTheDocument()
    expect(within(rows[1]).getByLabelText('Application status: Withdrawn')).toBeInTheDocument()
    expect(within(rows[0]).getByRole('link')).toHaveAttribute('href', `/notifications/rental-application/application-0?propertyId=${propertyId}`)
    expect(screen.queryByText(/987654|Private occupation|Private note|private-tenant/)).not.toBeInTheDocument()
  })

  it('opens a recent application in the existing authorized detail workflow', async () => {
    const record = { ...applications[1], createdAt: '2026-09-20T12:00:00Z', moveInDate: '2026-10-01', monthlyIncome: 1000, numberOfOccupants: 1 }
    fetch.mockImplementation((url) => Promise.resolve(json(isViewing(url) ? [] : url.includes('/property/') ? [record] : url.endsWith('/validation-runs') ? [] : record)))
    const { router } = renderApp()
    await userEvent.click(await screen.findByRole('link', { name: 'Open application application-1' }))
    expect(await screen.findByRole('heading', { name: 'Rental application' })).toBeInTheDocument()
    expect(router.state.location.search).toBe(`?propertyId=${propertyId}`)
    expect(await screen.findByRole('button', { name: 'Start review' })).toBeInTheDocument()
  })

  it('fetches AI runs with authentication only for scoped reviewable applications and uses the latest run', async () => {
    const actual = await vi.importActual('../../features/rentalApplications/services/applicationValidationApiService.js')
    getApplicationValidationRuns.mockImplementation(actual.getApplicationValidationRuns)
    fetch.mockImplementation((url) => {
      if (url.includes('/validation-runs')) {
        const id = url.split('/').at(-2)
        return Promise.resolve(json([{ id: `latest-${id}`, applicationId: id, status: id === 'application-1' ? 2 : id === 'application-2' ? 4 : 3 }, { id: `old-${id}`, applicationId: id, status: 2 }]))
      }
      return Promise.resolve(json(isViewing(url) ? viewings : applications))
    })
    renderApp()
    expect(await screen.findByText('1 AI workflow awaits human review')).toBeInTheDocument()
    expect(screen.getByText('1 AI workflow needs a retry')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Review AI findings' })).toHaveAttribute('href', `/ai-review?propertyId=${propertyId}`)
    const validationCalls = fetch.mock.calls.filter(([url]) => url.endsWith('/validation-runs'))
    expect(validationCalls).toHaveLength(3)
    validationCalls.forEach(([, options]) => {
      expect(options.headers.Authorization).toBe('Bearer landlord-token')
      expect(options.method).toBeUndefined()
    })
  })

  it('keeps AI Review accessible and labels partial failures without inventing results', async () => {
    getApplicationValidationRuns.mockImplementation((id) => id === 'application-1'
      ? Promise.resolve([{ id: 'run-one', applicationId: id, status: 2 }])
      : Promise.reject(new Error('private service detail')))
    renderApp()
    expect(await screen.findByText(/AI summary unavailable or incomplete/)).toBeInTheDocument()
    expect(screen.getByText('1 AI workflow awaits human review')).toBeInTheDocument()
    expect(screen.queryByText('private service detail')).not.toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Open AI Review' })).toHaveAttribute('href', `/ai-review?propertyId=${propertyId}`)
  })

  it('discards AI results after property changes', async () => {
    const pending = []
    getApplicationValidationRuns.mockImplementation((id) => new Promise((resolve) => pending.push(() => resolve([{ id: 'old-run', applicationId: id, status: 2 }]))))
    const { router } = renderApp()
    await screen.findByRole('region', { name: 'Recent Applications' })
    fetch.mockImplementation(() => Promise.resolve(json([])))
    await act(async () => { await router.navigate(scopedDashboard(otherPropertyId)) })
    await act(async () => { pending.forEach((resolve) => resolve()) })
    expect(screen.queryByText(/workflow awaits human review/)).not.toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Needs Attention' })).not.toBeInTheDocument()
  })

  it('rejects mismatched property records before showing rows or requesting AI data', async () => {
    fetch.mockImplementation(() => Promise.resolve(json([{ ...applications[1], propertyId: otherPropertyId }])))
    renderApp()
    expect(await screen.findAllByRole('alert')).toHaveLength(2)
    expect(screen.queryByRole('heading', { name: 'Recent Applications' })).not.toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Needs Attention' })).not.toBeInTheDocument()
    expect(getApplicationValidationRuns).not.toHaveBeenCalled()
  })

  it('rejects duplicate records instead of inflating counts or rendering duplicate application rows', async () => {
    fetch.mockImplementation(() => Promise.resolve(json([applications[1], applications[1]])))
    renderApp()
    expect(await screen.findAllByRole('alert')).toHaveLength(2)
    expect(screen.queryByRole('heading', { name: 'Recent Applications' })).not.toBeInTheDocument()
    expect(getApplicationValidationRuns).not.toHaveBeenCalled()
  })

  it('uses a valid creation date when submission dates are malformed and never invents missing dates', async () => {
    const records = [
      { ...applications[5], submittedAt: 'invalid', createdAt: '2026-09-19T12:00:00Z' },
      { ...applications[6], submittedAt: 123, createdAt: null },
    ]
    fetch.mockImplementation((url) => Promise.resolve(json(isViewing(url) ? [] : records)))
    renderApp()
    const recent = await screen.findByRole('region', { name: 'Recent Applications' })
    expect(recent.querySelectorAll('time')).toHaveLength(1)
    expect(recent.querySelector('time')).toHaveAttribute('dateTime', records[0].createdAt)
    expect(within(recent).getByText('Date unavailable')).toBeInTheDocument()
  })

  it.each([
    null,
    [{ id: 'run', applicationId: 'another-application', status: 2 }],
    [{ id: 'run', applicationId: 'application-1', status: 99 }],
    [{ id: 123, applicationId: 'application-1', status: 2 }],
  ])('keeps AI Review available when workflow data is malformed: %j', async (runs) => {
    getApplicationValidationRuns.mockResolvedValue(runs)
    renderApp()
    expect(await screen.findByText(/AI summary unavailable or incomplete/)).toBeInTheDocument()
    expect(screen.getByText(/AI counts include only confirmed results/)).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'Review AI findings' })).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'Open validation' })).not.toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Open AI Review' })).toHaveAttribute('href', `/ai-review?propertyId=${propertyId}`)
  })

  it('discards pending AI requests when the authenticated account changes', async () => {
    const pending = []
    getApplicationValidationRuns.mockImplementation((id) => new Promise((resolve) => pending.push(() => resolve([{ id: 'old-run', applicationId: id, status: 2 }]))))
    const { changeUser } = renderApp()
    await screen.findByRole('region', { name: 'Recent Applications' })
    expect(getApplicationValidationRuns).toHaveBeenCalledTimes(3)
    fetch.mockImplementation(() => Promise.resolve(json([])))
    changeUser({ ...landlord, id: 'landlord-two', fullName: 'Amara Silva' })
    await screen.findByText('No rental applications for this property yet.')
    await act(async () => { pending.forEach((resolve) => resolve()) })
    expect(screen.queryByRole('heading', { name: 'Needs Attention' })).not.toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Recent Applications' })).not.toBeInTheDocument()
    expect(screen.queryByText(/workflow awaits human review/)).not.toBeInTheDocument()
  })

  it('limits AI requests in flight and stops queued requests after leaving the property', async () => {
    const records = Array.from({ length: 9 }, (_, index) => ({ ...applications[1], id: `application-${index}` }))
    fetch.mockImplementation((url) => Promise.resolve(json(isViewing(url) ? [] : records)))
    const pending = []
    getApplicationValidationRuns.mockImplementation(() => new Promise((resolve) => pending.push(resolve)))
    const { router } = renderApp()
    await screen.findByRole('region', { name: 'Recent Applications' })
    expect(getApplicationValidationRuns).toHaveBeenCalledTimes(4)
    await act(async () => { pending[0]([]) })
    expect(getApplicationValidationRuns).toHaveBeenCalledTimes(5)
    await act(async () => { await router.navigate('/dashboard') })
    await act(async () => { pending.slice(1).forEach((resolve) => resolve([])) })
    expect(getApplicationValidationRuns).toHaveBeenCalledTimes(5)
    expect(screen.queryByRole('heading', { name: 'Needs Attention' })).not.toBeInTheDocument()
  })
})
