import { act, cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import AppShell from './AppShell.jsx'
import { AuthContext } from '../../features/auth/useAuth.js'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import LandlordMaintenancePage from '../../features/maintenance/pages/LandlordMaintenancePage.jsx'

vi.mock('../../features/notifications/notificationsApi.js', () => ({ getUnreadCount: vi.fn().mockResolvedValue(8) }))
const user = { id: '11111111-1111-4111-8111-111111111111', fullName: 'Test Landlord', role: 'Landlord' }
const properties = [
  { id: '22222222-2222-4222-8222-222222222222', title: 'Port city residence' },
  { id: '33333333-3333-4333-8333-333333333333', title: 'Harbour view residences' },
  { id: '44444444-4444-4444-8444-444444444444', title: 'Quiet apartment' },
]
const summary = { maintenanceCount: 3, maintenanceByProperty: [{ propertyId: properties[0].id, count: 2 }, { propertyId: properties[1].id, count: 1 }], leaseCount: 2, paymentCount: 1 }
const json = (data) => new Response(JSON.stringify(data), { headers: { 'Content-Type': 'application/json' } })
function tree(role = 'Landlord', id = user.id, maintenance = false) {
  return <MemoryRouter initialEntries={['/modules/maintenance/landlord']}><AuthContext.Provider value={{ user: { ...user, role, id }, logout: vi.fn(), isAuthenticated: true }}>
    <Routes><Route element={<AppShell />}><Route path="*" element={maintenance ? <LandlordMaintenancePage /> : <p>Workspace</p>} /></Route></Routes>
  </AuthContext.Provider></MemoryRouter>
}
const show = (...args) => render(tree(...args))
beforeEach(() => {
  tokenStorage.setToken('landlord-token')
  vi.stubGlobal('fetch', vi.fn(async (url) => json(url.includes('/actions/summary') ? summary : url.includes('/properties/mine') ? properties : [])))
})
afterEach(() => { cleanup(); vi.unstubAllGlobals(); tokenStorage.clearToken() })

it('shows global action badges separately from the unread bell and keeps them after navigation clicks', async () => {
  show()
  const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
  expect(await within(nav).findByRole('link', { name: 'Maintenance, 3 pending' })).toBeInTheDocument()
  expect(within(nav).getByRole('link', { name: 'Pricing / Lease, 2 pending' })).toBeInTheDocument()
  expect(within(nav).getByRole('link', { name: 'Payments, 1 pending' })).toBeInTheDocument()
  expect(await screen.findByRole('link', { name: 'Notifications, 8 unread' })).toBeInTheDocument()
  await userEvent.click(within(nav).getByRole('link', { name: 'Maintenance, 3 pending' }))
  expect(await within(nav).findByRole('link', { name: 'Maintenance, 3 pending' })).toBeInTheDocument()
})

it('uses the same summary for per-property counts and excludes zero chips without per-property count calls', async () => {
  show('Landlord', user.id, true)
  const selector = await screen.findByRole('combobox', { name: 'Property' })
  expect(await within(selector).findByRole('option', { name: 'Port city residence [2]' })).toBeInTheDocument()
  expect(within(selector).getByRole('option', { name: 'Harbour view residences [1]' })).toBeInTheDocument()
  const counts = screen.getByRole('list', { name: 'Property maintenance actions' })
  expect(within(counts).getByLabelText('2 actions required')).toBeInTheDocument()
  expect(within(counts).getByRole('button', { name: 'Quiet apartment' }).querySelector('.shared-nav-link__pending')).toBeNull()
  expect(fetch.mock.calls.filter(([url]) => url.includes('/actions/summary'))).toHaveLength(1)
  expect(fetch.mock.calls.some(([url]) => url.includes(properties[1].id))).toBe(false)
})

it('hides zero badges and does not load Landlord counters for other roles', async () => {
  fetch.mockImplementation(async () => json({ maintenanceCount: 0, maintenanceByProperty: [], leaseCount: 0, paymentCount: 0 }))
  show()
  await act(async () => {})
  const maintenance = await screen.findByRole('link', { name: 'Maintenance' })
  expect(maintenance.querySelector('.shared-nav-link__pending')).toBeNull()
  cleanup(); fetch.mockClear()
  show('Tenant')
  await act(async () => {})
  expect(fetch.mock.calls.some(([url]) => url.includes('/actions/summary'))).toBe(false)
})

it('refreshes current work on window focus without replacing the unread bell count', async () => {
  let latest = summary
  fetch.mockImplementation(async () => json(latest))
  show()
  expect(await screen.findByRole('link', { name: 'Maintenance, 3 pending' })).toBeInTheDocument()
  latest = { maintenanceCount: 0, maintenanceByProperty: [], leaseCount: 0, paymentCount: 0 }
  await act(async () => window.dispatchEvent(new Event('focus')))
  expect(await screen.findByRole('link', { name: 'Maintenance' })).toBeInTheDocument()
  expect(screen.getByRole('link', { name: 'Notifications, 8 unread' })).toBeInTheDocument()
  expect(fetch.mock.calls.filter(([url]) => url.includes('/actions/summary'))).toHaveLength(2)
})

it('ignores the previous Landlord response after an identity change', async () => {
  let resolveOld
  fetch.mockImplementationOnce(() => new Promise((resolve) => { resolveOld = resolve }))
    .mockImplementation(async () => json({ maintenanceCount: 0, maintenanceByProperty: [], leaseCount: 0, paymentCount: 0 }))
  const view = show()
  view.rerender(tree('Landlord', '55555555-5555-4555-8555-555555555555'))
  await act(async () => {})
  await act(async () => resolveOld(json(summary)))
  expect(screen.getByRole('link', { name: 'Maintenance' })).toBeInTheDocument()
  expect(screen.queryByRole('link', { name: 'Maintenance, 3 pending' })).not.toBeInTheDocument()
})
