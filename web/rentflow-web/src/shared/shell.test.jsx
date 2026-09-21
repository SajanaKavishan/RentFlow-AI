import { act, cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../App.jsx'
import { tokenStorage } from '../core/auth/tokenStorage.js'
import { AuthProvider } from '../features/auth/AuthContext.jsx'

vi.mock('../features/viewings/pages/ViewingRequestsPage.jsx', () => ({ default: () => <main><h1>Viewing requests workflow</h1></main> }))
vi.mock('../features/rentalApplications/pages/RentalApplicationsPage.jsx', () => ({ default: () => <main><h1>Rental applications workflow</h1></main> }))

const userFor = (role) => ({ id: 'user-id', fullName: 'Taylor Example', email: 'taylor@example.com', phoneNumber: '+94 77 123 4567', role })
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
    ['Tenant', ['Dashboard', 'Properties', 'My Viewings', 'My Applications', 'Lease & Payments', 'Maintenance', 'Profile']],
    ['Landlord', ['Dashboard', 'Properties', 'Viewing Requests', 'Rental Applications', 'AI Review', 'Pricing / Lease', 'Payments', 'Maintenance', 'Profile']],
    ['MaintenanceTechnician', ['Dashboard', 'Assigned Work', 'Profile']],
    ['Admin', ['Dashboard', 'Users', 'AI / System Overview', 'Profile']],
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

  it('keeps landlord AI review on the real rental application workflow', async () => {
    renderApp('Landlord', '/ai-review')
    expect(await screen.findByRole('heading', { name: 'Rental applications workflow' })).toBeInTheDocument()
  })

  it('shows profile details and logs out', async () => {
    renderApp('Tenant', '/profile')
    expect(await screen.findByRole('heading', { name: 'Profile' })).toBeInTheDocument()
    expect(screen.getByText('taylor@example.com')).toBeInTheDocument()
    expect(screen.getByText('+94 77 123 4567')).toBeInTheDocument()
    await userEvent.click(screen.getAllByRole('button', { name: 'Logout' })[0])
    expect(await screen.findByRole('heading', { name: 'Sign in to RentFlow' })).toBeInTheDocument()
    expect(tokenStorage.getToken()).toBeNull()
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

  it('closes the drawer when a route is selected and keeps profile and logout available', async () => {
    renderApp('Landlord')
    await screen.findByRole('heading', { name: 'Welcome, Taylor Example' })
    await userEvent.click(screen.getByRole('button', { name: 'Open navigation' }))
    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    expect(within(nav).getByRole('link', { name: 'Profile' })).toBeInTheDocument()
    expect(within(nav).getByRole('button', { name: 'Logout' })).toBeInTheDocument()
    await userEvent.click(within(nav).getByRole('link', { name: 'Viewing Requests' }))
    expect(await screen.findByRole('heading', { name: 'Viewing requests workflow' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Open navigation' })).toHaveAttribute('aria-expanded', 'false')
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
    await userEvent.click(screen.getByRole('button', { name: 'Close menu' }))
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
