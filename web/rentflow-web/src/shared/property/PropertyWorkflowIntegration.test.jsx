import { cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter, RouterProvider } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import { AuthContext } from '../../features/auth/useAuth.js'

vi.mock('../../features/notifications/notificationsApi.js', async (importOriginal) => ({
  ...(await importOriginal()), getUnreadCount: vi.fn().mockResolvedValue(0),
}))

const propertyId = '11111111-1111-1111-1111-111111111111'
const otherPropertyId = '99999999-9999-9999-9999-999999999999'
const property = {
  id: propertyId,
  landlordId: '22222222-2222-2222-2222-222222222222',
  title: 'Harbour View Residence',
  description: 'A real owned property fixture.',
  address: '18 Marine Drive',
  city: 'Colombo',
  monthlyRent: 185000,
  bedrooms: 3,
  bathrooms: 2,
  isAvailable: true,
  createdAt: '2026-09-01T00:00:00Z',
  updatedAt: null,
  amenities: ['Parking'],
}
const viewing = {
  id: '33333333-3333-3333-3333-333333333333',
  tenantId: '44444444-4444-4444-4444-444444444444',
  propertyId,
  requestedDateTime: '2030-01-02T10:00:00Z',
  status: 0,
  tenantMessage: 'Please confirm the viewing.',
  landlordResponse: null,
  createdAt: '2026-09-20T00:00:00Z',
  updatedAt: null,
}
const applicationId = '55555555-5555-5555-5555-555555555555'
const application = {
  id: applicationId,
  tenantId: viewing.tenantId,
  propertyId,
  moveInDate: '2030-02-01',
  monthlyIncome: 500000,
  occupation: 'Engineer',
  numberOfOccupants: 2,
  tenantNote: null,
  status: 2,
  landlordResponse: null,
  createdAt: '2026-09-20T00:00:00Z',
  submittedAt: '2026-09-21T00:00:00Z',
  updatedAt: null,
}

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'Content-Type': 'application/json' },
})

function renderApp(entry) {
  const router = createMemoryRouter([{ path: '*', element: <App /> }], { initialEntries: [entry] })
  render(<AuthContext.Provider value={{
    user: { id: property.landlordId, fullName: 'Nila Perera', email: 'nila@example.com', role: 'Landlord' },
    isAuthenticated: true,
    isLoading: false,
    logout: vi.fn(),
  }}><RouterProvider router={router} /></AuthContext.Provider>)
  return router
}

beforeEach(() => {
  tokenStorage.setToken('landlord-token')
  vi.stubGlobal('fetch', vi.fn((url) => {
    const path = new URL(url, 'http://localhost').pathname
    if (path === '/api/properties/mine') return Promise.resolve(json([property]))
    if (path === `/api/viewings/property/${propertyId}`) return Promise.resolve(json([viewing]))
    if (path === `/api/rental-applications/${applicationId}`) return Promise.resolve(json(application))
    if (path.startsWith(`/api/properties/${propertyId}/images`)) return Promise.resolve(json([]))
    return Promise.resolve(json([]))
  }))
})

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

