import { cleanup, render, screen, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { AuthContext } from '../../features/auth/useAuth.js'
import { getMaintenanceRequestById, getTechnicianMaintenanceRequests } from '../../features/maintenance/services/maintenanceApiService.js'
import { technicianSummary } from './technicianWorkPresentation.js'

vi.mock('../../features/maintenance/services/maintenanceApiService.js', async (original) => ({
  ...await original(), getTechnicianMaintenanceRequests: vi.fn(), getMaintenanceRequestById: vi.fn(),
}))
vi.mock('../../features/notifications/notificationsApi.js', async (original) => ({ ...await original(), getUnreadCount: vi.fn().mockResolvedValue(0) }))

function renderWorkspace(path, role = 'MaintenanceTechnician') {
  vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
  return render(<MemoryRouter initialEntries={[path]}><AuthContext.Provider value={{ user: { id: 'tech-1', role, fullName: 'Taylor Technician' }, isAuthenticated: true, isLoading: false, logout: vi.fn() }}><App /></AuthContext.Provider></MemoryRouter>)
}
afterEach(() => { cleanup(); vi.clearAllMocks(); vi.unstubAllGlobals() })

describe('Technician live workspace', () => {
  it('counts local-day jobs and Monday-based completions without using creation dates', () => {
    const now = new Date(2026, 9, 6, 12)
    const items = [
      { status: 'Approved', scheduledAt: new Date(2026, 9, 6, 9).toISOString() },
      { status: 'InProgress', scheduledAt: new Date(2026, 9, 7, 9).toISOString() },
      { status: 'Completed', completedAt: new Date(2026, 9, 5, 17).toISOString() },
      { status: 'Completed', completedAt: new Date(2026, 9, 4, 17).toISOString() },
      { status: 'Cancelled', scheduledAt: new Date(2026, 9, 6, 9).toISOString() },
    ]
    expect(technicianSummary(items, now)).toEqual({ today: 1, progress: 1, completed: 1 })
    expect(technicianSummary([{ status: 'Approved', createdAt: now.toISOString() }], now).today).toBeNull()
    expect(technicianSummary([{ status: 'Completed', updatedAt: now.toISOString() }], now).completed).toBeNull()
  })

  it('counts completed today and earlier this week, but excludes older, active, and undated requests', () => {
    const now = new Date(2026, 9, 6, 12)
    const items = [
      { status: 'Completed', completedAt: new Date(2026, 9, 6, 9).toISOString() },
      { status: 'Completed', completedAt: new Date(2026, 9, 5, 17).toISOString() },
      { status: 'Completed', completedAt: new Date(2026, 9, 5, 9).toISOString() },
      { status: 'Completed', completedAt: new Date(2026, 8, 30, 17).toISOString() },
      { status: 'InProgress', completedAt: new Date(2026, 9, 6, 10).toISOString() },
      { status: 'Completed', completedAt: null, createdAt: new Date(2026, 9, 6, 10).toISOString() },
    ]
    expect(technicianSummary(items, now).completed).toBe(3)
  })

  it('shows real queue counts and unavailable scheduling data on the dashboard', async () => {
    getTechnicianMaintenanceRequests.mockResolvedValue([{ id: 'job-1', title: 'Repair sink', propertyTitle: 'Olive House', status: 'InProgress', category: 'Plumbing', priority: 'High' }])
    renderWorkspace('/dashboard')
    expect(await screen.findByText('Repair sink')).toBeInTheDocument()
    expect(screen.getByRole('region', { name: "Today's jobs" })).toHaveTextContent('Unavailable')
    expect(screen.getByRole('region', { name: 'In progress' })).toHaveTextContent('1')
    expect(screen.getByText('Olive House')).toBeInTheDocument()
    expect(getTechnicianMaintenanceRequests).toHaveBeenCalledWith('tech-1')
  })

  it('shows at most three active jobs and excludes terminal work from the dashboard preview', async () => {
    getTechnicianMaintenanceRequests.mockResolvedValue([
      { id: 'one', referenceCode: 'MR-001', title: 'Repair sink', propertyTitle: 'Olive House', status: 'InProgress', category: 'Plumbing', priority: 'High' },
      { id: 'two', referenceCode: 'MR-002', title: 'Fix socket', propertyTitle: 'Cedar House', status: 'Approved', category: 'Electrical', priority: 'Normal' },
      { id: 'three', referenceCode: 'MR-003', title: 'Replace lock', propertyTitle: 'Palm House', status: 'Assigned', category: 'Security', priority: 'Low' },
      { id: 'four', referenceCode: 'MR-004', title: 'Repair gate', propertyTitle: 'Lake House', status: 'Triaged', category: 'Structural', priority: 'Emergency' },
      { id: 'done', referenceCode: 'MR-005', title: 'Completed job', status: 'Completed', category: 'Other', priority: 'Normal' },
    ])
    renderWorkspace('/dashboard')
    const assignedWork = await screen.findByRole('region', { name: 'Assigned Work' })
    expect(within(assignedWork).getByText('MR-001')).toBeInTheDocument()
    expect(within(assignedWork).getByText('MR-002')).toBeInTheDocument()
    expect(within(assignedWork).getByText('MR-003')).toBeInTheDocument()
    expect(within(assignedWork).queryByText('MR-004')).not.toBeInTheDocument()
    expect(within(assignedWork).queryByText('Completed job')).not.toBeInTheDocument()
    expect(within(assignedWork).getAllByRole('link', { name: 'View details' })).toHaveLength(3)
  })

  it('shows the truthful empty state when the technician has no active work', async () => {
    getTechnicianMaintenanceRequests.mockResolvedValue([
      { id: 'done', referenceCode: 'MR-006', title: 'Completed job', status: 'Completed' },
      { id: 'cancelled', referenceCode: 'MR-007', title: 'Cancelled job', status: 'Cancelled' },
    ])
    renderWorkspace('/dashboard')
    expect(await screen.findByText('No active assigned work.')).toBeInTheDocument()
  })

  it('shows only actionable assigned work in the sidebar badge', async () => {
    getTechnicianMaintenanceRequests.mockResolvedValue([
      { id: 'one', status: 'Assigned' },
      { id: 'two', status: 'InProgress' },
      { id: 'waiting', status: 'AwaitingLandlordApproval' },
      { id: 'done', status: 'Completed' },
      { id: 'cancelled', status: 'Cancelled' },
    ])
    renderWorkspace('/dashboard')
    expect(await screen.findByRole('link', { name: 'Assigned Work, 2 pending' })).toBeInTheDocument()
  })

  it('hides the assigned-work badge when no jobs require technician action', async () => {
    getTechnicianMaintenanceRequests.mockResolvedValue([
      { id: 'done', status: 'Completed' },
    ])
    renderWorkspace('/dashboard')
    await screen.findByText('No active assigned work.')
    expect(screen.queryByRole('link', { name: /Assigned Work, .*pending/ })).not.toBeInTheDocument()
  })

  it('reads actual completion dates from authorized details and shows only completed jobs', async () => {
    getTechnicianMaintenanceRequests.mockResolvedValue([
      {
        id: 'done',
        tenantId: 'tenant-secret',
        referenceCode: 'MR-LOCK-01',
        title: 'Repair lock',
        propertyTitle: 'Olive House',
        status: 'Completed',
        category: 'Security',
        priority: 'Normal',
      },
      { id: 'active', title: 'Repair sink', status: 'InProgress' },
    ])
    getMaintenanceRequestById.mockResolvedValue({ id: 'done', completedAt: '2026-10-05T10:00:00Z', assignmentNotes: 'Bring a new lock.' })
    renderWorkspace('/modules/work-history')
    expect(await screen.findByText('Repair lock')).toBeInTheDocument()
    expect(screen.queryByText('Repair sink')).not.toBeInTheDocument()
    expect(screen.getByText('1 completed job')).toBeInTheDocument()
    expect(getMaintenanceRequestById).toHaveBeenCalledWith('done')
    expect(screen.getByText('MR-LOCK-01')).toBeInTheDocument()
    expect(screen.getByText('Olive House')).toBeInTheDocument()
    expect(screen.getByText('Security')).toBeInTheDocument()
    expect(screen.getByText('Normal')).toBeInTheDocument()
    expect(screen.getByText('Oct 5, 2026')).toBeInTheDocument()
    expect(screen.queryByText('tenant-secret')).not.toBeInTheDocument()
    expect(screen.getByText(/Bring a new lock/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Refresh' })).not.toBeInTheDocument()
    expect(within(screen.getByRole('navigation', { name: 'Primary navigation' })).getByRole('link', { name: 'Work History' })).toHaveAttribute('aria-current', 'page')
    expect(screen.queryByRole('button', { name: 'Mark Complete' })).not.toBeInTheDocument()
  })

  it('does not invent a completion date if a detail read fails', async () => {
    getTechnicianMaintenanceRequests.mockResolvedValue([{ id: 'done', title: 'Repair lock', status: 'Completed' }])
    getMaintenanceRequestById.mockRejectedValue(new Error('Unavailable'))
    renderWorkspace('/modules/work-history')
    expect(await screen.findByText('Completion date unavailable')).toBeInTheDocument()
  })

  it('orders completed history by real completion time and excludes active work', async () => {
    getTechnicianMaintenanceRequests.mockResolvedValue([
      { id: 'older-id', referenceCode: 'MR-OLD', title: 'Older repair', status: 'Completed', completedAt: '2026-10-04T10:00:00Z' },
      { id: 'active-id', referenceCode: 'MR-ACTIVE', title: 'Active repair', status: 'InProgress' },
      { id: 'newer-id', referenceCode: 'MR-NEW', title: 'Newer repair', status: 'Completed', completedAt: '2026-10-05T10:00:00Z' },
    ])
    renderWorkspace('/modules/work-history')
    const headings = await screen.findAllByRole('heading', { level: 3 })
    expect(headings.map((heading) => heading.textContent)).toEqual(['Newer repair', 'Older repair'])
    expect(screen.queryByText('active-id')).not.toBeInTheDocument()
    expect(screen.queryByText('older-id')).not.toBeInTheDocument()
    expect(screen.getByText('Oct 5, 2026')).toBeInTheDocument()
  })

  it.each(['Tenant', 'Landlord', 'Admin'])('blocks %s from Work History', (role) => {
    renderWorkspace('/modules/work-history', role)
    expect(screen.getByRole('heading', { name: 'Not accessible' })).toBeInTheDocument()
    expect(getTechnicianMaintenanceRequests).not.toHaveBeenCalled()
  })

  it('shows queue errors without presenting zero summary counts', async () => {
    getTechnicianMaintenanceRequests.mockRejectedValue(new Error('Service unavailable'))
    renderWorkspace('/dashboard')
    expect(await screen.findByRole('alert')).toHaveTextContent('Service unavailable')
    expect(screen.getByRole('region', { name: 'In progress' })).not.toHaveTextContent('0')
  })
})
