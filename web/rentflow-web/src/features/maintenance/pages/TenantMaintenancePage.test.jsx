import { cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { AuthContext } from '../../auth/useAuth.js'
import { tokenStorage } from '../../../core/auth/tokenStorage.js'
import TenantMaintenancePage from './TenantMaintenancePage.jsx'

const tenantId = '11111111-1111-4111-8111-111111111111'
const propertyId = '22222222-2222-4222-8222-222222222222'
const oldId = '33333333-3333-4333-8333-333333333333'
const newId = '44444444-4444-4444-8444-444444444444'
const technicianId = '55555555-5555-4555-8555-555555555555'
const request = (id, extra = {}) => ({ id, tenantId, propertyId, propertyTitle: 'Port city residence',
  referenceCode: id === oldId ? 'MR-0000000000000001' : 'MR-0000000000000002', title: 'Leaking sink',
  description: 'The sink is leaking.', category: 0, priority: 1, status: 0,
  preferredAccessWindow: 'Morning', createdAt: id === oldId ? '2026-09-01T10:00:00Z' : '2026-10-01T10:00:00Z', ...extra })
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
let requests, attachments, history, estimate

function renderPage() {
  return render(<MemoryRouter><AuthContext.Provider value={{ user: { id: tenantId, role: 'Tenant' } }}>
    <TenantMaintenancePage />
  </AuthContext.Provider></MemoryRouter>)
}

beforeEach(() => {
  tokenStorage.setToken('tenant-token')
  requests = []
  attachments = []
  history = [{ id: 'history-1', toStatus: 0, changedAt: '2026-10-01T10:00:00Z', changedByUserId: technicianId }]
  estimate = null
  vi.stubGlobal('fetch', vi.fn(async (url) => {
    const path = new URL(url, 'http://localhost').pathname
    if (path === `/api/maintenance-requests/tenant/${tenantId}`) return json(requests)
    if (path.endsWith('/attachments')) return json(attachments)
    if (path.includes('/attachments/')) return new Response(new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]), { headers: { 'Content-Type': 'image/png' } })
    if (path.endsWith('/history')) return json(history)
    if (path.endsWith('/estimates/latest')) return estimate ? json(estimate) : new Response(null, { status: 204 })
    const item = requests.find((item) => path.endsWith(`/${item.id}`))
    if (item) return json(item)
    throw new Error(`Unexpected request: ${path}`)
  }))
  vi.stubGlobal('URL', class extends URL {
    static createObjectURL = vi.fn(() => 'blob:maintenance-photo')
    static revokeObjectURL = vi.fn()
  })
})
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.restoreAllMocks(); vi.unstubAllGlobals() })