describe('owned property landlord workflow integration', () => {
  it('selects from the authenticated collection and opens canonical viewing requests with property display data', async () => {
    const router = renderApp('/viewing-requests')
    const propertyLink = await screen.findByRole('link', { name: /Harbour View Residence/ })
    expect(propertyLink).toHaveAttribute('href', `/properties/${propertyId}/viewing-requests`)

    await userEvent.click(propertyLink)

    expect(router.state.location.pathname).toBe(`/properties/${propertyId}/viewing-requests`)
    expect(await screen.findByText('Please confirm the viewing.')).toBeInTheDocument()
    expect(screen.getAllByText('Harbour View Residence').length).toBeGreaterThan(0)
    expect(screen.getAllByText(/18 Marine Drive, Colombo/).length).toBeGreaterThan(0)

    const propertyCalls = fetch.mock.calls.filter(([url]) =>
      new URL(url, 'http://localhost').pathname.startsWith('/api/properties'))
    expect(propertyCalls.map(([url]) => new URL(url, 'http://localhost').pathname))
      .toEqual(['/api/properties/mine'])
    expect(propertyCalls[0][1].headers.Authorization).toBe('Bearer landlord-token')
  })

  it('rejects a property outside the authenticated owned collection', async () => {
    renderApp(`/properties/${otherPropertyId}/rental-applications`)

    expect(await screen.findByRole('heading', { name: 'Property unavailable' })).toBeInTheDocument()
    expect(screen.getByText(/not in your authenticated property portfolio/)).toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Rental applications' })).not.toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Harbour View Residence/ }))
      .toHaveAttribute('href', `/properties/${propertyId}/rental-applications`)
  })

  it('exposes canonical viewing and application navigation from Manage Properties', async () => {
    renderApp('/modules/manage-properties')

    const card = await screen.findByRole('article')
    expect(within(card).getByRole('heading', { name: property.title })).toBeInTheDocument()
    expect(within(card).getByText('18 Marine Drive, Colombo')).toBeInTheDocument()
    expect(within(card).getByText('Rs. 185,000')).toBeInTheDocument()
    expect(within(card).getByText('Available')).toBeInTheDocument()
    expect(within(card).getByText('Bedrooms').parentElement).toHaveTextContent('3')
    expect(within(card).getByText('Bathrooms').parentElement).toHaveTextContent('2')
    expect(within(card).getByRole('link', { name: 'Viewing Requests' }))
      .toHaveAttribute('href', `/properties/${propertyId}/viewing-requests`)
    expect(within(card).getByRole('link', { name: 'Rental Applications' }))
      .toHaveAttribute('href', `/properties/${propertyId}/rental-applications`)
    expect(within(card).getByRole('link', { name: 'View property' }))
      .toHaveAttribute('href', `/properties/${propertyId}`)
    expect(within(card).getByRole('button', { name: 'Edit property' })).toBeInTheDocument()
    expect(within(card).queryByText('Parking')).not.toBeInTheDocument()
    expect(within(card).queryByRole('button', { name: /favorite|heart/i })).not.toBeInTheDocument()
  })

  it('keeps the create form compact until the landlord chooses to add a property', async () => {
    renderApp('/modules/manage-properties')

    expect(await screen.findByRole('heading', { name: property.title })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Create Property' })).not.toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Add Property' }))

    expect(screen.getByRole('heading', { name: 'Add to your portfolio' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Create Property' })).toBeInTheDocument()
    expect(screen.getByLabelText('Property title')).toBeInTheDocument()
  })

  it('filters the authenticated owned-property list by title or city on the client', async () => {
    renderApp('/modules/manage-properties')

    const search = await screen.findByLabelText('Search properties by title or city')
    await userEvent.type(search, 'Kandy')

    expect(screen.getByRole('heading', { name: 'No matching properties' })).toBeInTheDocument()
    expect(screen.queryByRole('article')).not.toBeInTheDocument()

    await userEvent.clear(search)
    await userEvent.type(search, 'Colombo')

    expect(await screen.findByRole('heading', { name: property.title })).toBeInTheDocument()
    expect(fetch.mock.calls.filter(([url]) =>
      new URL(url, 'http://localhost').pathname === '/api/properties/mine')).toHaveLength(1)
  })

  it('keeps the owned property context in AI Validation and Back to Applications', async () => {
    renderApp(`/properties/${propertyId}/rental-applications/${applicationId}/validation`)

    expect(await screen.findByRole('heading', { name: 'AI Validation Report' })).toBeInTheDocument()
    expect(screen.getByText('Harbour View Residence')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to Applications' }))
      .toHaveAttribute('href', `/properties/${propertyId}/rental-applications`)
  })

  it('shows the honest no-properties state without falling back to the public collection', async () => {
    fetch.mockImplementation((url) => {
      const path = new URL(url, 'http://localhost').pathname
      return Promise.resolve(json(path === '/api/properties/mine' ? [] : []))
    })
    renderApp('/rental-applications')

    expect(await screen.findByRole('heading', { name: 'No owned properties' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Manage properties' }))
      .toHaveAttribute('href', '/modules/manage-properties')
    expect(fetch.mock.calls.map(([url]) => new URL(url, 'http://localhost').pathname))
      .toEqual(['/api/properties/mine'])
  })

  it('retries an owned-property API error and then offers the real selection', async () => {
    let attempts = 0
    fetch.mockImplementation((url) => {
      const path = new URL(url, 'http://localhost').pathname
      if (path === '/api/properties/mine') {
        attempts += 1
        return Promise.resolve(attempts === 1 ? json({}, 500) : json([property]))
      }
      return Promise.resolve(json([]))
    })
    renderApp('/viewing-requests')

    expect(await screen.findByRole('heading', { name: 'We could not load your properties' })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByRole('link', { name: /Harbour View Residence/ })).toBeInTheDocument()
    expect(attempts).toBe(2)
  })
})
