import { act, cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../App.jsx'
import { tokenStorage } from '../core/auth/tokenStorage.js'
import { AuthProvider } from '../features/auth/AuthContext.jsx'

vi.mock('../features/viewings/pages/ViewingRequestsPage.jsx', () => ({ default: () => <main><h1>Viewing requests workflow</h1></main> }))
vi.mock('../features/rentalApplications/pages/RentalApplicationsPage.jsx', () => ({ default: () => <main><h1>Rental applications workflow</h1></main> }))

const userFor = (role) => ({ id: 'user-id', fullName: 'Taylor Example', email: 'taylor@example.com', phoneNumber: '+94 77 123 4567', role })
const propertyId = '88888888-8888-8888-8888-888888888888'
function renderApp(role, path = '/dashboard', authenticated = true) {
  if (authenticated) tokenStorage.setToken('test-token')
  const api = { login: vi.fn(), register: vi.fn(), getCurrentUser: vi.fn().mockResolvedValue(userFor(role)) }
  return render(<MemoryRouter initialEntries={[path]}><AuthProvider api={api}><App /></AuthProvider></MemoryRouter>)
}

beforeEach(() => {
  vi.stubGlobal('fetch', vi.fn().mockImplementation(() => Promise.resolve(new Response('[]', { status: 200 }))))
  vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
})
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('shared React shell', () => {
  it('keeps unauthenticated routes on login outside the shell', async () => {
    renderApp('Tenant', '/dashboard', false)
    expect(await screen.findByRole('heading', { name: 'Sign in to RentFlow' })).toBeInTheDocument()
    const authBrand = screen.getByRole('complementary')
    expect(authBrand).toHaveTextContent('RentFlow AI')
    expect(within(authBrand).getByRole('link', { name: 'RentFlow AI home' })).toHaveAttribute('href', '/')
    expect(authBrand.querySelector('img')).toHaveAttribute('src', expect.stringContaining('rentflow-mark'))
    expect(screen.queryByRole('img', { name: 'RentFlow AI' })).not.toBeInTheDocument()
    expect(screen.queryByRole('navigation', { name: 'Primary navigation' })).not.toBeInTheDocument()
  })

  it('renders a role dashboard and a landlord sidebar with working workflow links', async () => {
    renderApp('Landlord')
    expect(await screen.findByRole('heading', { name: 'Welcome, Taylor Example' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'RentFlow dashboard' }).querySelector('img')).toHaveAttribute('src', expect.stringContaining('rentflow-wordmark'))
    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    await userEvent.click(within(nav).getByRole('link', { name: 'Viewing Requests' }))
    expect(await screen.findByRole('heading', { name: 'Viewing requests workflow' })).toBeInTheDocument()
    await userEvent.click(within(nav).getByRole('link', { name: 'Rental Applications' }))
    expect(await screen.findByRole('heading', { name: 'Rental applications workflow' })).toBeInTheDocument()
  })

  it.each([
    ['Tenant', ['Dashboard', 'Properties', 'My Viewings', 'My Applications', 'Lease & Payments', 'Maintenance']],
    ['Landlord', ['Dashboard', 'Properties', 'Viewing Requests', 'Rental Applications', 'AI Review', 'Pricing / Lease', 'Payments', 'Maintenance']],
    ['MaintenanceTechnician', ['Dashboard', 'Assigned Work']],
    ['Admin', ['Dashboard', 'Users', 'Support Requests', 'AI / System Overview']],
  ])('renders the exact navigation map for %s', async (role, expectedLabels) => {
    renderApp(role)
    const nav = await screen.findByRole('navigation', { name: 'Primary navigation' })
    const brand = screen.getByRole('link', { name: 'RentFlow dashboard' })
    expect(brand.querySelector('img')).toHaveAttribute('src', expect.stringContaining('rentflow-wordmark'))
    expect(brand).toHaveTextContent('A better way to rent')
    const labels = within(nav).getAllByRole('link').map((link) => link.textContent.replace('Soon', ''))
    expect(labels).toEqual(expectedLabels)
  })

  it('labels missing modules honestly', async () => {
    renderApp('Tenant', '/modules/properties')
    expect(await screen.findByRole('heading', { name: 'Properties' })).toBeInTheDocument()
    expect(screen.getByText('Integration pending')).toBeInTheDocument()
    expect(screen.getByText(/property module is integrated/)).toBeInTheDocument()
    expect(screen.getByText('Owning area: Property management')).toBeInTheDocument()
  })

  it('keeps landlord property selection unavailable without inventing property context', async () => {
    renderApp('Landlord', '/viewing-requests')
    expect(await screen.findByRole('heading', { name: 'Viewing requests workflow' })).toBeInTheDocument()

    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    const propertiesLink = within(nav).getByText('Properties').closest('a')
    const viewingsLink = within(nav).getByRole('link', { name: 'Viewing Requests' })

    expect(propertiesLink).toHaveAttribute('href', '/modules/properties')
    expect(within(propertiesLink).getByText('Soon')).toBeInTheDocument()
    expect(viewingsLink).toHaveAttribute('href', '/viewing-requests')
    expect(fetch.mock.calls.some(([url]) =>
      new URL(url).pathname.startsWith('/api/properties') ||
      new URL(url).pathname.startsWith('/api/viewings'))).toBe(false)
  })

  it('keeps landlord AI review on the real rental application workflow', async () => {
    renderApp('Landlord', '/ai-review')
    expect(await screen.findByRole('heading', { name: 'Rental applications workflow' })).toBeInTheDocument()
  })

  it('shows profile details and logs out', async () => {
    renderApp('Tenant', '/profile')
    expect(await screen.findByRole('heading', { name: 'Profile' })).toBeInTheDocument()
    expect(screen.getAllByText('taylor@example.com')).toHaveLength(2)
    expect(screen.getByText('+94 77 123 4567')).toBeInTheDocument()
    await userEvent.click(screen.getAllByRole('button', { name: 'Logout' })[0])
    expect(await screen.findByRole('heading', { name: 'Sign in to RentFlow' })).toBeInTheDocument()
    expect(tokenStorage.getToken()).toBeNull()
  })

  it('opens the account popup from the top-right control and keeps Profile out of the sidebar', async () => {
    renderApp('Admin')
    const account = await screen.findByRole('button', { name: 'Profile for Taylor Example' })
    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    expect(within(nav).queryByRole('link', { name: 'Profile' })).not.toBeInTheDocument()
    await userEvent.click(account)
    const popup = screen.getByRole('dialog', { name: 'Account menu' })
    expect(account).toHaveAttribute('aria-expanded', 'true')
    expect(popup).toHaveTextContent('Taylor Example')
    expect(popup).toHaveTextContent('taylor@example.com')
    expect(popup).toHaveTextContent('Admin')
    expect(within(popup).getByRole('link', { name: 'View full profile' })).toHaveAttribute('href', '/profile')
    expect(within(popup).queryByRole('button', { name: 'Sign out' })).not.toBeInTheDocument()
    await userEvent.keyboard('{Escape}')
    expect(screen.queryByRole('dialog', { name: 'Account menu' })).not.toBeInTheDocument()
    expect(account).toHaveFocus()
  })

  it('renders Not Found for unknown authenticated routes', async () => {
    renderApp('Landlord', '/not-a-page')
    expect(await screen.findByRole('heading', { name: 'Page not found' })).toBeInTheDocument()
  })

  it('opens and closes the narrow navigation control', async () => {
    renderApp('Tenant')
    const open = await screen.findByRole('button', { name: 'Open navigation' })
    await userEvent.click(open)
    expect(screen.getByRole('button', { name: 'Close navigation', expanded: true })).toHaveAttribute('aria-expanded', 'true')
    expect(screen.getByRole('dialog', { name: 'Navigation menu' })).toHaveAttribute('aria-modal', 'true')
    expect(screen.getByRole('link', { name: 'RentFlow dashboard' })).toHaveFocus()
    await userEvent.keyboard('{Escape}')
    expect(screen.getByRole('button', { name: 'Open navigation' })).toHaveAttribute('aria-expanded', 'false')
    expect(screen.getByRole('button', { name: 'Open navigation' })).toHaveFocus()
  })

  it('closes the drawer when a route is selected and keeps logout available', async () => {
    renderApp('Landlord')
    await screen.findByRole('heading', { name: 'Welcome, Taylor Example' })
    await userEvent.click(screen.getByRole('button', { name: 'Open navigation' }))
    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    expect(within(nav).queryByRole('link', { name: 'Profile' })).not.toBeInTheDocument()
    expect(within(nav).getByRole('button', { name: 'Logout' })).toBeInTheDocument()
    await userEvent.click(within(nav).getByRole('link', { name: 'Viewing Requests' }))
    expect(await screen.findByRole('heading', { name: 'Viewing requests workflow' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Open navigation' })).toHaveAttribute('aria-expanded', 'false')
  })

  it('loads the pending badge from the authorized property endpoint on a direct landlord route', async () => {
    fetch.mockImplementation((url) => Promise.resolve(new Response(JSON.stringify(
      url.includes(`/api/viewings/property/${propertyId}`)
        ? [0, 0, 1].map((status, index) => ({ id: `viewing-${index}`, propertyId, status })) : [],
    ), { status: 200, headers: { 'Content-Type': 'application/json' } })))
    renderApp('Landlord', `/rental-applications?propertyId=${propertyId}`)
    const nav = await screen.findByRole('navigation', { name: 'Primary navigation' })
    const link = await within(nav).findByRole('link', { name: 'Viewing Requests, 2 pending' })
    expect(within(link).getByText('2')).toHaveClass('shared-nav-link__pending')
    expect(fetch.mock.calls.map(([url]) => new URL(url).pathname).filter((path) => path.startsWith('/api/viewings'))).toEqual([`/api/viewings/property/${propertyId}`])
    await userEvent.click(link)
    expect(await screen.findByRole('heading', { name: 'Viewing requests workflow' })).toBeInTheDocument()
    expect(within(nav).getByRole('link', { name: 'Viewing Requests' })).not.toHaveTextContent('2')
  })

  it('loads the application badge from its authorized property endpoint on a direct landlord route', async () => {
    fetch.mockImplementation((url) => Promise.resolve(new Response(JSON.stringify(
      url.includes(`/api/rental-applications/property/${propertyId}`)
        ? [0, 1, 2, 3, 4].map((status, index) => ({ id: `application-${index}`, propertyId, status })) : [],
    ), { status: 200, headers: { 'Content-Type': 'application/json' } })))
    renderApp('Landlord', `/viewing-requests?propertyId=${propertyId}`)
    const nav = await screen.findByRole('navigation', { name: 'Primary navigation' })
    const link = await within(nav).findByRole('link', { name: 'Rental Applications, 2 pending' })
    expect(within(link).getByText('2')).toHaveClass('shared-nav-link__pending')
    expect(fetch.mock.calls.map(([url]) => new URL(url).pathname).filter((path) => path.startsWith('/api/rental-applications'))).toEqual([`/api/rental-applications/property/${propertyId}`])
    await userEvent.click(link)
    expect(await screen.findByRole('heading', { name: 'Rental applications workflow' })).toBeInTheDocument()
    expect(within(nav).getByRole('link', { name: 'Rental Applications' })).not.toHaveTextContent('2')
  })

  it('does not show a pending badge for viewings belonging to another property', async () => {
    fetch.mockImplementation((url) => Promise.resolve(new Response(JSON.stringify(
      url.includes(`/api/viewings/property/${propertyId}`)
        ? [{ id: 'other-viewing', propertyId: '99999999-9999-9999-9999-999999999999', status: 0 }] : [],
    ), { status: 200, headers: { 'Content-Type': 'application/json' } })))
    renderApp('Landlord', `/rental-applications?propertyId=${propertyId}`)
    const nav = await screen.findByRole('navigation', { name: 'Primary navigation' })
    await waitFor(() => expect(fetch.mock.calls.some(([url]) => url.includes(`/api/viewings/property/${propertyId}`))).toBe(true))
    await act(async () => {})
    expect(within(nav).getByRole('link', { name: 'Viewing Requests' })).not.toHaveTextContent('1')
    expect(within(nav).queryByText('1', { selector: '.shared-nav-link__pending' })).not.toBeInTheDocument()
  })

  it.each([
    ['/dashboard query', `/dashboard?propertyId=${propertyId}`],
    ['/dashboard router state', { pathname: '/dashboard', state: { propertyId } }],
    ['property route', `/properties/${propertyId}/viewing-requests`],
  ])('keeps the actual landlord property across navigation from %s', async (_, entry) => {
    renderApp('Landlord', entry)
    const nav = await screen.findByRole('navigation', { name: 'Primary navigation' })
    for (const [name, path] of [
      ['Dashboard', '/dashboard'],
      ['Viewing Requests', '/viewing-requests'],
      ['Rental Applications', '/rental-applications'],
      ['AI Review', '/ai-review'],
    ]) {
      expect(within(nav).getByRole('link', { name })).toHaveAttribute('href', `${path}?propertyId=${propertyId}`)
    }
    expect(screen.getByRole('link', { name: 'RentFlow dashboard' })).toHaveAttribute('href', `/dashboard?propertyId=${propertyId}`)
    const account = screen.getByRole('button', { name: 'Profile for Taylor Example' })
    await userEvent.click(account)
    expect(within(screen.getByRole('dialog', { name: 'Account menu' })).getByRole('link', { name: 'View full profile' })).toHaveAttribute('href', `/profile?propertyId=${propertyId}`)
    if (typeof entry === 'string' && entry.startsWith('/properties/')) {
      expect(within(nav).getByRole('link', { name: 'Viewing Requests' })).toHaveAttribute('aria-current', 'page')
      expect(within(screen.getByRole('banner')).getByText('Viewings Management', { exact: true })).toBeInTheDocument()
    }
    await userEvent.click(within(nav).getByRole('link', { name: 'Rental Applications' }))
    expect(await screen.findByRole('heading', { name: 'Rental applications workflow' })).toBeInTheDocument()
    expect(within(screen.getByRole('banner')).getByText('Applications Management', { exact: true })).toBeInTheDocument()
    expect(within(nav).getByRole('link', { name: 'AI Review' })).toHaveAttribute('href', `/ai-review?propertyId=${propertyId}`)
    await userEvent.click(within(nav).getByRole('link', { name: 'AI Review' }))
    expect(await screen.findByRole('heading', { name: 'Rental applications workflow' })).toBeInTheDocument()
    expect(within(nav).getByRole('link', { name: 'AI Review' })).toHaveAttribute('aria-current', 'page')
  })

  it('does not invent or propagate a malformed property ID in landlord navigation', async () => {
    renderApp('Landlord', '/viewing-requests?propertyId=not-a-property')
    const nav = await screen.findByRole('navigation', { name: 'Primary navigation' })
    expect(within(nav).getByRole('link', { name: 'Rental Applications' })).toHaveAttribute('href', '/rental-applications')
    expect(screen.getByRole('link', { name: 'RentFlow dashboard' })).toHaveAttribute('href', '/dashboard')
  })

  it('contains keyboard focus and restores scrolling when the mobile menu closes', async () => {
    renderApp('Tenant')
    const open = await screen.findByRole('button', { name: 'Open navigation' })
    await userEvent.click(open)
    expect(document.body.style.overflow).toBe('hidden')
    await userEvent.tab({ shift: true })
    expect(screen.getByRole('button', { name: 'Logout' })).toHaveFocus()
    await userEvent.tab()
    expect(screen.getByRole('link', { name: 'RentFlow dashboard' })).toHaveFocus()
    expect(screen.queryByRole('button', { name: 'Close menu' })).not.toBeInTheDocument()
    await userEvent.click(document.querySelector('.shared-nav-scrim'))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(document.body.style.overflow).toBe('')
    expect(open).toHaveFocus()
  })

  it('clears the mobile dialog and scroll lock when switching to desktop', async () => {
    let resize
    matchMedia.mockReturnValue({ matches: false, addEventListener: (_, listener) => { resize = listener }, removeEventListener: vi.fn() })
    renderApp('Tenant')
    await userEvent.click(await screen.findByRole('button', { name: 'Open navigation' }))
    await act(async () => { resize({ matches: true }) })
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(document.body.style.overflow).toBe('')
    expect(screen.getByRole('button', { name: 'Open navigation' })).toHaveAttribute('aria-expanded', 'false')
  })

  it('shows authorization feedback inside the authenticated shell', async () => {
    renderApp('Tenant', '/rental-applications')
    expect(await screen.findByRole('heading', { name: 'Not accessible' })).toBeInTheDocument()
    expect(screen.getByRole('navigation', { name: 'Primary navigation' })).toBeInTheDocument()
  })
})
