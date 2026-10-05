import { cleanup, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import { AuthContext } from '../auth/useAuth.js'
import LandlordMaintenancePage from './pages/LandlordMaintenancePage.jsx'
import TenantMaintenancePage from './pages/TenantMaintenancePage.jsx'

const propertyId = '88888888-8888-8888-8888-888888888888'
const requestId = '99999999-9999-4999-8999-999999999999'
const tenantId = '11111111-1111-4111-8111-111111111111'
const landlordId = '22222222-2222-4222-8222-222222222222'
const technicianId = '33333333-3333-4333-8333-333333333333'

const maintenanceRequest = (status = 0) => ({
  id: requestId,
  propertyId,
  tenantId,
  technicianId: null,
  title: 'Leaking kitchen sink',
  description: 'Water is leaking below the sink.',
  category: 0,
  priority: 1,
  status,
  createdAt: '2026-09-01T12:00:00Z',
  updatedAt: '2026-09-01T12:00:00Z',
})

function response(body, status = 200) {
  return new Response(body === undefined ? null : JSON.stringify(body), { status })
}

function renderWithUser(role, id, ui, route = '/modules/maintenance') {
  const session = {
    user: { id, fullName: 'Test User', email: 'test@example.com', phoneNumber: '', role },
    isAuthenticated: true,
    isLoading: false,
    logout: vi.fn(),
  }
  return render(
    <MemoryRouter initialEntries={[route]}>
      <AuthContext.Provider value={session}>{ui}</AuthContext.Provider>
    </MemoryRouter>,
  )
}

beforeEach(() => {
  tokenStorage.setToken('maintenance-test-token')
  vi.stubGlobal('matchMedia', vi.fn(() => ({
    matches: false,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
  })))
  vi.stubGlobal('fetch', vi.fn())
  window.localStorage.clear()
})

afterEach(() => {
  cleanup()
  tokenStorage.clearToken()
  window.localStorage.clear()
  vi.unstubAllGlobals()
})

describe('maintenance workflows', () => {
  it('keeps legacy title/notes while sending the required access window and new HVAC category', async () => {
    let created = null
    fetch.mockImplementation(async (url, options = {}) => {
      const path = String(url)
      if (path.includes('/api/properties/tenant/mine')) return response([{ id: propertyId, title: 'Riverside Flat', city: 'Colombo' }])
      if (options.method === 'POST' && path.includes('/api/maintenance-requests?')) {
        created = JSON.parse(options.body)
        return response({ ...maintenanceRequest(), ...created, referenceCode: 'MR-C8070B6D94F6A810' }, 201)
      }
      if (path.includes(`/api/maintenance-requests/tenant/${tenantId}`)) return response([])
      return response([])
    })
    renderWithUser('Tenant', tenantId, <TenantMaintenancePage />)
    await userEvent.selectOptions(await screen.findByRole('combobox', { name: 'Associated property' }), propertyId)
    await userEvent.type(screen.getByLabelText('Title'), 'A/C rattling')
    await userEvent.type(screen.getByLabelText('Description'), 'The bedroom air conditioner is rattling.')
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Category' }), 'Hvac')
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Preferred access time' }), 'Evening')
    await userEvent.type(screen.getByLabelText('Tenant access notes'), 'Please knock.')
    await userEvent.click(screen.getByRole('button', { name: 'Submit request' }))
    await waitFor(() => expect(created).toMatchObject({ propertyId, title: 'A/C rattling', category: 7, preferredAccessWindow: 'Evening', tenantAccessNotes: 'Please knock.' }))
  })

  it('triages a submitted request and assigns a selected active technician', async () => {
    let currentRequest = maintenanceRequest()
    fetch.mockImplementation(async (url, options = {}) => {
      const path = String(url)
      if (path.includes('/api/properties/mine')) {
        return response([{ id: propertyId, title: 'Riverside Flat', city: 'Colombo' }])
      }
      if (path.includes(`/api/maintenance-requests/property/${propertyId}`)) {
        return response([currentRequest])
      }
      if (path.endsWith(`/api/maintenance-requests/${requestId}/history`)) return response([])
      if (path.endsWith(`/api/maintenance-requests/${requestId}/estimates/latest`)) {
        return response({ detail: 'No estimate found.' }, 404)
      }
      if (path.endsWith('/api/maintenance-requests/technicians')) {
        return response([{ id: technicianId, name: 'Morgan Technician' }])
      }
      if (path.endsWith(`/api/maintenance-requests/${requestId}/triage`)) {
        const body = JSON.parse(options.body)
        currentRequest = { ...currentRequest, ...body, status: 1 }
        return response(currentRequest)
      }
      if (path.endsWith(`/api/maintenance-requests/${requestId}/assign-technician`)) {
        const body = JSON.parse(options.body)
        currentRequest = { ...currentRequest, ...body, status: 2 }
        return response(currentRequest)
      }
      if (path.endsWith(`/api/maintenance-requests/${requestId}`)) return response(currentRequest)
      return response({ detail: 'Not found.' }, 404)
    })

    renderWithUser('Landlord', landlordId, <LandlordMaintenancePage />)
    await userEvent.selectOptions(await screen.findByRole('combobox', { name: 'Property' }), propertyId)
    await screen.findByRole('button', { name: 'Triage request' })
    await userEvent.selectOptions(screen.getByLabelText('Priority', { selector: 'select' }), 'High')
    await userEvent.type(screen.getByLabelText('Triage notes'), 'Urgent plumbing repair.')
    await userEvent.click(screen.getByRole('button', { name: 'Triage request' }))

    const technicianSelector = await screen.findByRole('combobox', { name: 'Maintenance technician' })
    await userEvent.selectOptions(technicianSelector, technicianId)
    await userEvent.type(screen.getByLabelText('Assignment notes'), 'Call before arrival.')
    await userEvent.click(screen.getByRole('button', { name: 'Assign technician' }))

    await waitFor(() => {
      expect(screen.getByText('Technician assigned.')).toBeInTheDocument()
    })
    const triageCall = fetch.mock.calls.find(([url, options]) =>
      String(url).endsWith(`/api/maintenance-requests/${requestId}/triage`) &&
      options.method === 'PATCH')
    expect(JSON.parse(triageCall[1].body)).toEqual({
      category: 0,
      priority: 2,
      triageNotes: 'Urgent plumbing repair.',
    })
    const assignmentCall = fetch.mock.calls.find(([url, options]) =>
      String(url).endsWith(`/api/maintenance-requests/${requestId}/assign-technician`) &&
      options.method === 'PATCH')
    expect(JSON.parse(assignmentCall[1].body)).toEqual({
      technicianId,
      assignmentNotes: 'Call before arrival.',
    })
    expect(fetch.mock.calls.some(([url]) => String(url).endsWith('/api/maintenance-requests/technicians'))).toBe(true)
  })

  it('selects an associated tenant property and uploads/removes authorized attachments', async () => {
    const initialRequest = maintenanceRequest()
    const attachment = {
      id: 'attachment-1',
      fileName: 'sink-photo.png',
      attachmentType: 'Photo',
      fileSize: 1024,
    }
    let attachments = []
    fetch.mockImplementation(async (url, options = {}) => {
      const path = String(url)
      if (path.endsWith('/api/properties/tenant/mine')) {
        return response([{ id: propertyId, title: 'Riverside Flat', city: 'Colombo' }])
      }
      if (path.endsWith(`/api/maintenance-requests/tenant/${tenantId}`)) return response([initialRequest])
      if (path.endsWith(`/api/maintenance-requests/${requestId}/attachments?tenantId=${tenantId}`) &&
          options.method === 'POST') {
        attachments = [attachment]
        return response(attachment, 201)
      }
      if (path.endsWith(`/api/maintenance-requests/${requestId}/attachments?tenantId=${tenantId}`)) {
        return response(attachments)
      }
      if (path.endsWith(`/api/maintenance-requests/${requestId}/attachments/attachment-1?tenantId=${tenantId}`) &&
          options.method === 'DELETE') {
        attachments = []
        return response(undefined, 204)
      }
      if (path.endsWith(`/api/maintenance-requests/${requestId}`)) return response(initialRequest)
      return response({ detail: 'Not found.' }, 404)
    })

    renderWithUser(
      'Tenant',
      tenantId,
      <TenantMaintenancePage />,
      `/modules/maintenance?propertyId=${propertyId}`,
    )
    expect(await screen.findByLabelText('Associated property')).toHaveValue(propertyId)
    expect(screen.queryByLabelText('Property ID')).not.toBeInTheDocument()
    expect(await screen.findByText('No attachments have been added to this request.')).toBeInTheDocument()

    const photo = new File(['image content'], 'sink-photo.png', { type: 'image/png' })
    await userEvent.upload(screen.getByLabelText('File'), photo)
    expect(screen.getByLabelText('File').files).toHaveLength(1)
    await userEvent.selectOptions(screen.getByLabelText('Attachment type'), 'Photo')
    expect(screen.getByRole('button', { name: 'Upload attachment' }).closest('form').checkValidity()).toBe(true)
    await userEvent.click(screen.getByRole('button', { name: 'Upload attachment' }))
    await waitFor(() => {
      expect(fetch.mock.calls.some(([url, options]) =>
        String(url).includes(`/api/maintenance-requests/${requestId}/attachments`) &&
        options.method === 'POST')).toBe(true)
    })
    expect(await screen.findByText('sink-photo.png')).toBeInTheDocument()
    const uploadCall = fetch.mock.calls.find(([url, options]) =>
      String(url).includes('/api/maintenance-requests/') && options.method === 'POST')
    expect(uploadCall[1].body).toBeInstanceOf(FormData)
    expect(uploadCall[1].body.get('file')).toBeInstanceOf(File)
    expect(uploadCall[1].body.get('attachmentType')).toBe('Photo')

    await userEvent.click(screen.getByRole('button', { name: 'Remove' }))
    await waitFor(() => expect(screen.getByText('No attachments have been added to this request.')).toBeInTheDocument())
    expect(fetch.mock.calls.some(([url, options]) =>
      String(url).endsWith(`/api/maintenance-requests/${requestId}/attachments/attachment-1?tenantId=${tenantId}`) &&
      options.method === 'DELETE')).toBe(true)
  })

  it.each([
    ['Approve estimate', 'approve', 3, 6],
    ['Reject estimate', 'reject', 4, 7],
    ['Request revision', 'request-revision', 2, 3],
  ])('allows a landlord to %s with review notes', async (buttonName, action, estimateStatus, requestStatus) => {
    let currentRequest = maintenanceRequest(5)
    let currentEstimate = {
      id: 'estimate-1',
      status: 1,
      laborCost: 100,
      partsCost: 50,
      additionalCost: 0,
      totalCost: 150,
      technicianId,
    }
    fetch.mockImplementation(async (url) => {
      const path = String(url)
      if (path.includes('/api/properties/mine')) {
        return response([{ id: propertyId, title: 'Riverside Flat' }])
      }
      if (path.includes(`/api/maintenance-requests/property/${propertyId}`)) return response([currentRequest])
      if (path.endsWith(`/api/maintenance-requests/${requestId}/history`)) return response([])
      if (path.endsWith(`/api/maintenance-requests/${requestId}/estimates/latest`)) return response(currentEstimate)
      if (path.endsWith(`/api/maintenance-requests/${requestId}/estimates/estimate-1/${action}`)) {
        currentEstimate = { ...currentEstimate, status: estimateStatus }
        currentRequest = { ...currentRequest, status: requestStatus }
        return response(currentEstimate)
      }
      if (path.endsWith(`/api/maintenance-requests/${requestId}`)) return response(currentRequest)
      return response({ detail: 'Not found.' }, 404)
    })

    renderWithUser('Landlord', landlordId, <LandlordMaintenancePage />)
    await userEvent.selectOptions(await screen.findByRole('combobox', { name: 'Property' }), propertyId)
    await screen.findByLabelText('Review notes')
    await userEvent.type(screen.getByLabelText('Review notes'), 'Reviewed against the submitted scope.')
    await userEvent.click(screen.getByRole('button', { name: buttonName }))
    expect(await screen.findByRole('status')).toHaveTextContent(
      action === 'approve' ? 'Repair estimate approved.' :
        action === 'reject' ? 'Repair estimate rejected.' : 'Revision requested from the technician.',
    )

    const reviewCall = fetch.mock.calls.find(([url, options]) =>
      String(url).endsWith(`/api/maintenance-requests/${requestId}/estimates/estimate-1/${action}`) &&
      options.method === 'PATCH')
    expect(JSON.parse(reviewCall[1].body)).toEqual({
      reviewNotes: 'Reviewed against the submitted scope.',
    })
  })

  it('starts, reads, persists, and human-approves a coordination workflow', async () => {
    let workflow = {
      id: 'workflow-1',
      status: 2,
      approvalStatus: 1,
      requiresHumanApproval: true,
      planSummary: 'Replace the leaking sink trap.',
    }
    fetch.mockImplementation(async (url, options = {}) => {
      const path = String(url)
      if (path.includes('/api/properties/mine')) {
        return response([{ id: propertyId, title: 'Riverside Flat' }])
      }
      if (path.includes(`/api/maintenance-requests/property/${propertyId}`)) return response([maintenanceRequest()])
      if (path.endsWith(`/api/maintenance-requests/${requestId}/history`)) return response([])
      if (path.endsWith(`/api/maintenance-requests/${requestId}/estimates/latest`)) {
        return response({ detail: 'No estimate found.' }, 404)
      }
      if (path.endsWith(`/api/maintenance-requests/${requestId}/coordination-workflows`) &&
          options.method === 'POST') return response(workflow, 201)
      if (path.endsWith(`/api/maintenance-requests/${requestId}/coordination-workflows/workflow-1/approve`)) {
        workflow = { ...workflow, status: 3, approvalStatus: 2 }
        return response(workflow)
      }
      if (path.endsWith(`/api/maintenance-requests/${requestId}/coordination-workflows/workflow-1`)) return response(workflow)
      if (path.endsWith(`/api/maintenance-requests/${requestId}`)) return response(maintenanceRequest())
      return response({ detail: 'Not found.' }, 404)
    })

    const view = renderWithUser('Landlord', landlordId, <LandlordMaintenancePage />)
    await userEvent.selectOptions(await screen.findByRole('combobox', { name: 'Property' }), propertyId)
    await userEvent.click(await screen.findByRole('button', { name: 'Start AI coordination' }))
    expect(await screen.findByText('Replace the leaking sink trap.')).toBeInTheDocument()
    expect(window.localStorage.getItem(`rentflow.maintenance.workflow.${requestId}`)).toBe('workflow-1')
    await userEvent.type(screen.getByLabelText('Decision notes'), 'Approved after review.')
    await userEvent.click(screen.getByRole('button', { name: 'Approve' }))
    expect(await screen.findByText(/AI\/workflow review approved/)).toBeInTheDocument()

    expect(fetch.mock.calls.some(([url, options]) =>
      String(url).endsWith(`/api/maintenance-requests/${requestId}/coordination-workflows`) &&
      options.method === 'POST')).toBe(true)
    expect(fetch.mock.calls.some(([url]) =>
      String(url).endsWith(`/api/maintenance-requests/${requestId}/coordination-workflows/workflow-1`))).toBe(true)
    const approveCall = fetch.mock.calls.find(([url, options]) =>
      String(url).endsWith(`/api/maintenance-requests/${requestId}/coordination-workflows/workflow-1/approve`) &&
      options.method === 'PATCH')
    expect(JSON.parse(approveCall[1].body)).toEqual({ decisionNotes: 'Approved after review.' })

    view.unmount()
    renderWithUser('Landlord', landlordId, <LandlordMaintenancePage />)
    await userEvent.selectOptions(await screen.findByRole('combobox', { name: 'Property' }), propertyId)
    expect(await screen.findByText('Replace the leaking sink trap.')).toBeInTheDocument()
  })
})
