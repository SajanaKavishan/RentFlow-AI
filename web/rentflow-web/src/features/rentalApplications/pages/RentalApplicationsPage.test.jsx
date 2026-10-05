import { cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import OwnedPropertiesContext from '../../../shared/property/OwnedPropertiesContext.js'
import RentalApplicationsPage from './RentalApplicationsPage.jsx'

vi.mock('../../properties/services/propertyApiService.js', () => ({
  getPropertyImages: vi.fn().mockResolvedValue([]),
  getPropertyImageUrl: vi.fn(),
}))
vi.mock('../services/rentalApplicationApiService.js', async (importOriginal) => ({
  ...await importOriginal(),
  getOwnedPropertyApplicationActionCounts: vi.fn().mockResolvedValue([]),
}))

const propertyId = '22222222-2222-2222-2222-222222222222'
const tenantId = '11111111-1111-1111-1111-111111111111'
const property = {
  id: propertyId,
  title: 'Harbour View Residence',
  address: '18 Marine Drive',
  city: 'Colombo',
  isAvailable: true,
}

function application(overrides = {}) {
  return {
    id: '33333333-3333-3333-3333-333333333333',
    tenantId,
    propertyId,
    moveInDate: '2030-02-14',
    monthlyIncome: 6500,
    occupation: 'Product designer',
    numberOfOccupants: 2,
    tenantNote: 'We would like a long-term tenancy.',
    status: 1,
    landlordResponse: null,
    createdAt: '2026-09-10T08:00:00Z',
    submittedAt: '2026-09-11T09:30:00Z',
    updatedAt: '2026-09-12T10:45:00Z',
    ...overrides,
  }
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function mockApplicationApi(applications, options = {}) {
  const { documents = [], validationRuns = [], actionResponse } = options
  const fetchMock = vi.fn().mockImplementation((url, request = {}) => {
    if (url.includes('/documents')) {
      return Promise.resolve(jsonResponse(documents))
    }
    if (url.includes('/validation-runs')) {
      return Promise.resolve(jsonResponse(validationRuns))
    }
    if (request.method === 'PATCH' && actionResponse) {
      return Promise.resolve(jsonResponse(actionResponse))
    }
    return Promise.resolve(jsonResponse(applications))
  })
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

function renderPage(selectedPropertyId = propertyId, route = 'rental-applications', properties = [property]) {
  const routePath = route.startsWith('/') ? route : `/${route}`
  const isScopedRoute = routePath.startsWith('/properties/')
  const entry = selectedPropertyId
    ? (isScopedRoute ? routePath : `/properties/${selectedPropertyId}${routePath}`)
    : routePath

  return render(
    <OwnedPropertiesContext.Provider value={{ status: 'ready', properties, error: '', retry: vi.fn() }}>
      <MemoryRouter initialEntries={[entry]}>
        <Routes>
          <Route path="/rental-applications" element={<RentalApplicationsPage />} />
          <Route path="/ai-review" element={<RentalApplicationsPage />} />
          <Route path="/properties/:propertyId/rental-applications" element={<RentalApplicationsPage />} />
          <Route path="/properties/:propertyId/ai-review" element={<RentalApplicationsPage />} />
        </Routes>
      </MemoryRouter>
    </OwnedPropertiesContext.Provider>,
  )
}

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

describe('Landlord rental applications', () => {
  it('prioritizes attention states and exposes every application status clearly', async () => {
    const applications = [
      application({ id: 'approved', status: 4 }),
      application({ id: 'withdrawn', status: 6 }),
      application({ id: 'changes', status: 3, landlordResponse: 'Upload a clearer identity document.' }),
      application({ id: 'rejected', status: 5 }),
      application({ id: 'review', status: 2 }),
      application({ id: 'draft', status: 0 }),
      application({ id: 'submitted', status: 1 }),
    ]
    const fetchMock = mockApplicationApi(applications)

    renderPage()

    const cards = await screen.findAllByRole('article')
    expect(fetchMock).toHaveBeenCalledWith(
      expect.stringContaining(
        `/api/rental-applications/property/${propertyId}`,
      ),
      expect.any(Object),
    )
    expect(cards).toHaveLength(7)
    expect(screen.getByRole('link', { name: 'Back to Property' }))
      .toHaveAttribute('href', `/properties/${propertyId}`)
    expect(screen.getByRole('group', { name: 'Selected property' }))
      .toHaveTextContent('Harbour View Residence18 Marine Drive, Colombo')
    const counts = screen.getByRole('group', { name: 'Rental application counts' })
    expect(within(counts).getByText('Total').parentElement).toHaveTextContent('7')
    expect(within(counts).getByText('Awaiting review').parentElement).toHaveTextContent('2')
    expect(within(cards[0]).getByLabelText('Application status: Submitted')).toBeInTheDocument()
    expect(within(cards[1]).getByLabelText('Application status: Under review')).toBeInTheDocument()
    expect(within(cards[2]).getByLabelText('Application status: Changes requested')).toBeInTheDocument()
    expect(within(cards[2]).queryByText('Tenant update required')).not.toBeInTheDocument()

    for (const label of ['Draft', 'Approved', 'Rejected', 'Withdrawn']) {
      expect(screen.getByLabelText(`Application status: ${label}`)).toBeInTheDocument()
    }

    expect(within(cards[0]).getByText(tenantId)).toBeInTheDocument()
    expect(within(cards[0]).getByText('submitted')).toBeInTheDocument()
    expect(within(cards[0]).getByText('Harbour View Residence')).toBeInTheDocument()
    expect(within(cards[0]).getByText('18 Marine Drive, Colombo')).toBeInTheDocument()
    expect(cards[0].querySelector(`time[datetime="${application().submittedAt}"]`)).toBeInTheDocument()
    expect(cards[0].querySelector(`time[datetime="${application().updatedAt}"]`)).toBeInTheDocument()
    expect(screen.getAllByRole('button', { name: 'Start review' })).toHaveLength(1)
    expect(screen.queryByRole('button', { name: 'Approve' })).not.toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Application validation' })).not.toBeInTheDocument()
    await userEvent.click(within(cards[2]).getByRole('button', { name: 'Details' }))
    expect(within(cards[2]).getByText('Tenant update required')).toBeInTheDocument()
    expect(within(cards[2]).getByText('Upload a clearer identity document.')).toBeInTheDocument()
  })

  it('shows API-backed document details in a readable review section', async () => {
    const currentApplication = application()
    const document = {
      id: '44444444-4444-4444-4444-444444444444',
      applicationId: currentApplication.id,
      documentType: 1,
      originalFileName: 'income-proof-september.pdf',
      contentType: 'application/pdf',
      fileSizeBytes: 204800,
      uploadedAt: '2026-09-11T11:20:00Z',
    }
    mockApplicationApi([currentApplication], { documents: [document] })

    renderPage()
    await userEvent.click(await screen.findByRole('button', { name: 'Details' }))
    await userEvent.click(
      await screen.findByRole('button', {
        name: `Review documents for application ${currentApplication.id}`,
      }),
    )

    const review = await screen.findByRole('region', {
      name: 'Application documents',
    })
    expect(within(review).getByText('1 document')).toBeInTheDocument()
    expect(within(review).getByText('Income proof')).toBeInTheDocument()
    expect(within(review).getByText(document.originalFileName)).toBeInTheDocument()
    expect(within(review).getByText(document.id)).toBeInTheDocument()
    expect(within(review).getByText('application/pdf')).toBeInTheDocument()
    expect(within(review).getByRole('button', { name: 'Open document' })).toBeInTheDocument()
  })

  it('opens AI Validation on the property-scoped full report route', async () => {
    mockApplicationApi([application()])
    renderPage()
    const link = await screen.findByRole('link', {
      name: `AI Validation for application ${application().id}`,
    })
    expect(link).toHaveAttribute(
      'href',
      `/properties/${propertyId}/rental-applications/${application().id}/validation`,
    )
    expect(screen.queryByRole('region', { name: 'Application validation' })).not.toBeInTheDocument()
  })

  it('uses an AI Review heading only on the AI Review route', async () => {
    mockApplicationApi([])
    renderPage(propertyId, 'ai-review')
    expect(await screen.findByRole('heading', { name: 'AI Review' })).toBeInTheDocument()
    expect(screen.getByText('Review application validation findings and supporting documents before making a decision.')).toBeInTheDocument()

    cleanup()
    mockApplicationApi([])
    renderPage(propertyId, `/properties/${propertyId}/ai-review`)
    expect(await screen.findByRole('heading', { name: 'AI Review' })).toBeInTheDocument()

    cleanup()
    mockApplicationApi([])
    renderPage()
    expect(await screen.findByRole('heading', { name: 'Rental Applications' })).toBeInTheDocument()
    expect(screen.getByText('Track tenant applications, review documents and validation findings, and make the final landlord decision.')).toBeInTheDocument()
  })

  it('keeps Details inline while AI Validation remains a dedicated navigation target', async () => {
    mockApplicationApi([application()])
    renderPage()
    const details = await screen.findByRole('button', { name: 'Details' })
    const validation = screen.getByRole('link', { name: `AI Validation for application ${application().id}` })

    expect(details).toHaveAttribute('aria-expanded', 'false')
    expect(details).toHaveAttribute('aria-controls', `application-details-${application().id}`)
    expect(validation).toHaveAttribute('href', `/properties/${propertyId}/rental-applications/${application().id}/validation`)

    await userEvent.click(details)
    expect(details).toHaveAttribute('aria-expanded', 'true')
    expect(document.getElementById(details.getAttribute('aria-controls'))).toBeInTheDocument()
  })

  it('shows retryable page errors and a genuine empty state', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse({}, 500))
      .mockResolvedValueOnce(jsonResponse([]))
    vi.stubGlobal('fetch', fetchMock)

    renderPage()
    expect(screen.getByText('Loading rental applications')).toBeInTheDocument()
    expect(
      await screen.findByRole('heading', { name: 'We could not load the applications' }),
    ).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))

    expect(
      await screen.findByRole('heading', { name: 'No rental applications yet' }),
    ).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(2)
    const counts = screen.getByRole('group', { name: 'Rental application counts' })
    expect(within(counts).getByText('Total').parentElement).toHaveTextContent('0')
    expect(within(counts).getByText('Awaiting review').parentElement).toHaveTextContent('0')
  })

  it('combines the supported status filters with search over real returned fields', async () => {
    const secondTenantId = '99999999-9999-9999-9999-999999999999'
    mockApplicationApi([
      application({ id: 'first', tenantId, status: 1 }),
      application({ id: 'second', tenantId: secondTenantId, status: 2, occupation: 'Architect' }),
      application({ id: 'third', tenantId: secondTenantId, status: 4, occupation: 'Product designer' }),
    ])
    renderPage()
    const list = await screen.findByRole('region', { name: 'Rental applications' })
    const filters = screen.getByRole('group', { name: 'Filter applications by status' })
    expect(within(filters).getAllByRole('button').map((button) => button.textContent)).toEqual([
      'All', 'Submitted', 'Under Review', 'Changes Requested', 'Approved', 'Rejected',
    ])
    expect(within(list).getAllByRole('article')).toHaveLength(3)
    await userEvent.type(screen.getByRole('searchbox', { name: 'Search rental applications' }), '99999999')
    expect(within(list).getAllByRole('article')).toHaveLength(2)
    await userEvent.click(within(filters).getByRole('button', { name: 'Under Review' }))
    expect(within(list).getAllByRole('article')).toHaveLength(1)
    expect(within(list).getByText('Architect')).toBeInTheDocument()
    expect(within(filters).getByRole('button', { name: 'Under Review' })).toHaveAttribute('aria-pressed', 'true')
    await userEvent.clear(screen.getByRole('searchbox', { name: 'Search rental applications' }))
    await userEvent.type(screen.getByRole('searchbox', { name: 'Search rental applications' }), 'Architect')
    expect(within(list).getByText('Architect')).toBeInTheDocument()
    await userEvent.clear(screen.getByRole('searchbox', { name: 'Search rental applications' }))
    await userEvent.click(within(filters).getByRole('button', { name: 'All' }))
    expect(within(screen.getByRole('region', { name: 'Rental applications' })).getAllByRole('article')).toHaveLength(3)
    expect(within(filters).getByRole('button', { name: 'All' })).toHaveAttribute('aria-pressed', 'true')
    expect(within(screen.getByRole('group', { name: 'Rental application counts' })).getByText('Total').parentElement).toHaveTextContent('3')
  })

  it('refreshes the scoped list and removes stale cards', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(jsonResponse([application()]))
      .mockResolvedValueOnce(jsonResponse([]))
    vi.stubGlobal('fetch', fetchMock)
    renderPage()
    expect(await screen.findByRole('region', { name: 'Rental applications' })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Refresh' }))
    expect(await screen.findByRole('heading', { name: 'No rental applications yet' })).toBeInTheDocument()
    expect(screen.queryByRole('article')).not.toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(2)
    for (const [url] of fetchMock.mock.calls) expect(url).toContain(`/api/rental-applications/property/${propertyId}`)
  })

  it('starts review only for a submitted application through the existing transition', async () => {
    const submitted = application()
    const fetchMock = mockApplicationApi([submitted], { actionResponse: application({ status: 2 }) })
    renderPage()
    await userEvent.click(await screen.findByRole('button', { name: 'Start review' }))
    expect(await screen.findByRole('status')).toHaveTextContent('Application marked as under review.')
    expect(screen.getByLabelText('Application status: Under review')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Start review' })).not.toBeInTheDocument()
    const patchCall = fetchMock.mock.calls.find(([, request]) => request?.method === 'PATCH')
    expect(patchCall[0]).toContain(`/api/rental-applications/${submitted.id}/review`)
  })

  it('rejects a response for another property without rendering its records', async () => {
    mockApplicationApi([application({ propertyId: '99999999-9999-9999-9999-999999999999' })])
    renderPage()
    expect(await screen.findByRole('heading', { name: 'We could not load the applications' })).toBeInTheDocument()
    expect(screen.queryByRole('article')).not.toBeInTheDocument()
  })

  it('rejects duplicate applications from the scoped endpoint', async () => {
    const duplicate = application()
    mockApplicationApi([duplicate, { ...duplicate }])
    renderPage()

    expect(await screen.findByRole('heading', { name: 'We could not load the applications' })).toBeInTheDocument()
    expect(screen.queryByRole('article')).not.toBeInTheDocument()
  })

  it('does not show a successful transition for a mismatched mutation response', async () => {
    const submitted = application()
    mockApplicationApi([submitted], {
      actionResponse: application({ id: 'different-application', status: 2 }),
    })
    renderPage()

    await userEvent.click(await screen.findByRole('button', { name: 'Start review' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Unable to update this rental application. Please try again.',
    )
    expect(screen.getByLabelText('Application status: Submitted')).toBeInTheDocument()
    expect(screen.queryByText('Application marked as under review.')).not.toBeInTheDocument()
  })

  it('keeps decision feedback and action availability aligned with API state', async () => {
    const submitted = application()
    const approved = application({ status: 4, landlordResponse: 'Application approved after review.' })
    const fetchMock = mockApplicationApi([submitted], { actionResponse: approved })

    renderPage()
    await userEvent.click(await screen.findByRole('button', { name: 'Details' }))
    await userEvent.click(await screen.findByRole('button', { name: 'Approve' }))
    await userEvent.type(
      screen.getByLabelText('Response (optional)'),
      'Application approved after review.',
    )
    await userEvent.click(screen.getByRole('button', { name: 'Confirm' }))

    expect(await screen.findByRole('status')).toHaveTextContent('Application approved.')
    expect(screen.getAllByLabelText('Application status: Approved')).toHaveLength(2)
    expect(screen.queryByRole('button', { name: 'Approve' })).not.toBeInTheDocument()
    const patchCall = fetchMock.mock.calls.find(([, request]) => request?.method === 'PATCH')
    expect(patchCall[0]).toContain(`/api/rental-applications/${submitted.id}/approve`)
    expect(JSON.parse(patchCall[1].body)).toEqual({
      landlordResponse: 'Application approved after review.',
    })
  })

  it('requires a property selection without calling the API with a fallback ID', () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    renderPage(null)

    expect(
      screen.getByRole('heading', { name: 'Select a property' }),
    ).toBeInTheDocument()
    expect(screen.getByText(/Choose one of your owned properties/)).toBeInTheDocument()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('treats a malformed property reference as unselected', () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)
    renderPage('not-a-property-id')
    expect(screen.getByRole('heading', { name: 'Select a property' })).toBeInTheDocument()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('rejects a property outside the authenticated ownership context without loading applications', () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)
    renderPage(propertyId, 'rental-applications', [{ ...property, id: '99999999-9999-9999-9999-999999999999' }])
    expect(screen.getByRole('heading', { name: 'Property unavailable' })).toBeInTheDocument()
    expect(fetchMock).not.toHaveBeenCalled()
  })
})
