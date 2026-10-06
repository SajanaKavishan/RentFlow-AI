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
  area: 1450,
  areaUnit: 'sqft',
  areaType: 'FloorArea',
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

function portfolioProperties(count) {
  return Array.from({ length: count }, (_, index) => ({
    ...property,
    id: `00000000-0000-0000-0000-${String(index + 1).padStart(12, '0')}`,
    title: `Property ${index + 1}`,
    address: `${index + 1} Main Road`,
    city: index === count - 1 ? 'Kandy' : 'Colombo',
    monthlyRent: 100000 + (index * 10000),
  }))
}

function mockOwnedPropertyCollection(collection) {
  fetch.mockImplementation((url) => {
    const path = new URL(url, 'http://localhost').pathname
    if (path === '/api/properties/mine') return Promise.resolve(json(collection))
    return Promise.resolve(json([]))
  })
}

function renderApp(entry, user = {
  id: property.landlordId,
  fullName: 'Nila Perera',
  email: 'nila@example.com',
  role: 'Landlord',
}) {
  const router = createMemoryRouter([{ path: '*', element: <App /> }], { initialEntries: [entry] })
  render(<AuthContext.Provider value={{
    user,
    isAuthenticated: true,
    isLoading: false,
    logout: vi.fn(),
  }}><RouterProvider router={router} /></AuthContext.Provider>)
  return router
}

beforeEach(() => {
  vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', '')
  tokenStorage.setToken('landlord-token')
  vi.stubGlobal('fetch', vi.fn((url) => {
    const path = new URL(url, 'http://localhost').pathname
    if (path === '/api/properties/mine') return Promise.resolve(json([property]))
    if (path === `/api/properties/${propertyId}`) return Promise.resolve(json(property))
    if (path === `/api/viewings/property/${propertyId}`) return Promise.resolve(json([viewing]))
    if (path === '/api/viewings/mine/pending-counts') return Promise.resolve(json([{ propertyId, pendingCount: 1 }]))
    if (path === '/api/rental-applications/mine/action-counts') return Promise.resolve(json([{ propertyId, actionRequiredCount: 1 }]))
    if (path === `/api/rental-applications/property/${propertyId}`) return Promise.resolve(json([application]))
    if (path === `/api/rental-applications/${applicationId}`) return Promise.resolve(json(application))
    if (path.startsWith(`/api/properties/${propertyId}/images`)) return Promise.resolve(json([]))
    return Promise.resolve(json([]))
  }))
})

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
  vi.unstubAllEnvs()
})

