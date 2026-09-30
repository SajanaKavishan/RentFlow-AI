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
const tenantGreeting = /^(Welcome back|Good to see you|Hello|Hi there), Taylor Tenant$/

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
  it('renders the public landing page at the root route', () => {
    renderApp()
    expect(screen.getByRole('heading', { name: 'Find your perfect home, smarter.' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Everything you need for the rental journey.' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Smarter help throughout your rental journey.' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Your rental journey, kept together.' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Built for every part of the rental process.' })).not.toBeInTheDocument()
    expect(screen.queryByRole('navigation', { name: 'Primary navigation' })).not.toBeInTheDocument()
  })

  it('shows a transparent navbar initially', () => {
    renderApp()
    const navbar = screen.getByRole('banner')
    expect(navbar).toHaveAttribute('data-visible', 'true')
    expect(navbar).toHaveAttribute('data-surface', 'transparent')
  })

  it('hides after meaningful downward scrolling', async () => {
    renderApp()
    const navbar = screen.getByRole('banner')
    scrollTo(120)
    await waitFor(() => expect(navbar).toHaveAttribute('data-visible', 'false'))
    expect(navbar).toHaveAttribute('data-surface', 'dark')
  })

  it('reappears on upward movement from a lower landing section', async () => {
    renderApp()
    const navbar = screen.getByRole('banner')
    scrollTo(1400)
    await waitFor(() => expect(navbar).toHaveAttribute('data-visible', 'false'))
    scrollTo(1370)
    await waitFor(() => expect(navbar).toHaveAttribute('data-visible', 'true'))
    expect(navbar).toHaveAttribute('data-surface', 'dark')
  })

  it('restores the visible transparent state at the top', async () => {
    renderApp()
    const navbar = screen.getByRole('banner')
    scrollTo(180)
    await waitFor(() => expect(navbar).toHaveAttribute('data-visible', 'false'))
    scrollTo(0)
    await waitFor(() => {
      expect(navbar).toHaveAttribute('data-visible', 'true')
      expect(navbar).toHaveAttribute('data-surface', 'transparent')
    })
  })

  it('navigates Get Started to the real registration page', async () => {
    renderApp()
    await userEvent.click(screen.getAllByRole('link', { name: 'Get Started' })[0])
    expect(await screen.findByRole('heading', { name: 'Create your RentFlow account' })).toBeInTheDocument()
  })

  it('navigates an unauthenticated Sign In request to login', async () => {
    renderApp()
    await userEvent.click(screen.getAllByRole('button', { name: 'Sign In' })[0])
    expect(await screen.findByRole('heading', { name: 'Sign in to RentFlow' })).toBeInTheDocument()
  })

  it('keeps landing visible during session restoration and enters the authenticated home only after Sign In', async () => {
    let finishRestore
    const restoredUser = new Promise((resolve) => { finishRestore = resolve })
    tokenStorage.setToken('stored-token')
    const api = apiWith()
    api.getCurrentUser.mockReturnValue(restoredUser)
    renderApp(api)

    expect(screen.getByRole('heading', { name: 'Find your perfect home, smarter.' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: tenantGreeting })).not.toBeInTheDocument()

    await userEvent.click(screen.getAllByRole('button', { name: 'Sign In' })[0])
    expect(screen.getAllByRole('button', { name: 'Restoring…' })[0]).toBeDisabled()
    finishRestore(tenant)

    expect(await screen.findByRole('heading', { name: tenantGreeting })).toBeInTheDocument()
    expect(screen.getByRole('navigation', { name: 'Primary navigation' })).toBeInTheDocument()
  })

  it('uses in-page section links without leaving the landing route', async () => {
    renderApp()
    const navigation = screen.getByRole('navigation', { name: 'Landing page navigation' })
    const platformLink = within(navigation).getByRole('link', { name: 'Platform' })
    const assistanceLink = within(navigation).getByRole('link', { name: 'Smart Assistance' })
    expect(platformLink).toHaveAttribute('href', '#platform')
    expect(assistanceLink).toHaveAttribute('href', '#smart-assistance')
    expect(within(navigation).queryByRole('link', { name: 'Roles' })).not.toBeInTheDocument()
    await userEvent.click(platformLink)
    expect(screen.getByRole('heading', { name: 'Everything you need for the rental journey.' })).toBeInTheDocument()
  })

  it('uses a simplified mobile header without drawer controls', () => {
    renderApp()
    const header = screen.getByRole('banner')
    expect(within(header).queryByRole('button', { name: 'Open menu' })).not.toBeInTheDocument()
    expect(within(header).queryByRole('button', { name: 'Close menu' })).not.toBeInTheDocument()
    expect(header.querySelector('.public-header__mobile-signin')).toHaveTextContent('Sign In')
    expect(header.querySelector('.public-header__menu')).not.toBeInTheDocument()
  })

  it('renders product-value rail cards without testimonial claims or ratings', () => {
    renderApp()
    const rail = screen.getByLabelText('Product experience highlights')
    expect(within(rail).getAllByText('Easy property discovery')).toHaveLength(2)
    expect(within(rail).getAllByText('Human-controlled decisions')).toHaveLength(2)
    expect(rail.querySelector('.experience-rail__list[aria-hidden="true"]')).toBeInTheDocument()
    expect(rail).not.toHaveTextContent('★')
    expect(screen.queryByText(/what customers say|testimonial/i)).not.toBeInTheDocument()
  })

  it('keeps one complete semantic value list available without animation', () => {
    renderApp()
    const rail = screen.getByLabelText('Product experience highlights')
    const primaryList = rail.querySelector('.experience-rail__list:not([aria-hidden])')
    expect(primaryList).toBeInTheDocument()
    expect(within(primaryList).getAllByRole('listitem')).toHaveLength(12)
    expect(rail.querySelector('.experience-rail__list[aria-hidden="true"]')).toHaveAttribute('aria-hidden', 'true')
  })

  it('validates feedback fields and never fakes successful delivery', async () => {
    renderApp()
    const sendButton = screen.getByRole('button', { name: 'Send message' })
    await userEvent.click(sendButton)
    expect(screen.getByText('Enter your name.')).toBeInTheDocument()
    expect(screen.getByText('Enter your email address.')).toBeInTheDocument()
    expect(screen.getByText('Enter your message.')).toBeInTheDocument()

    await userEvent.type(screen.getByLabelText('Name'), 'Taylor Example')
    await userEvent.type(screen.getByLabelText('Email'), 'taylor@example.com')
    await userEvent.type(screen.getByLabelText('Message'), 'I have a question about RentFlow.')
    await userEvent.click(sendButton)

    expect(await screen.findByRole('alert')).toHaveTextContent('Message delivery is not connected yet.')
    expect(screen.queryByText(/message sent|sent successfully/i)).not.toBeInTheDocument()
  })

  it('renders a minimal footer without repeated navigation or auth actions', () => {
    renderApp()
    const footer = screen.getByRole('contentinfo')
    expect(within(footer).queryByRole('link', { name: 'RentFlow AI home' })).not.toBeInTheDocument()
    expect(within(footer).getByText('© 2026 RentFlow AI. All rights reserved.')).toBeInTheDocument()
    expect(within(footer).queryByRole('navigation')).not.toBeInTheDocument()
    expect(within(footer).queryByText('Platform')).not.toBeInTheDocument()
    expect(within(footer).queryByText('How It Works')).not.toBeInTheDocument()
    expect(within(footer).queryByText('Smart Assistance')).not.toBeInTheDocument()
    expect(within(footer).queryByText('Sign In')).not.toBeInTheDocument()
    expect(within(footer).queryByText('Create Account')).not.toBeInTheDocument()
  })

  it('removes the repeated Final CTA while preserving navbar auth actions', () => {
    renderApp()
    expect(screen.queryByRole('heading', { name: 'Ready to start your rental journey?' })).not.toBeInTheDocument()
    const navigation = screen.getByRole('navigation', { name: 'Landing page navigation' })
    expect(within(navigation).getByRole('button', { name: 'Sign In' })).toBeInTheDocument()
    expect(within(navigation).getByRole('link', { name: 'Get Started' })).toHaveAttribute('href', '/register')
  })
})
