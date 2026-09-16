import { cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
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

afterEach(() => { cleanup(); tokenStorage.clearToken() })

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

  it.each(['Tenant', 'Admin', 'MaintenanceTechnician'])('filters navigation for %s', async (role) => {
    renderApp(role)
    const nav = await screen.findByRole('navigation', { name: 'Primary navigation' })
    expect(within(nav).queryByRole('link', { name: 'Viewing Requests' })).not.toBeInTheDocument()
    expect(within(nav).queryByRole('link', { name: 'Rental Applications' })).not.toBeInTheDocument()
    expect(within(nav).getByRole('link', { name: 'Profile' })).toBeInTheDocument()
    if (role === 'Tenant') expect(within(nav).getByRole('link', { name: /My Applications/ })).toBeInTheDocument()
    if (role === 'Admin') expect(within(nav).getByRole('link', { name: /AI Workflow Monitoring/ })).toBeInTheDocument()
    if (role === 'MaintenanceTechnician') expect(within(nav).getByRole('link', { name: /Assigned Maintenance/ })).toBeInTheDocument()
  })

  it('labels missing modules honestly', async () => {
    renderApp('Tenant', '/modules/properties')
    expect(await screen.findByRole('heading', { name: 'Properties' })).toBeInTheDocument()
    expect(screen.getByText('Not available yet')).toBeInTheDocument()
    expect(screen.getByText(/No workflow is available here/)).toBeInTheDocument()
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

  it('shows authorization feedback inside the authenticated shell', async () => {
    renderApp('Tenant', '/rental-applications')
    expect(await screen.findByRole('heading', { name: 'Not accessible' })).toBeInTheDocument()
    expect(screen.getByRole('navigation', { name: 'Primary navigation' })).toBeInTheDocument()
  })
})
