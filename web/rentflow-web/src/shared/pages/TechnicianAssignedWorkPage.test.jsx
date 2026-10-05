import { cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { AuthContext } from '../../features/auth/useAuth.js'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import { AssignedWorkState } from './TechnicianAssignedWorkPage.jsx'

vi.mock('../../features/notifications/notificationsApi.js', async (importOriginal) => ({
  ...(await importOriginal()), getUnreadCount: vi.fn().mockResolvedValue(0),
}))

const account = (role = 'MaintenanceTechnician') => ({
  id: '11111111-1111-1111-1111-111111111111', fullName: 'Sam Perera',
  email: 'sam@example.com', phoneNumber: '+94 77 123 4567', role,
})

function renderRoute(role = 'MaintenanceTechnician') {
  const session = { user: account(role), isAuthenticated: true, isLoading: false, logout: vi.fn() }
  return render(<MemoryRouter initialEntries={['/modules/assigned-work']}><AuthContext.Provider value={session}><App /></AuthContext.Provider></MemoryRouter>)
}

beforeEach(() => {
  tokenStorage.setToken('technician-token')
  vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
  vi.stubGlobal('fetch', vi.fn())
})
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('Technician Assigned Work page', () => {
  it.each(['MR-C8070B6D94F6A810', null])('shows only the friendly reference or a neutral fallback (%s)', (referenceCode) => {
    const ids = {
      id: '11efbe01-9196-44b6-b1b2-73767fae5cf1',
      tenantId: '21efbe01-9196-44b6-b1b2-73767fae5cf1',
      propertyId: '31efbe01-9196-44b6-b1b2-73767fae5cf1',
    }
    render(<AssignedWorkState status="ready" requests={[{
      ...ids, referenceCode, title: 'Bedroom outlet not working', selected: true,
      category: 'Electrical', priority: 'Normal', status: 'Assigned',
    }]} />)
    expect(screen.getByRole('heading', { name: 'Bedroom outlet not working' })).toBeInTheDocument()
    if (referenceCode) {
      expect(screen.getByText(`Request #${referenceCode}`)).toBeInTheDocument()
      expect(screen.getByText(referenceCode)).toBeInTheDocument()
    } else {
      expect(screen.getAllByText('Reference unavailable')).toHaveLength(2)
    }
    for (const id of Object.values(ids)) expect(screen.queryByText(id)).not.toBeInTheDocument()
    expect(screen.queryByText('Request ID')).not.toBeInTheDocument()
  })

  it('loads the signed-in technician work queue and renders live maintenance items', async () => {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: async () => [{
        id: 'request-1',
        title: 'Kitchen sink leak',
        description: 'Water is leaking under the sink cabinet.',
        status: 2,
        priority: 2,
        category: 0,
        propertyId: 'property-1',
      }],
    })

    renderRoute()
    const main = screen.getByRole('main')
    expect(within(main).getByRole('heading', { name: 'Assigned Work', level: 1 })).toBeInTheDocument()
    expect(within(main).getByText('Technician workspace')).toBeInTheDocument()

    await waitFor(() => {
      expect(screen.getByText('Kitchen sink leak')).toBeInTheDocument()
    })
    expect(screen.getByText('Assigned')).toBeInTheDocument()
    expect(screen.getByText('High')).toBeInTheDocument()
    expect(screen.getByText('Plumbing')).toBeInTheDocument()

    expect(fetch).toHaveBeenCalledWith(
      expect.stringContaining('/api/maintenance-requests/technician/11111111-1111-1111-1111-111111111111'),
      expect.objectContaining({ headers: expect.objectContaining({ Authorization: 'Bearer technician-token' }) }),
    )
  })

  it('keeps navigation active and exposes only work actions allowed by the request status', async () => {
    fetch.mockResolvedValueOnce({
      ok: true,
      json: async () => [{
        id: 'request-1', title: 'Kitchen sink leak', description: 'Leak details',
        status: 2, priority: 2, category: 0, propertyId: 'property-1',
      }],
    })
    renderRoute()
    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    const assignedLink = within(nav).getByRole('link', { name: 'Assigned Work' })
    expect(assignedLink).toHaveAttribute('href', '/modules/assigned-work')
    expect(assignedLink).toHaveAttribute('aria-current', 'page')
    expect(assignedLink).not.toHaveTextContent('Soon')

    const main = screen.getByRole('main')
    expect(within(main).getByRole('link', { name: 'Back to dashboard' })).toHaveAttribute('href', '/dashboard')
    expect(within(main).getAllByRole('link', { name: /notification/i }).every((link) => link.getAttribute('href') === '/notifications')).toBe(true)
    expect(within(main).getByRole('link', { name: /Profile/ })).toHaveAttribute('href', '/profile')
    expect(await within(main).findByRole('button', { name: 'View details' })).toBeInTheDocument()
    expect(within(main).queryByRole('button', { name: /start work|complete work/i })).not.toBeInTheDocument()
  })

  it.each(['Tenant', 'Landlord', 'Admin'])('blocks %s from the Technician route', (role) => {
    renderRoute(role)
    expect(screen.getByRole('heading', { name: 'Not accessible' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Assigned Work' })).not.toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
  })

  it('provides accessible loading and empty presentations for the future collection workflow', () => {
    const view = render(<AssignedWorkState status="loading" />)
    expect(screen.getByRole('status')).toHaveAttribute('aria-busy', 'true')
    expect(screen.getByRole('heading', { name: 'Loading assigned work' })).toBeInTheDocument()

    view.rerender(<AssignedWorkState status="empty" />)
    expect(screen.getByRole('heading', { name: 'No assigned work' })).toBeInTheDocument()
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  it('provides an accessible retryable error presentation without manufacturing records', async () => {
    const retry = vi.fn()
    render(<AssignedWorkState status="error" error="Unable to reach assigned work." onRetry={retry} />)
    expect(screen.getByRole('alert')).toHaveTextContent('Unable to reach assigned work.')
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect(retry).toHaveBeenCalledOnce()
  })

  it('starts and completes work, showing details and refreshing the authorized queue', async () => {
    const makeResponse = (status) => ({
      ok: true,
      json: async () => [{
        id: 'request-1',
        title: 'Kitchen sink leak',
        description: 'Water is leaking under the sink cabinet.',
        status,
        priority: 2,
        category: 0,
        propertyId: 'property-1',
        tenantId: 'tenant-1',
        tenantAccessNotes: 'Use the back door.',
        assignmentNotes: 'Visit Monday.',
      }],
    })
    fetch
      .mockResolvedValueOnce(makeResponse(6))
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          id: 'estimate-1',
          status: 1,
          laborCost: 100,
          partsCost: 50,
          additionalCost: 0,
          totalCost: 150,
        }),
      })
      .mockResolvedValueOnce(makeResponse(8))
      .mockResolvedValueOnce(makeResponse(8))
      .mockResolvedValueOnce(makeResponse(9))
      .mockResolvedValueOnce(makeResponse(9))

    renderRoute()
    await userEvent.click(await screen.findByRole('button', { name: 'View details' }))
    expect(screen.queryByText('tenant-1')).not.toBeInTheDocument()
    expect(screen.getByText('Use the back door.')).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Start work' }))
    expect(await screen.findByRole('button', { name: 'Complete work' })).toBeInTheDocument()
    expect(await screen.findByRole('status')).toHaveTextContent('Work started.')

    await userEvent.click(screen.getByRole('button', { name: 'Complete work' }))
    expect(await screen.findByRole('status')).toHaveTextContent('Work completed.')
    expect(fetch).toHaveBeenCalledTimes(6)
    expect(fetch.mock.calls.map(([url]) => url).filter((url) => String(url).includes('/technician/'))).toHaveLength(3)
  })

  it('creates a technician estimate and submits it for landlord review', async () => {
    fetch
      .mockResolvedValueOnce(new Response(JSON.stringify([{
        id: 'request-estimate',
        title: 'Broken heater',
        description: 'The heater will not turn on.',
        status: 3,
        priority: 1,
        category: 2,
        propertyId: 'property-1',
      }]), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ detail: 'No estimate found.' }), { status: 404 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        id: 'estimate-1',
        status: 1,
        laborCost: 120,
        partsCost: 45,
        additionalCost: 5,
        totalCost: 170,
        notes: 'Replace the thermostat.',
      }), { status: 201 }))
      .mockResolvedValueOnce(new Response(JSON.stringify([{
        id: 'request-estimate',
        title: 'Broken heater',
        description: 'The heater will not turn on.',
        status: 4,
        priority: 1,
        category: 2,
        propertyId: 'property-1',
      }]), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        id: 'request-estimate',
        status: 5,
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify([{
        id: 'request-estimate',
        title: 'Broken heater',
        description: 'The heater will not turn on.',
        status: 5,
        priority: 1,
        category: 2,
        propertyId: 'property-1',
      }]), { status: 200 }))

    renderRoute()
    await userEvent.click(await screen.findByRole('button', { name: 'View details' }))
    expect(await screen.findByLabelText('Labor cost')).toBeInTheDocument()
    await userEvent.type(screen.getByLabelText('Labor cost'), '120')
    await userEvent.type(screen.getByLabelText('Parts cost'), '45')
    await userEvent.type(screen.getByLabelText('Additional cost'), '5')
    await userEvent.type(screen.getByLabelText('Estimate notes'), 'Replace the thermostat.')
    await userEvent.click(screen.getByRole('button', { name: 'Create estimate' }))

    expect(await screen.findByText(/\$170\.00/)).toBeInTheDocument()
    expect(await screen.findByRole('button', { name: 'Submit estimate for review' })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Submit estimate for review' }))
    expect(await screen.findByText('Estimate submitted for landlord review.')).toBeInTheDocument()

    const createCall = fetch.mock.calls.find(([url, options]) =>
      String(url).includes('/api/maintenance-requests/request-estimate/estimates') &&
      options?.method === 'POST')
    expect(createCall).toBeDefined()
    expect(JSON.parse(createCall[1].body)).toEqual({
      laborCost: 120,
      partsCost: 45,
      additionalCost: 5,
      notes: 'Replace the thermostat.',
    })
    expect(fetch.mock.calls.some(([url, options]) =>
      String(url).includes('/api/maintenance-requests/request-estimate/estimates/estimate-1/submit-for-review') &&
      options?.method === 'PATCH')).toBe(true)
  })
})
