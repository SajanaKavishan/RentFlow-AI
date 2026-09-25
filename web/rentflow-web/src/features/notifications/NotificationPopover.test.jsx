import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { AuthContext } from '../auth/useAuth.js'
import { tokenStorage } from '../../core/auth/tokenStorage.js'

const first = {
  id: '11111111-1111-1111-1111-111111111111',
  eventType: 'viewing.approved',
  relatedResourceType: 'ViewingRequest',
  relatedResourceId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  title: 'Viewing confirmed',
  message: 'Your viewing is confirmed for Tuesday.',
  createdAt: '2026-09-20T10:00:00Z',
  isRead: false,
  readAt: null,
}
const second = {
  ...first,
  id: '22222222-2222-2222-2222-222222222222',
  title: 'Second account update',
  isRead: true,
  readAt: '2026-09-20T11:00:00Z',
}
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const page = (items) => ({ items, pagination: { page: 1, pageSize: 5, totalCount: items.length, totalPages: items.length ? 1 : 0, hasNextPage: false, hasPreviousPage: false } })
const preferences = { viewingUpdatesEnabled: true, rentalApplicationUpdatesEnabled: true, accountSecurityUpdatesEnabled: true }
const session = (id = 'first-user') => ({ user: { id, fullName: 'Taylor Example', email: 'taylor@example.com', role: 'Tenant' }, isAuthenticated: true, isLoading: false, logout: vi.fn() })

function renderApp(auth = session()) {
  return render(<MemoryRouter initialEntries={['/profile']}><AuthContext.Provider value={auth}><App /></AuthContext.Provider></MemoryRouter>)
}

beforeEach(() => {
  tokenStorage.setToken('session-token')
  vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
})
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('notification bell preview', () => {
  it('loads recent recipient-scoped notifications and closes after See all navigation', async () => {
    vi.stubGlobal('fetch', vi.fn((url) => {
      const request = new URL(url, 'http://localhost')
      if (request.pathname === '/api/notification-preferences') return Promise.resolve(json(preferences))
      if (request.pathname === '/api/notifications/unread-count') return Promise.resolve(json({ unreadCount: 1 }))
      if (request.pathname === '/api/notifications') return Promise.resolve(json(page([first])))
      throw new Error(`Unexpected request: ${request.pathname}`)
    }))
    renderApp()
    const bell = screen.getByRole('link', { name: /^Notifications(?:, \d+ unread)?$/ })
    await userEvent.click(bell)
    const dialog = await screen.findByRole('dialog', { name: 'Recent notifications' })
    expect(within(dialog).getByText(first.message)).toBeInTheDocument()
    expect(within(dialog).getByText('Viewing approved')).toBeInTheDocument()
    const previewRequest = fetch.mock.calls.map(([url]) => new URL(url, 'http://localhost')).find((url) => url.pathname === '/api/notifications' && url.searchParams.get('pageSize') === '5')
    expect(previewRequest.searchParams.get('page')).toBe('1')
    expect(previewRequest.searchParams.has('userId')).toBe(false)
    expect(previewRequest.searchParams.has('recipientId')).toBe(false)

    await userEvent.click(within(dialog).getByRole('link', { name: /See all notifications/ }))
    expect(screen.queryByRole('dialog', { name: 'Recent notifications' })).not.toBeInTheDocument()
    expect(await screen.findByRole('heading', { name: 'Notifications' })).toBeInTheDocument()
  })

  it('supports focus, Escape, outside click, and API-confirmed mark as read', async () => {
    let read = false
    vi.stubGlobal('fetch', vi.fn((url, options) => {
      const path = new URL(url, 'http://localhost').pathname
      if (path === '/api/notification-preferences') return Promise.resolve(json(preferences))
      if (path === '/api/notifications/unread-count') return Promise.resolve(json({ unreadCount: read ? 0 : 1 }))
      if (path === '/api/notifications') return Promise.resolve(json(page([{ ...first, isRead: read, readAt: read ? '2026-09-22T10:00:00Z' : null }])))
      if (options?.method === 'PATCH') { read = true; return Promise.resolve(json({ ...first, isRead: true, readAt: '2026-09-22T10:00:00Z' })) }
      throw new Error(`Unexpected request: ${path}`)
    }))
    renderApp()
    const bell = screen.getByRole('link', { name: /^Notifications(?:, \d+ unread)?$/ })
    await userEvent.click(bell)
    const dialog = await screen.findByRole('dialog', { name: 'Recent notifications' })
    expect(dialog).toHaveFocus()
    await userEvent.click(within(dialog).getByRole('button', { name: 'Mark as read' }))
    await waitFor(() => expect(within(dialog).getByText('Read')).toBeInTheDocument())
    expect(fetch.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(1)
    await waitFor(() => expect(bell).toHaveAccessibleName('Notifications'))

    await userEvent.keyboard('{Escape}')
    expect(screen.queryByRole('dialog', { name: 'Recent notifications' })).not.toBeInTheDocument()
    expect(bell).toHaveFocus()
    await userEvent.click(bell)
    await screen.findByRole('dialog', { name: 'Recent notifications' })
    fireEvent.mouseDown(document.body)
    expect(screen.queryByRole('dialog', { name: 'Recent notifications' })).not.toBeInTheDocument()
  })

  it('shows loading, error with retry, and empty states', async () => {
    let finishRequest
    let attempts = 0
    vi.stubGlobal('fetch', vi.fn((url) => {
      const path = new URL(url, 'http://localhost').pathname
      if (path === '/api/notification-preferences') return Promise.resolve(json(preferences))
      if (path === '/api/notifications/unread-count') return Promise.resolve(json({ unreadCount: 0 }))
      attempts++
      if (attempts === 1) return new Promise((resolve) => { finishRequest = resolve })
      return Promise.resolve(json(page([])))
    }))
    renderApp()
    await userEvent.click(screen.getByRole('link', { name: 'Notifications' }))
    expect(screen.getByRole('status')).toHaveTextContent('Loading notifications')
    await act(async () => { finishRequest(json({ message: 'Unavailable' }, 500)) })
    expect(await screen.findByRole('alert')).toHaveTextContent('Notifications could not be loaded')
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByText('No notifications yet')).toBeInTheDocument()
  })

  it('clears popup content and ignores stale results when the authenticated account changes', async () => {
    let activeItems = [first]
    vi.stubGlobal('fetch', vi.fn((url) => {
      const path = new URL(url, 'http://localhost').pathname
      if (path === '/api/notification-preferences') return Promise.resolve(json(preferences))
      return Promise.resolve(json(path === '/api/notifications/unread-count' ? { unreadCount: 0 } : page(activeItems)))
    }))
    const view = renderApp(session('first-user'))
    await userEvent.click(screen.getByRole('link', { name: 'Notifications' }))
    expect(await screen.findByText(first.title)).toBeInTheDocument()
    activeItems = [second]
    view.rerender(<MemoryRouter initialEntries={['/profile']}><AuthContext.Provider value={session('second-user')}><App /></AuthContext.Provider></MemoryRouter>)
    expect(screen.queryByRole('dialog', { name: 'Recent notifications' })).not.toBeInTheDocument()
    expect(screen.queryByText(first.title)).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('link', { name: 'Notifications' }))
    expect(await screen.findByText(second.title)).toBeInTheDocument()
    expect(screen.queryByText(first.title)).not.toBeInTheDocument()
  })
})
