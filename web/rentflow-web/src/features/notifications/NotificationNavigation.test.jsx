import { act, cleanup, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { AuthContext } from '../auth/useAuth.js'
import { tokenStorage } from '../../core/auth/tokenStorage.js'

const applicationId = '11111111-1111-1111-1111-111111111111'
const viewingId = '22222222-2222-2222-2222-222222222222'
const propertyId = '33333333-3333-3333-3333-333333333333'
const notificationId = '44444444-4444-4444-4444-444444444444'
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const notification = (type, id, isRead = true) => ({
  id: notificationId, title: 'An update', message: 'Open the related record.',
  createdAt: '2026-09-20T10:00:00Z', isRead, readAt: isRead ? '2026-09-20T11:00:00Z' : null,
  eventType: type === 'ViewingRequest' ? 'viewing.approved' : 'rental_application.approved',
  relatedResourceType: type, relatedResourceId: id,
})
const page = (item) => ({ items: [item], pagination: {
  page: 1, pageSize: 20, totalCount: 1, totalPages: 1, hasNextPage: false, hasPreviousPage: false,
} })
const application = { id: applicationId, propertyId, tenantId: '55555555-5555-5555-5555-555555555555',
  status: 1, moveInDate: '2026-10-01', monthlyIncome: 2500, occupation: 'Designer',
  numberOfOccupants: 2, tenantNote: 'Please review', landlordResponse: null,
  createdAt: '2026-09-20T10:00:00Z', submittedAt: '2026-09-20T10:00:00Z' }
const viewing = { id: viewingId, propertyId, tenantId: application.tenantId,
  status: 0, requestedDateTime: '2026-10-01T10:00:00Z', tenantMessage: 'Morning works',
  landlordResponse: null, createdAt: '2026-09-20T10:00:00Z' }

function renderInbox(role) {
  const session = { user: { id: application.tenantId, fullName: 'Taylor Example', email: 'taylor@example.com', role },
    isAuthenticated: true, isLoading: false, logout: vi.fn() }
  render(<MemoryRouter initialEntries={['/notifications']}><AuthContext.Provider value={session}><App /></AuthContext.Provider></MemoryRouter>)
}

function mockEndpoints(item, resource = application, resourceStatus = 200) {
  vi.stubGlobal('fetch', vi.fn((url, options) => {
    const path = new URL(url, 'http://localhost').pathname
    if (path === '/api/notifications/unread-count') return Promise.resolve(json({ unreadCount: item.isRead ? 0 : 1 }))
    if (path === '/api/notifications') return Promise.resolve(json(page(item)))
    if (path === '/api/viewings') return Promise.resolve(json(resource.id === viewingId ? [resource] : []))
    if (options?.method === 'PATCH') return Promise.resolve(json({ ...item, isRead: true, readAt: '2026-09-22T10:00:00Z' }))
    if (path === `/api/rental-applications/${applicationId}` || path === `/api/viewings/${viewingId}`) {
      return Promise.resolve(json(resourceStatus === 200 ? resource : { message: 'Unavailable' }, resourceStatus))
    }
    throw new Error(`Unexpected request: ${path}`)
  }))
}

beforeEach(() => {
  tokenStorage.setToken('session-token')
  vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
})
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('notification resource navigation', () => {
  it('opens a read tenant application through the authorized detail endpoint without PATCH', async () => {
    mockEndpoints(notification('RentalApplication', applicationId))
    renderInbox('Tenant')
    await userEvent.click(await screen.findByRole('button', { name: /An update/ }))
    expect(await screen.findByRole('heading', { name: 'Rental application' })).toBeInTheDocument()
    expect(await screen.findByText('Designer')).toBeInTheDocument()
    expect(fetch.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(0)
    expect(fetch.mock.calls.filter(([url]) => new URL(url, 'http://localhost').pathname === `/api/rental-applications/${applicationId}`)).toHaveLength(2)
    expect(fetch.mock.calls.every(([, options]) => options.headers.Authorization === 'Bearer session-token')).toBe(true)
  })

  it('waits for read confirmation before opening the landlord application card', async () => {
    const item = notification('RentalApplication', applicationId, false)
    let finishPatch
    mockEndpoints(item)
    const normalFetch = fetch.getMockImplementation()
    fetch.mockImplementation((url, options) => options?.method === 'PATCH'
      ? new Promise((resolve) => { finishPatch = resolve }) : normalFetch(url, options))
    renderInbox('Landlord')
    await userEvent.click(await screen.findByRole('button', { name: /An update/ }))
    expect(fetch.mock.calls.some(([url]) => new URL(url, 'http://localhost').pathname === `/api/rental-applications/${applicationId}`)).toBe(false)
    await act(async () => { finishPatch(json({ ...item, isRead: true, readAt: '2026-09-22T10:00:00Z' })) })
    expect(await screen.findByText('Move in Oct 1, 2026')).toBeInTheDocument()
    expect(fetch.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(1)
  })

  it('opens the existing landlord viewing details and action card after authorized fetch', async () => {
    mockEndpoints(notification('ViewingRequest', viewingId), viewing)
    renderInbox('Landlord')
    await userEvent.click(await screen.findByRole('button', { name: /An update/ }))
    expect(await screen.findByRole('article', { name: `Viewing request ${viewingId}` })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Approve request' })).toBeInTheDocument()
  })

  it('opens the tenant My Viewings destination without claiming a selected viewing', async () => {
    mockEndpoints(notification('ViewingRequest', viewingId), viewing)
    renderInbox('Tenant')
    await userEvent.click(await screen.findByRole('button', { name: /An update/ }))
    expect(await screen.findByRole('heading', { name: 'My Viewings' })).toBeInTheDocument()
    expect(await screen.findByText(propertyId)).toBeInTheDocument()
    expect(screen.queryByText(viewingId)).not.toBeInTheDocument()
    expect(fetch.mock.calls.filter(([url]) => new URL(url, 'http://localhost').pathname === `/api/viewings/${viewingId}`)).toHaveLength(1)
  })

  it.each([403, 404, 503])('keeps the inbox open when the resource fetch returns %s', async (status) => {
    mockEndpoints(notification('RentalApplication', applicationId), application, status)
    renderInbox('Tenant')
    await userEvent.click(await screen.findByRole('button', { name: /An update/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent(status === 503 ? 'could not be opened' : 'unavailable or you do not have access')
    expect(screen.getByRole('heading', { name: 'Notifications' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Rental application' })).not.toBeInTheDocument()
  })

  it('keeps the inbox open when the resource network request fails', async () => {
    mockEndpoints(notification('ViewingRequest', viewingId), viewing)
    const normalFetch = fetch.getMockImplementation()
    fetch.mockImplementation((url, options) => new URL(url, 'http://localhost').pathname === `/api/viewings/${viewingId}`
      ? Promise.reject(new Error('offline')) : normalFetch(url, options))
    renderInbox('Landlord')
    await userEvent.click(await screen.findByRole('button', { name: /An update/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent('could not be opened')
    expect(screen.getByRole('heading', { name: 'Notifications' })).toBeInTheDocument()
  })

  it('does not fetch or navigate when marking an unread item fails', async () => {
    const item = notification('RentalApplication', applicationId, false)
    mockEndpoints(item)
    const normalFetch = fetch.getMockImplementation()
    fetch.mockImplementation((url, options) => options?.method === 'PATCH'
      ? Promise.resolve(json({ message: 'Unavailable' }, 503)) : normalFetch(url, options))
    renderInbox('Landlord')
    await userEvent.click(await screen.findByRole('button', { name: /An update/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Notification could not be marked as read')
    expect(fetch.mock.calls.some(([url]) => new URL(url, 'http://localhost').pathname === `/api/rental-applications/${applicationId}`)).toBe(false)
    expect(screen.getByRole('heading', { name: 'Notifications' })).toBeInTheDocument()
  })

  it('keeps unsupported resources in the inbox without guessing from the message', async () => {
    mockEndpoints(notification('UnknownResource', applicationId))
    renderInbox('Tenant')
    await userEvent.click(await screen.findByRole('button', { name: /An update/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent('no supported destination')
    expect(fetch.mock.calls.some(([url]) => new URL(url, 'http://localhost').pathname === `/api/rental-applications/${applicationId}`)).toBe(false)
  })

  it('does not open another record when the authorized response ID differs', async () => {
    mockEndpoints(notification('ViewingRequest', viewingId), { ...viewing, id: applicationId })
    renderInbox('Landlord')
    await userEvent.click(await screen.findByRole('button', { name: /An update/ }))
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('could not be verified'))
    expect(screen.queryByRole('article', { name: `Viewing request ${applicationId}` })).not.toBeInTheDocument()
  })

  it('shows a safe detail error if a record disappears after the initial authorized fetch', async () => {
    mockEndpoints(notification('RentalApplication', applicationId))
    const normalFetch = fetch.getMockImplementation()
    let resourceReads = 0
    fetch.mockImplementation((url, options) => {
      if (new URL(url, 'http://localhost').pathname === `/api/rental-applications/${applicationId}`) {
        return Promise.resolve(++resourceReads === 1 ? json(application) : json({ message: 'Gone' }, 404))
      }
      return normalFetch(url, options)
    })
    renderInbox('Tenant')
    await userEvent.click(await screen.findByRole('button', { name: /An update/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Related record unavailable')
    expect(screen.queryByText('Designer')).not.toBeInTheDocument()
    expect(resourceReads).toBe(2)
  })
})
