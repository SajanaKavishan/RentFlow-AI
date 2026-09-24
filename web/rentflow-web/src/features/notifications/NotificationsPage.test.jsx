import { act, cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { AuthContext } from '../auth/useAuth.js'
import { tokenStorage } from '../../core/auth/tokenStorage.js'

const user = { id: 'session-user', fullName: 'Taylor Example', email: 'taylor@example.com', role: 'Tenant' }
const first = { id: '11111111-1111-1111-1111-111111111111', eventType: 'viewing.approved', relatedResourceType: 'ViewingRequest', relatedResourceId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', title: 'Viewing confirmed', message: 'Your viewing is confirmed for Tuesday.', createdAt: '2026-09-20T10:00:00Z', isRead: false, readAt: null }
const second = { id: '22222222-2222-2222-2222-222222222222', eventType: 'rental_application.approved', relatedResourceType: 'RentalApplication', relatedResourceId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', title: 'Application updated', message: 'Your application was updated.', createdAt: '2026-09-19T10:00:00Z', isRead: true, readAt: '2026-09-19T11:00:00Z' }
const activation = { id: '33333333-3333-4333-8333-333333333333', eventType: 'maintenance_technician.activated', relatedResourceType: 'MaintenanceTechnician', relatedResourceId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', title: 'Technician account activated', message: 'The Maintenance Technician account you provisioned is now active.', createdAt: '2026-09-21T10:00:00Z', isRead: false, readAt: null }
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const page = (items = [first, second], number = 1, totalPages = 1) => ({ items, pagination: { page: number, pageSize: 20, totalCount: items.length, totalPages, hasNextPage: number < totalPages, hasPreviousPage: number > 1 } })

function renderApp(role = 'Tenant', path = '/notifications') {
  const session = { user: { ...user, role }, isAuthenticated: true, isLoading: false, logout: vi.fn() }
  return render(<MemoryRouter initialEntries={[path]}><AuthContext.Provider value={session}><App /></AuthContext.Provider></MemoryRouter>)
}

beforeEach(() => {
  tokenStorage.setToken('session-token')
  vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
  vi.stubGlobal('fetch', vi.fn((url) => Promise.resolve(json(url.includes('unread-count') ? { unreadCount: 1 } : page()))))
})
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('shared notifications UI', () => {
  it.each(['Tenant', 'Landlord', 'MaintenanceTechnician', 'Admin'])('shows the bell and real count for %s', async (role) => {
    renderApp(role)
    const bell = screen.getByRole('link', { name: /^Notifications(?:, \d+ unread)?$/ })
    await waitFor(() => expect(bell).toHaveAccessibleName('Notifications, 1 unread'))
    expect(within(bell).getByText('1')).toBeInTheDocument()
    expect(await screen.findByText(first.title)).toBeInTheDocument()
    expect(screen.getByText(first.message)).toBeInTheDocument()
    const list = screen.getByRole('region', { name: 'Notification list' })
    expect(within(list).getAllByText('Unread')).toHaveLength(1)
    expect(within(list).getAllByText('Read')).toHaveLength(1)
    expect(screen.getAllByText(first.message)).toHaveLength(1)
    expect(document.querySelector('.notifications-detail')).not.toBeInTheDocument()
    expect(screen.getByText(first.message).closest('button').querySelector('time')).toHaveAttribute('dateTime', first.createdAt)
  })

  it('hides the badge when the count is zero or unavailable', async () => {
    fetch.mockImplementation((url) => Promise.resolve(json(url.includes('unread-count') ? { unreadCount: 0 } : page())))
    const view = renderApp()
    await screen.findByText(first.title)
    await waitFor(() => expect(screen.getByRole('link', { name: 'Notifications' })).toBeInTheDocument())
    view.unmount()
    fetch.mockImplementation((url) => Promise.resolve(url.includes('unread-count') ? json({}, 500) : json(page())))
    renderApp()
    await screen.findByText(first.title)
    expect(screen.getByRole('link', { name: 'Notifications' })).toBeInTheDocument()
  })

  it('refreshes the count when returning to the dashboard and inbox', async () => {
    let countRequests = 0
    fetch.mockImplementation((url) => Promise.resolve(json(url.includes('unread-count')
      ? { unreadCount: ++countRequests } : page())))
    renderApp('Admin', '/profile')
    const bell = screen.getByRole('link', { name: /^Notifications(?:, \d+ unread)?$/ })
    await waitFor(() => expect(bell).toHaveAccessibleName('Notifications, 1 unread'))
    await userEvent.click(bell)
    await userEvent.click(await screen.findByRole('link', { name: /See all notifications/ }))
    await waitFor(() => expect(bell).toHaveAccessibleName('Notifications, 2 unread'))
    await userEvent.click(screen.getByRole('link', { name: 'Dashboard' }))
    await waitFor(() => expect(bell).toHaveAccessibleName('Notifications, 3 unread'))
  })

  it('clears the previous inbox when the authenticated user changes', async () => {
    let activePage = page([first])
    fetch.mockImplementation((url) => Promise.resolve(json(url.includes('unread-count')
      ? { unreadCount: 0 } : activePage)))
    const session = (id) => ({ user: { ...user, id, role: 'Admin' }, isAuthenticated: true, isLoading: false, logout: vi.fn() })
    const view = render(<MemoryRouter initialEntries={['/notifications']}><AuthContext.Provider value={session('first-user')}><App /></AuthContext.Provider></MemoryRouter>)
    expect(await screen.findByRole('button', { name: /Viewing confirmed/ })).toBeInTheDocument()
    activePage = page([second])
    view.rerender(<MemoryRouter initialEntries={['/notifications']}><AuthContext.Provider value={session('second-user')}><App /></AuthContext.Provider></MemoryRouter>)
    expect(screen.queryByRole('button', { name: /Viewing confirmed/ })).not.toBeInTheDocument()
    expect(await screen.findByRole('button', { name: /Application updated/ })).toBeInTheDocument()
  })

  it('marks unread only after PATCH succeeds and does not PATCH it again', async () => {
    let completePatch
    fetch.mockImplementation((url, options) => {
      if (options?.method === 'PATCH') return new Promise((resolve) => { completePatch = resolve })
      return Promise.resolve(json(url.includes('unread-count') ? { unreadCount: fetch.mock.calls.some(([, opts]) => opts?.method === 'PATCH') ? 0 : 1 } : page()))
    })
    renderApp()
    const bell = screen.getByRole('link', { name: /^Notifications(?:, \d+ unread)?$/ })
    await waitFor(() => expect(bell).toHaveAccessibleName('Notifications, 1 unread'))
    const unread = await screen.findByRole('button', { name: /Viewing confirmed/ })
    await userEvent.click(unread)
    expect(unread).toHaveAttribute('aria-busy', 'true')
    expect(unread).toHaveTextContent('Unread')
    expect(bell).toHaveTextContent('1')
    await act(async () => { completePatch(json({ ...first, isRead: true, readAt: '2026-09-22T10:00:00Z' })) })
    await waitFor(() => expect(unread).toHaveTextContent('Read'))
    await waitFor(() => expect(bell).toHaveAccessibleName('Notifications'))
    await userEvent.click(unread)
    expect(fetch.mock.calls.filter(([, options]) => options?.method === 'PATCH')).toHaveLength(1)
  })

  it('retains unread state and count on PATCH failure, then retries on selection', async () => {
    let patches = 0
    fetch.mockImplementation((url, options) => {
      if (options?.method === 'PATCH') return Promise.resolve(++patches === 1 ? json({ message: 'Try again later.' }, 503) : json({ ...first, isRead: true }))
      return Promise.resolve(json(url.includes('unread-count') ? { unreadCount: patches > 1 ? 0 : 1 } : page()))
    })
    renderApp()
    const unread = await screen.findByRole('button', { name: /Viewing confirmed/ })
    await waitFor(() => expect(screen.getByRole('link', { name: /^Notifications(?:, \d+ unread)?$/ })).toHaveAccessibleName('Notifications, 1 unread'))
    await userEvent.click(unread)
    expect(await screen.findByRole('alert')).toHaveTextContent('Notification could not be marked as read.')
    expect(unread).toHaveTextContent('Unread')
    expect(screen.getByRole('link', { name: 'Notifications, 1 unread' })).toBeInTheDocument()
    await userEvent.click(unread)
    await waitFor(() => expect(unread).toHaveTextContent('Read'))
    expect(patches).toBe(2)
  })

  it('keeps a read failure attached to its notification when another item is selected', async () => {
    let failPatch
    fetch.mockImplementation((url, options) => options?.method === 'PATCH'
      ? new Promise((resolve) => { failPatch = resolve })
      : Promise.resolve(json(url.includes('unread-count') ? { unreadCount: 1 } : page())))
    renderApp()
    const unread = await screen.findByRole('button', { name: /Viewing confirmed/ })
    await userEvent.click(unread)
    await userEvent.click(screen.getByRole('button', { name: /Application updated/ }))
    await act(async () => { failPatch(json({ message: 'Unavailable' }, 503)) })
    expect(within(unread).getByRole('alert')).toHaveTextContent('Notification could not be marked as read.')
    expect(unread).toHaveTextContent('Unread')
  })

  it('filters the current page by read state and supported notification type', async () => {
    fetch.mockImplementation((url) => Promise.resolve(json(url.includes('unread-count') ? { unreadCount: 2 } : page([first, second, activation]))))
    renderApp('Admin')
    await screen.findByRole('button', { name: /Viewing confirmed/ })
    expect(screen.getByText('Filters apply to the 3 notifications loaded on this page.')).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Unread' }))
    expect(screen.getByRole('button', { name: /Viewing confirmed/ })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Application updated/ })).not.toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Read' }))
    expect(screen.queryByRole('button', { name: /Viewing confirmed/ })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Application updated/ })).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'All' }))
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Notification type' }), 'viewing.approved')
    expect(screen.getByRole('button', { name: /Viewing confirmed/ })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Application updated/ })).not.toBeInTheDocument()

    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Notification type' }), 'viewing.rejected')
    const noMatchHeading = screen.getByRole('heading', { name: 'No matching notifications on this page' })
    const noMatchState = noMatchHeading.closest('.notifications-feedback')
    expect(noMatchState).toHaveTextContent('No matching notifications on this page')
    expect(noMatchState).not.toHaveTextContent('Try another filter or move to a different page.')
    expect(within(noMatchState).queryByRole('button')).not.toBeInTheDocument()
    expect(noMatchState.querySelector('svg')).toBeNull()
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Notification type' }), 'all')
    expect(screen.getByRole('button', { name: /Application updated/ })).toBeInTheDocument()

    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Notification type' }), 'maintenance_technician.activated')
    const activationItem = screen.getByRole('button', { name: /Technician account activated/ })
    expect(activationItem).toHaveTextContent('Technician activation')
    expect(screen.queryByRole('button', { name: /Viewing confirmed/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Application updated/ })).not.toBeInTheDocument()
    expect(screen.getByText('Filters apply to the 3 notifications loaded on this page.')).toBeInTheDocument()
  })

  it('handles loading, error, retry, empty, refresh and pagination', async () => {
    let finishFirst
    let pages = 0
    fetch.mockImplementation((url) => {
      if (url.includes('unread-count')) return Promise.resolve(json({ unreadCount: 0 }))
      pages++
      if (pages === 1) return new Promise((resolve) => { finishFirst = resolve })
      if (pages === 2) return Promise.resolve(json({ message: 'Unavailable' }, 500))
      if (pages === 3) return Promise.resolve(json(page([first], 1, 2)))
      if (pages === 4) return Promise.resolve(json(page([second], 2, 2)))
      return Promise.resolve(json(page([], 1, 0)))
    })
    renderApp()
    expect(screen.getByRole('status')).toHaveTextContent('Loading notifications')
    await act(async () => { finishFirst(json({ message: 'Unavailable' }, 500)) })
    expect(await screen.findByRole('alert')).toHaveTextContent('Notifications could not be loaded.')
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByRole('alert')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByRole('button', { name: /Viewing confirmed/ })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Next' }))
    expect(await screen.findByRole('button', { name: /Application updated/ })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Next' })).toBeDisabled()
    await userEvent.click(screen.getByRole('button', { name: 'Refresh' }))
    expect(await screen.findByRole('heading', { name: 'No notifications yet' })).toBeInTheDocument()
  })
})
