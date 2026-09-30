import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import { AuthProvider } from '../auth/AuthContext.jsx'

const tenant = {
  id: 'landing-user',
  fullName: 'Taylor Tenant',
  email: 'tenant@example.com',
  phoneNumber: '+94 77 123 4567',
  role: 'Tenant',
}

function apiWith(currentUser = null) {
  return {
    login: vi.fn(),
    register: vi.fn(),
    getCurrentUser: vi.fn().mockResolvedValue(currentUser),
  }
}

function renderApp(api = apiWith(), initialEntry = '/') {
  return render(<MemoryRouter initialEntries={[initialEntry]}><AuthProvider api={api}><App /></AuthProvider></MemoryRouter>)
}

function scrollTo(y) {
  Object.defineProperty(window, 'scrollY', { configurable: true, value: y })
  fireEvent.scroll(window)
}

afterEach(() => {
  cleanup()
  tokenStorage.clearToken()
  Object.defineProperty(window, 'scrollY', { configurable: true, value: 0 })
})

describe('public landing experience', () => {
  it('renders the public landing page and guest hero journey', () => {
    renderApp()
    expect(screen.getByRole('heading', { name: 'Find your perfect home, smarter.' })).toBeInTheDocument()
    expect(screen.getByText('AI-powered rental search and management for a simpler rental journey.')).toBeInTheDocument()
    expect(screen.getAllByRole('link', { name: /Get Started/ })[0]).toHaveAttribute('href', '/get-started')
    expect(screen.getByRole('link', { name: 'Explore the platform' })).toHaveAttribute('href', '/platform')
    expect(screen.queryByRole('navigation', { name: 'Primary navigation' })).not.toBeInTheDocument()
  })

  it('keeps the auto-hiding header behavior', async () => {
    renderApp()
    const navbar = screen.getByRole('banner')
    expect(navbar).toHaveAttribute('data-visible', 'true')
    expect(navbar).toHaveAttribute('data-surface', 'transparent')
    scrollTo(120)
    await waitFor(() => expect(navbar).toHaveAttribute('data-visible', 'false'))
    expect(navbar).toHaveAttribute('data-surface', 'dark')
    scrollTo(90)
    await waitFor(() => expect(navbar).toHaveAttribute('data-visible', 'true'))
  })

  it('routes Get Started to the two supported public account choices', async () => {
    renderApp()
    await userEvent.click(screen.getAllByRole('link', { name: 'Get Started' })[0])
    expect(await screen.findByRole('heading', { name: 'How would you like to use RentFlow?' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Continue as Tenant/ })).toHaveAttribute('href', '/register?role=tenant')
    expect(screen.getByRole('link', { name: /Continue as Landlord/ })).toHaveAttribute('href', '/register?role=landlord')
    expect(screen.queryByText('Admin', { selector: '.role-choice-card__role' })).not.toBeInTheDocument()
    expect(screen.queryByText('Technician', { selector: '.role-choice-card__role' })).not.toBeInTheDocument()
  })

  it('routes guest Sign In to the canonical login page', async () => {
    renderApp()
    await userEvent.click(screen.getByRole('link', { name: 'Sign In' }))
    expect(await screen.findByRole('heading', { name: 'Sign in to RentFlow' })).toBeInTheDocument()
  })

  it('uses dedicated public information routes in the navbar', async () => {
    renderApp()
    const navigation = screen.getByRole('navigation', { name: 'Landing page navigation' })
    expect(within(navigation).getByRole('link', { name: 'Platform' })).toHaveAttribute('href', '/platform')
    expect(within(navigation).getByRole('link', { name: 'How It Works' })).toHaveAttribute('href', '/how-it-works')
    expect(within(navigation).getByRole('link', { name: 'Smart Assistance' })).toHaveAttribute('href', '/smart-assistance')
    await userEvent.click(within(navigation).getByRole('link', { name: 'Platform' }))
    expect(await screen.findByRole('heading', { name: 'One rental platform. A workspace for every role.' })).toBeInTheDocument()
  })

  it.each([
    ['/how-it-works', 'A clear path through the rental journey.'],
    ['/smart-assistance', 'Useful intelligence, with clear boundaries.'],
  ])('keeps %s public and renders its marketing content', async (path, heading) => {
    renderApp(apiWith(), path)
    expect(await screen.findByRole('heading', { name: heading })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Sign In' })).toHaveAttribute('href', '/login')
  })

  it('provides an accessible mobile navigation menu control', async () => {
    renderApp()
    const header = screen.getByRole('banner')
    const openMenu = within(header).getByRole('button', { name: 'Open menu' })
    expect(openMenu).toHaveAttribute('aria-expanded', 'false')
    await userEvent.click(openMenu)
    expect(within(header).getByRole('button', { name: 'Close menu' })).toHaveAttribute('aria-expanded', 'true')
    expect(header.querySelector('.public-header__nav')).toHaveClass('is-open')
  })

  it('shows Tenant hero and navbar destinations after restoring a session', async () => {
    tokenStorage.setToken('stored-token')
    renderApp(apiWith(tenant))
    expect(await screen.findByRole('link', { name: /Browse Properties/ })).toHaveAttribute('href', '/modules/properties')
    expect(screen.getByRole('link', { name: 'My Dashboard' })).toHaveAttribute('href', '/dashboard')
    expect(screen.getByRole('link', { name: 'Open Workspace' })).toHaveAttribute('href', '/modules/properties')
    expect(screen.queryByRole('link', { name: 'Sign In' })).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'Get Started' })).not.toBeInTheDocument()
  })

  it.each([
    ['Landlord', 'Manage Properties', '/modules/manage-properties', 'Dashboard', '/dashboard'],
    ['MaintenanceTechnician', 'View Assigned Work', '/modules/assigned-work', 'Dashboard', '/dashboard'],
  ])('shows isolated %s hero destinations', async (role, primaryLabel, primaryPath, secondaryLabel, secondaryPath) => {
    tokenStorage.setToken('stored-token')
    renderApp(apiWith({ ...tenant, role }))
    expect(await screen.findByRole('link', { name: new RegExp(primaryLabel) })).toHaveAttribute('href', primaryPath)
    expect(screen.getByRole('link', { name: secondaryLabel })).toHaveAttribute('href', secondaryPath)
    expect(screen.queryByRole('link', { name: 'Get Started' })).not.toBeInTheDocument()
  })

  it('shows only the Admin dashboard hero action for an authenticated Admin', async () => {
    tokenStorage.setToken('stored-token')
    renderApp(apiWith({ ...tenant, role: 'Admin' }))
    expect(await screen.findByRole('link', { name: /Open Admin Dashboard/ })).toHaveAttribute('href', '/dashboard')
    expect(screen.queryByRole('link', { name: 'Dashboard' })).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: /Browse Properties|Manage Properties|View Assigned Work/ })).not.toBeInTheDocument()
  })

  it('redirects an authenticated Tenant away from Get Started to the Tenant workspace', async () => {
    tokenStorage.setToken('stored-token')
    renderApp(apiWith(tenant), '/get-started')
    expect(await screen.findByRole('heading', { name: 'Find a home that fits' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'How would you like to use RentFlow?' })).not.toBeInTheDocument()
  })

  it('keeps role identity unchanged when using role-aware links', async () => {
    tokenStorage.setToken('stored-token')
    const landlord = { ...tenant, role: 'Landlord' }
    const api = apiWith(landlord)
    renderApp(api)
    const manageLink = await screen.findByRole('link', { name: /Manage Properties/ })
    expect(manageLink).toHaveAttribute('href', '/modules/manage-properties')
    expect(api.getCurrentUser).toHaveBeenCalledTimes(1)
    expect(landlord.role).toBe('Landlord')
  })

  it('renders product-value rail cards without fake testimonials or ratings', () => {
    renderApp()
    const rail = screen.getByLabelText('Product experience highlights')
    expect(within(rail).getAllByText('Easy property discovery')).toHaveLength(2)
    expect(rail.querySelector('.experience-rail__list[aria-hidden="true"]')).toBeInTheDocument()
    expect(screen.queryByText(/what customers say|testimonial/i)).not.toBeInTheDocument()
  })

  it('validates feedback and never fakes successful delivery', async () => {
    renderApp()
    const sendButton = screen.getByRole('button', { name: 'Send message' })
    await userEvent.click(sendButton)
    expect(screen.getByText('Enter your name.')).toBeInTheDocument()
    await userEvent.type(screen.getByLabelText('Name'), 'Taylor Example')
    await userEvent.type(screen.getByLabelText('Email'), 'taylor@example.com')
    await userEvent.type(screen.getByLabelText('Message'), 'I have a question about RentFlow.')
    await userEvent.click(sendButton)
    expect(await screen.findByRole('alert')).toHaveTextContent('Message delivery is not connected yet.')
    expect(screen.queryByText(/message sent|sent successfully/i)).not.toBeInTheDocument()
  })

  it('keeps the footer minimal', () => {
    renderApp()
    const footer = screen.getByRole('contentinfo')
    expect(within(footer).getByText('© 2026 RentFlow AI. All rights reserved.')).toBeInTheDocument()
    expect(within(footer).queryByRole('navigation')).not.toBeInTheDocument()
  })
})