describe('owned property landlord workflow integration', () => {
  it('loads one authenticated application summary and opens the exact existing rental workspace', async () => {
    const router = renderApp('/rental-applications')
    const card = await screen.findByRole('button', { name: 'Harbour View Residence, 1 rental application needs attention' })
    expect(card).toHaveTextContent('1 to review')
    expect(fetch.mock.calls.some(([url]) => url.includes(`/api/rental-applications/property/${propertyId}`))).toBe(false)
    const summaryCalls = fetch.mock.calls.filter(([url]) => url.includes('/api/rental-applications/mine/action-counts'))
    expect(summaryCalls).toHaveLength(1)
    expect(summaryCalls[0][1].headers.Authorization).toBe('Bearer landlord-token')
    await userEvent.click(card)
    expect(router.state.location.pathname).toBe(`/properties/${propertyId}/rental-applications`)
    expect(await screen.findByRole('region', { name: 'Rental applications' })).toBeInTheDocument()
    expect(screen.getByRole('group', { name: 'Selected property' })).toHaveTextContent('Harbour View Residence')
    expect(screen.getByRole('link', { name: 'Change property' })).toHaveAttribute('href', '/rental-applications')
  })

  it('selects from the authenticated collection and opens canonical viewing requests with property display data', async () => {
    const router = renderApp('/viewing-requests')
    const propertyLink = await screen.findByRole('button', { name: 'Harbour View Residence, 1 pending viewing request' })

    await userEvent.click(propertyLink)

    expect(router.state.location.pathname).toBe(`/properties/${propertyId}/viewing-requests`)
    expect(await screen.findByText('Please confirm the viewing.')).toBeInTheDocument()
    expect(screen.getAllByText('Harbour View Residence').length).toBeGreaterThan(0)
    expect(screen.getAllByText(/18 Marine Drive, Colombo/).length).toBeGreaterThan(0)

    const propertyCalls = fetch.mock.calls.filter(([url]) =>
      new URL(url, 'http://localhost').pathname.startsWith('/api/properties'))
    expect(propertyCalls.map(([url]) => new URL(url, 'http://localhost').pathname))
      .toEqual(['/api/properties/mine', `/api/properties/${propertyId}/images`])
    expect(propertyCalls[0][1].headers.Authorization).toBe('Bearer landlord-token')
    const summaryCalls = fetch.mock.calls.filter(([url]) => url.includes('/api/viewings/mine/pending-counts'))
    expect(summaryCalls).toHaveLength(1)
    expect(summaryCalls[0][1].headers.Authorization).toBe('Bearer landlord-token')
  })

  it('rejects a property outside the authenticated owned collection', async () => {
    renderApp(`/properties/${otherPropertyId}/rental-applications`)

    expect(await screen.findByRole('heading', { name: 'Property unavailable' })).toBeInTheDocument()
    expect(screen.getByText(/not in your authenticated property portfolio/)).toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Rental applications' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Harbour View Residence/ })).toBeInTheDocument()
  })

  it('exposes canonical viewing and application navigation from Manage Properties', async () => {
    const router = renderApp('/modules/manage-properties')

    expect(await screen.findByRole('heading', { name: 'My Properties' })).toBeInTheDocument()
    expect(screen.getByText('1 property listed')).toBeInTheDocument()
    const card = await screen.findByRole('article')
    expect(within(card).getByRole('heading', { name: property.title })).toBeInTheDocument()
    expect(within(card).getByText('18 Marine Drive, Colombo')).toBeInTheDocument()
    expect(within(card).getByText('Rs. 185,000')).toBeInTheDocument()
    expect(within(card).getByText('Available')).toBeInTheDocument()
    expect(within(card).getByText('Bedrooms').parentElement).toHaveTextContent('3')
    expect(within(card).getByText('Bathrooms').parentElement).toHaveTextContent('2')
    expect(within(card).getByRole('link', { name: 'View property' }))
      .toHaveAttribute('href', `/properties/${propertyId}`)
    expect(within(card).queryByRole('link', { name: 'Viewing Requests' })).not.toBeInTheDocument()
    expect(within(card).queryByRole('link', { name: 'Rental Applications' })).not.toBeInTheDocument()
    expect(within(card).queryByRole('link', { name: 'Edit' })).not.toBeInTheDocument()
    expect(within(card).queryByRole('button', { name: 'Delete' })).not.toBeInTheDocument()
    expect(within(card).queryByText('Parking')).not.toBeInTheDocument()
    expect(within(card).queryByRole('button', { name: /favorite|heart/i })).not.toBeInTheDocument()

    await userEvent.click(within(card).getByRole('link', { name: 'View property' }))
    expect(router.state.location.pathname).toBe(`/properties/${propertyId}`)
    expect(await screen.findByRole('heading', { name: property.title })).toBeInTheDocument()
    expect(screen.getAllByText('18 Marine Drive, Colombo')).toHaveLength(2)
    expect(screen.getByText('A real owned property fixture.')).toBeInTheDocument()
    expect(screen.getByText('Parking')).toBeInTheDocument()
    expect(screen.getByText('Available now')).toBeInTheDocument()
    expect(screen.queryByText('Property / land size')).not.toBeInTheDocument()
    expect(screen.getByText('Floor area: 1,450 sq ft')).toBeInTheDocument()
    expect(screen.getByText('Map preview unavailable')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Open in Google Maps/ }))
      .toHaveAttribute('href', expect.stringContaining('query=18+Marine+Drive%2C+Colombo'))
    const management = screen.getByRole('complementary', { name: 'Manage property' })
    expect(screen.queryByText('RentFlow AI')).not.toBeInTheDocument()
    expect(document.querySelector('.shared-topbar__title')).toBeNull()
    expect(screen.getByRole('link', { name: 'Notifications' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Profile for Nila Perera' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to properties' }))
      .toHaveAttribute('href', '/modules/manage-properties')
    expect(within(management).getByRole('link', { name: 'Viewing availability' }))
      .toHaveAttribute('href', `/properties/${propertyId}/viewing-availability`)
    expect(within(management).getByRole('link', { name: 'Viewing Requests' }))
      .toHaveAttribute('href', `/properties/${propertyId}/viewing-requests`)
    expect(within(management).getByRole('link', { name: 'Rental Applications' }))
      .toHaveAttribute('href', `/properties/${propertyId}/rental-applications`)
    expect(within(management).getByRole('link', { name: 'Edit' }))
      .toHaveAttribute('href', `/properties/${propertyId}/edit`)
    expect(within(management).getByRole('button', { name: 'Mark unavailable' })).toBeInTheDocument()
    expect(within(management).getByRole('button', { name: 'Delete' })).toBeInTheDocument()
  })

  it('keeps the public property read available to an authenticated tenant without landlord tools', async () => {
    renderApp(`/properties/${propertyId}`, {
      id: viewing.tenantId,
      fullName: 'Ravi Silva',
      email: 'ravi@example.com',
      role: 'Tenant',
    })

    expect(await screen.findByRole('heading', { name: property.title })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to properties' }))
      .toHaveAttribute('href', '/modules/properties')
    expect(screen.queryByRole('complementary', { name: 'Manage property' })).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'Viewing availability' })).not.toBeInTheDocument()
    expect(document.querySelector('.shared-topbar__title')).toHaveTextContent('RentFlow AI')

    const propertyRead = fetch.mock.calls.find(([url]) => (
      new URL(url, 'http://localhost').pathname === `/api/properties/${propertyId}`
    ))
    expect(propertyRead[1].headers.Authorization).toBeUndefined()
  })

  it('does not use public property details for an unavailable landlord property', async () => {
    renderApp(`/properties/${otherPropertyId}`)

    expect(await screen.findByRole('heading', { name: 'Property unavailable' })).toBeInTheDocument()
    expect(screen.getByText(/not in your authenticated property portfolio/)).toBeInTheDocument()
    expect(fetch.mock.calls.some(([url]) => (
      new URL(url, 'http://localhost').pathname === `/api/properties/${otherPropertyId}`
    ))).toBe(false)
    const ownedRead = fetch.mock.calls.find(([url]) => (
      new URL(url, 'http://localhost').pathname === '/api/properties/mine'
    ))
    expect(ownedRead[1].headers.Authorization).toBe('Bearer landlord-token')
  })

  it('shows toast feedback for property updates and deletion', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true)
    fetch.mockImplementation((url, options = {}) => {
      const path = new URL(url, 'http://localhost').pathname
      if (path === `/api/properties/${propertyId}` && options.method === 'PUT') {
        return Promise.resolve(json({ ...property, isAvailable: false }))
      }
      if (path === `/api/properties/${propertyId}` && options.method === 'DELETE') {
        return Promise.resolve(new Response(null, { status: 204 }))
      }
      if (path === `/api/properties/${propertyId}`) return Promise.resolve(json(property))
      if (path === '/api/properties/mine') return Promise.resolve(json([property]))
      if (path.startsWith(`/api/properties/${propertyId}/images`)) return Promise.resolve(json([]))
      return Promise.resolve(json([]))
    })
    renderApp(`/properties/${propertyId}`)

    await userEvent.click(await screen.findByRole('button', { name: 'Mark unavailable' }))

    const updateMessage = await screen.findByText('Harbour View Residence is now unavailable.')
    expect(updateMessage.closest('.property-toast')).toHaveClass('property-toast--success')
    expect(fetch).toHaveBeenCalledWith(
      expect.stringMatching(new RegExp(`/api/properties/${propertyId}$`)),
      expect.objectContaining({ method: 'PUT' }),
    )

    await userEvent.click(await screen.findByRole('button', { name: 'Delete' }))

    expect(confirm).toHaveBeenCalledWith(`Are you sure you want to permanently delete ${property.title}?`)
    const deleteMessage = await screen.findByText('Harbour View Residence was deleted successfully.')
    expect(deleteMessage.closest('.property-toast')).toHaveClass('property-toast--success')
    expect(fetch).toHaveBeenCalledWith(
      expect.stringMatching(new RegExp(`/api/properties/${propertyId}$`)),
      expect.objectContaining({ method: 'DELETE' }),
    )
  })

  it('keeps My Properties list-only and navigates to the dedicated create route', async () => {
    const router = renderApp('/modules/manage-properties')

    expect(await screen.findByRole('heading', { name: property.title })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Create Property' })).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Property title')).not.toBeInTheDocument()
    const addProperty = screen.getByRole('link', { name: '+ Add Property' })
    expect(addProperty).toHaveAttribute('href', '/properties/new')

    await userEvent.click(addProperty)

    expect(router.state.location.pathname).toBe('/properties/new')
    expect(screen.getByRole('heading', { name: 'Add Property' })).toBeInTheDocument()
    expect(screen.getByLabelText('Property title')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Create Property' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Continue' })).toBeInTheDocument()
  })

  it('filters the authenticated owned-property list by title or city on the client', async () => {
    renderApp('/modules/manage-properties')

    const search = await screen.findByLabelText('Search properties by title or city')
    expect(search).toHaveAttribute('placeholder', 'Search by property name or city...')
    await userEvent.type(search, 'hArBoUr')

    expect(screen.getByRole('heading', { name: property.title })).toBeInTheDocument()

    await userEvent.clear(search)
    await userEvent.type(search, 'kAnDy')

    expect(screen.getByRole('heading', { name: 'No matching properties' })).toBeInTheDocument()
    expect(screen.queryByRole('article')).not.toBeInTheDocument()

    await userEvent.clear(search)
    await userEvent.type(search, 'cOlOmBo')

    expect(await screen.findByRole('heading', { name: property.title })).toBeInTheDocument()
    expect(fetch.mock.calls.filter(([url]) =>
      new URL(url, 'http://localhost').pathname === '/api/properties/mine')).toHaveLength(1)
  })

  it('paginates six properties at a time and resets to page one after search', async () => {
    const portfolio = portfolioProperties(8)
    mockOwnedPropertyCollection(portfolio)
    renderApp('/modules/manage-properties')

    expect(await screen.findByText('8 properties listed')).toBeInTheDocument()
    expect(screen.getAllByRole('article')).toHaveLength(6)
    expect(screen.getByRole('heading', { name: 'Property 1' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Property 7' })).not.toBeInTheDocument()

    const pagination = screen.getByRole('navigation', { name: 'Property pagination' })
    expect(within(pagination).getByRole('button', { name: 'Previous' })).toBeDisabled()
    expect(within(pagination).getByRole('button', { name: 'Page 1' })).toHaveAttribute('aria-current', 'page')

    await userEvent.click(within(pagination).getByRole('button', { name: 'Next' }))

    expect(screen.getAllByRole('article')).toHaveLength(2)
    expect(screen.getByRole('heading', { name: 'Property 7' })).toBeInTheDocument()
    expect(within(pagination).getByRole('button', { name: 'Page 2' })).toHaveAttribute('aria-current', 'page')

    await userEvent.type(screen.getByLabelText('Search properties by title or city'), 'Colombo')

    expect(screen.getAllByRole('article')).toHaveLength(6)
    expect(screen.getByRole('heading', { name: 'Property 1' })).toBeInTheDocument()
    expect(within(pagination).getByRole('button', { name: 'Previous' })).toBeDisabled()
    expect(within(pagination).getByRole('button', { name: 'Page 1' })).toHaveAttribute('aria-current', 'page')
    expect(fetch.mock.calls.filter(([url]) =>
      new URL(url, 'http://localhost').pathname === '/api/properties/mine')).toHaveLength(1)
  })

  it('shows the compact zero-property state with the real owned count', async () => {
    mockOwnedPropertyCollection([])
    renderApp('/modules/manage-properties')

    expect(await screen.findByText('0 properties listed')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'No properties yet' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Add your first property' }))
      .toHaveAttribute('href', '/properties/new')
    expect(screen.queryByLabelText('Search properties by title or city')).not.toBeInTheDocument()
    expect(screen.queryByRole('navigation', { name: 'Property pagination' })).not.toBeInTheDocument()
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
      .toEqual(['/api/properties/mine', '/api/landlord/actions/summary'])
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
    expect(await screen.findByRole('button', { name: /Harbour View Residence/ })).toBeInTheDocument()
    expect(attempts).toBe(2)
  })
})
