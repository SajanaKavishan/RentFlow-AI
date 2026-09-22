import { act, cleanup, render, screen, within } from '@testing-library/react'
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

// Fixture IDs are only used by tests; production always uses the existing context.
const propertyId = '88888888-8888-8888-8888-888888888888'
const otherPropertyId = '99999999-9999-9999-9999-999999999999'
const landlord = { id: 'landlord-one', fullName: 'Nila Perera', email: 'nila@example.com', phoneNumber: '', role: 'Landlord' }
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
  vi.stubGlobal('fetch', vi.fn((url) => Promise.resolve(json(isViewing(url) ? viewings : applications))))
})
afterEach(() => { cleanup(); vi.unstubAllGlobals() })

describe('landlord dashboard', () => {
  it.each(['/dashboard', '/dashboard?propertyId=invalid'])('requires property context at %s without fetching or displaying fake counts', (entry) => {
    renderApp(entry)
    expect(screen.getByRole('heading', { name: 'Welcome, Nila Perera' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Select a property' })).toBeInTheDocument()
    expect(screen.getByText(/Property integration pending/)).toBeInTheDocument()
    expect(screen.getAllByText('Property required')).toHaveLength(2)
    expect(screen.queryByText('0')).not.toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
  })

  it('summarizes status counts using only the existing authenticated property endpoints', async () => {
    renderApp()
    const visits = screen.getByRole('region', { name: 'Viewing Requests' })
    const apps = screen.getByRole('region', { name: 'Rental Applications' })
    expect(await within(visits).findByText('6')).toBeInTheDocument()
    expect(within(visits).getByText('Pending response').nextElementSibling).toHaveTextContent('2')
    expect(await within(apps).findByText('8')).toBeInTheDocument()
    for (const [label, count] of [['Submitted', '2'], ['Under review', '1'], ['Changes requested', '1']]) {
      expect(within(apps).getByText(label).nextElementSibling).toHaveTextContent(count)
    }
    expect(screen.getByRole('region', { name: 'Property context' })).toHaveTextContent(propertyId)
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

  it('uses router-state property context and retains it in all three workflow shortcuts', async () => {
    renderApp({ pathname: '/dashboard', state: { propertyId } })
    await screen.findByText('Total requests')
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
    expect(screen.getAllByText('Loading summary…')).toHaveLength(2)
    expect(screen.queryByText('0')).not.toBeInTheDocument()
    await act(async () => { finishViewings(json([])) })
    expect(screen.getByText('No viewing requests for this property yet.')).toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Viewing Requests' })).toHaveAttribute('aria-busy', 'false')
    expect(screen.getByRole('region', { name: 'Rental Applications' })).toHaveAttribute('aria-busy', 'true')
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
    expect(await screen.findByText(failed === 'viewings' ? '8' : '6')).toBeInTheDocument()
    expect(screen.queryByText('0')).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: failed === 'viewings' ? 'Retry viewing requests' : 'Retry rental applications' }))
    expect(await screen.findByText(failed === 'viewings' ? '6' : '8')).toBeInTheDocument()
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
    fetch.mockImplementation(() => Promise.resolve(json([])))
    await act(async () => { await router.navigate(scopedDashboard(otherPropertyId)) })
    expect(await screen.findByText('No rental applications for this property yet.')).toBeInTheDocument()
    await act(async () => { oldRequests[0](json(viewings)); oldRequests[1](json(applications)) })
    expect(screen.queryByText('6')).not.toBeInTheDocument()
    expect(screen.queryByText('8')).not.toBeInTheDocument()
    expect(screen.getByRole('region', { name: 'Property context' })).toHaveTextContent(otherPropertyId)
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
    expect(screen.queryByText('6')).not.toBeInTheDocument()
  })

  it('discards the previous account’s requests when the authenticated landlord changes', async () => {
    const oldRequests = []
    fetch.mockImplementation(() => new Promise((resolve) => { oldRequests.push(resolve) }))
    const { changeUser } = renderApp()
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
    ['Viewing Requests', '/viewing-requests', 'Viewing requests'],
    ['Rental Applications', '/rental-applications', 'Rental applications'],
    ['AI Review', '/ai-review', 'Rental applications'],
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
    expect(screen.getByRole('heading', { name: 'Viewing requests' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Select a property' })).toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
  })

  it.each(['Tenant', 'Admin', 'MaintenanceTechnician'])('does not call property summary endpoints for %s', async (role) => {
    fetch.mockImplementation(() => Promise.resolve(json([])))
    renderApp(scopedDashboard(), { ...landlord, role })
    await act(async () => {})
    expect(screen.getByRole('heading', { name: 'Welcome, Nila Perera' })).toBeInTheDocument()
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
})