describe('tenant maintenance request flow', () => {
  it('shows technician details and actual progress inside each newest-first request card without GUIDs', async () => {
    requests = [request(oldId), request(newId, { status: 2, technicianId, assignedTechnicianName: 'Morgan', assignedTechnicianContactPhone: '+94771234567', triageNotes: 'Internal triage', assignmentNotes: 'Internal assignment' })]
    const { container } = renderPage()
    const list = await screen.findByRole('region', { name: 'Your requests' })
    const cards = within(list).getAllByRole('article')
    expect(cards[0]).toHaveAccessibleName('MR-0000000000000002')
    expect(cards[1]).toHaveAccessibleName('MR-0000000000000001')
    expect(cards[0]).toHaveTextContent('Port city residence')
    expect(cards[0]).toHaveTextContent('Assigned')
    expect(cards[0]).toHaveTextContent('Plumbing')
    expect(cards[0]).toHaveTextContent('Normal')
    expect(await within(cards[0]).findByText('Morgan')).toBeInTheDocument()
    expect(within(cards[0]).getByText('+94771234567')).toBeInTheDocument()
    expect(within(cards[0]).getByRole('region', { name: 'Request progress' })).toBeInTheDocument()
    expect(within(cards[1]).getByRole('region', { name: 'Request progress' })).toBeInTheDocument()
    expect(within(cards[1]).queryByText('Morgan')).not.toBeInTheDocument()
    await userEvent.click(await within(cards[0]).findByText('Request summary', { selector: 'summary' }))
    expect(within(cards[0]).getByText('Morning 8-12', { selector: 'dd' })).toBeInTheDocument()
    expect(await within(cards[0]).findByRole('region', { name: 'Status history' })).toHaveTextContent('Submitted')
    for (const id of [tenantId, propertyId, oldId, newId, technicianId]) expect(container).not.toHaveTextContent(id)
    expect(screen.queryByText(/Internal triage|Internal assignment/)).not.toBeInTheDocument()
    expect(fetch.mock.calls.some(([url]) => /technicians|coordination-workflows|properties/.test(url))).toBe(false)
  })

  it('is read-only with photos, safe estimate information and mobile guidance', async () => {
    requests = [request(newId)]
    attachments = [{ id: 'photo-1', fileName: 'sink.png', contentType: 'image/png' }]
    estimate = { id: 'private-estimate-id', technicianId, status: 3, versionNumber: 2, totalCost: 1250, createdAt: '2026-10-01T10:00:00Z', notes: 'Private estimate notes', reviewNotes: 'Staff review' }
    const { container } = renderPage()
    await userEvent.click(await screen.findByText('Request summary', { selector: 'summary' }))
    expect(await screen.findByRole('img', { name: 'sink.png' })).toHaveAttribute('src', 'blob:maintenance-photo')
    const latest = await screen.findByRole('region', { name: 'Latest estimate' })
    expect(latest).toHaveTextContent('Approved')
    expect(latest).toHaveTextContent('1,250.00')
    expect(container).not.toHaveTextContent('private-estimate-id')
    expect(container).not.toHaveTextContent('Private estimate notes')
    expect(container).not.toHaveTextContent('Staff review')
    expect(screen.getByText('Use the RentFlow mobile app to submit a new maintenance request.')).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Report an issue' })).not.toBeInTheDocument()
    expect(container.querySelector('form, input, textarea')).toBeNull()
    expect(within(screen.getByRole('article')).queryByRole('button', { name: /^(Submit|Create|Edit|Upload|Remove|Approve|Reject|Assign|Triage|Coordination|Start work|Complete work)/ })).not.toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Request attachments' })).getByRole('button', { name: 'Open' })).toBeInTheDocument()
    for (const [, options] of fetch.mock.calls) {
      expect(options.method || 'GET').toBe('GET')
      expect(options.headers.Authorization).toBe('Bearer tenant-token')
    }
    cleanup()
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:maintenance-photo')
  })

  it('highlights only recorded stages and the current status without inferring skipped states', async () => {
    requests = [request(newId, { status: 8 })]
    history = [
      { id: 'h1', toStatus: 0, changedAt: '2026-10-01T10:00:00Z' },
      { id: 'h2', toStatus: 2, changedAt: '2026-10-02T10:00:00Z' },
      { id: 'h3', toStatus: 8, changedAt: '2026-10-03T10:00:00Z' },
    ]
    renderPage()
    const progress = await screen.findByRole('region', { name: 'Request progress' })
    await waitFor(() => expect(progress.querySelectorAll('.maintenance-progress__reached')).toHaveLength(2))
    expect(progress.querySelector('[aria-current="step"]')).toHaveTextContent('In Progress')
    expect(within(progress).getByText('Completed').closest('li')).toHaveTextContent('Not recorded')
    expect(within(progress).getByText('Completed').closest('li')).not.toHaveClass('maintenance-progress__reached')
    expect(within(progress).getByText('Triaged').closest('li')).toHaveTextContent('Not recorded')
    await userEvent.click(await screen.findByText('Request summary', { selector: 'summary' }))
    const timeline = screen.getByRole('region', { name: 'Status history' })
    expect(within(timeline).getAllByRole('listitem')).toHaveLength(3)
    expect(within(timeline).queryByText('Completed')).not.toBeInTheDocument()
  })

  it.each([7, 10])('shows rejected/cancelled current status (%s) without highlighting completion', async (status) => {
    requests = [request(newId, { status })]
    renderPage()
    const progress = await screen.findByRole('region', { name: 'Request progress' })
    expect(progress.querySelector('[aria-current="step"]')).toHaveTextContent(status === 7 ? 'Rejected' : 'Cancelled')
    expect(within(progress).getByText('Completed').closest('li')).toHaveTextContent('Not recorded')
  })

  it('shows an empty tracking state and mobile guidance without create controls or unnecessary API calls', async () => {
    renderPage()
    expect(await screen.findByText('No maintenance requests yet.')).toBeInTheDocument()
    expect(screen.getByText('Use the RentFlow mobile app to submit a new maintenance request.')).toBeInTheDocument()
    expect(fetch).toHaveBeenCalledTimes(1)
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /^(Create|Submit|Upload)/ })).not.toBeInTheDocument()
  })

  it('does not fabricate history when the history endpoint fails and preserves the actual current status', async () => {
    requests = [request(newId, { status: 6 })]
    const original = fetch.getMockImplementation()
    fetch.mockImplementation((url, options) => url.includes('/history')
      ? Promise.resolve(json({ message: 'Internal database information' }, 500)) : original(url, options))
    renderPage()
    expect(await screen.findByRole('alert')).toHaveTextContent('The maintenance request failed')
    const progress = screen.getByRole('region', { name: 'Request progress' })
    expect(progress.querySelector('[aria-current="step"]')).toHaveTextContent('Approved')
    expect(progress.querySelectorAll('.maintenance-progress__reached')).toHaveLength(0)
    expect(screen.queryByText('Internal database information')).not.toBeInTheDocument()
  })

  it('retries a failed list load using only read requests', async () => {
    const original = fetch.getMockImplementation()
    fetch.mockImplementationOnce(() => Promise.resolve(json({}, 503)))
    renderPage()
    expect(await screen.findByRole('alert')).toBeInTheDocument()
    fetch.mockImplementation(original)
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByText('No maintenance requests yet.')).toBeInTheDocument()
    expect(fetch.mock.calls.every(([, options]) => !options.method || options.method === 'GET')).toBe(true)
  })
  it('keeps only the four status filters and clears a filtered empty state', async () => {
    requests = [request(oldId), request(newId, { status: 8, category: 1, priority: 2 })]
    renderPage()
    await screen.findByRole('article', { name: 'MR-0000000000000002' })
    await userEvent.click(screen.getByRole('button', { name: 'In Progress', exact: true }))
    expect(screen.getAllByRole('article')).toHaveLength(1)
    expect(screen.getByRole('article')).toHaveAccessibleName('MR-0000000000000002')
    expect(screen.queryByRole('combobox')).not.toBeInTheDocument()
    expect(within(screen.getByRole('group', { name: 'Filter by status' })).getAllByRole('button').map((button) => button.textContent)).toEqual(['All requests', 'Open', 'In Progress', 'Completed'])
    await userEvent.click(screen.getByRole('button', { name: 'Completed', exact: true }))
    expect(screen.getByText('No requests match these filters.')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Clear filters' }))
    expect(screen.getAllByRole('article')).toHaveLength(2)
    await userEvent.click(screen.getByRole('button', { name: 'In Progress', exact: true }))
    expect(screen.getAllByRole('article')).toHaveLength(1)
    expect(screen.getByRole('article')).toHaveAccessibleName('MR-0000000000000002')
    expect(fetch.mock.calls.every(([, options]) => !options.method || options.method === 'GET')).toBe(true)
    expect(fetch.mock.calls.filter(([url]) => url.includes(`/tenant/${tenantId}`))).toHaveLength(1)
  })

  it('retains cancelled and rejected requests in All requests while excluding them from Open', async () => {
    requests = [request(oldId), request(newId, { status: 9 }), request('cancelled', { status: 10, referenceCode: 'MR-CANCELLED' }), request('rejected', { status: 7, referenceCode: 'MR-REJECTED' })]
    renderPage()
    await screen.findByRole('article', { name: 'MR-0000000000000002' })
    for (const [filter, expected] of [['Open', 'MR-0000000000000001'], ['Completed', 'MR-0000000000000002']]) {
      await userEvent.click(screen.getByRole('button', { name: filter, exact: true }))
      expect(screen.getAllByRole('article')).toHaveLength(1)
      expect(screen.getByRole('article')).toHaveAccessibleName(expected)
    }
    await userEvent.click(screen.getByRole('button', { name: 'All requests' }))
    expect(screen.getAllByRole('article')).toHaveLength(4)
    expect(screen.getByRole('article', { name: 'MR-CANCELLED' })).toBeInTheDocument()
    expect(screen.getByRole('article', { name: 'MR-REJECTED' })).toBeInTheDocument()
  })

})
