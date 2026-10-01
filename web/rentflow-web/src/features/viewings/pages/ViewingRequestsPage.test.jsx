import { act, cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import OwnedPropertiesContext from '../../../shared/property/OwnedPropertiesContext.js'
import ViewingRequestsPage from './ViewingRequestsPage.jsx'

const tenantId = '11111111-1111-1111-1111-111111111112'
const propertyId = '22222222-2222-2222-2222-222222222222'
const property = {
  id: propertyId,
  title: 'Harbour View Residence',
  address: '18 Marine Drive',
  city: 'Colombo',
  isAvailable: true,
}

const pendingViewing = {
  id: 'pending-viewing',
  tenantId,
  propertyId,
  requestedDateTime: '2030-01-02T10:00:00Z',
  status: 0,
  tenantMessage: 'Could I see the storage space during the viewing?',
  landlordResponse: null,
  createdAt: '2026-09-14T10:00:00Z',
  updatedAt: null,
}

const approvedViewing = {
  ...pendingViewing,
  id: 'approved-viewing',
  tenantId: '33333333-3333-3333-3333-333333333333',
  status: 1,
  tenantMessage: null,
  landlordResponse: 'The storage space will be available to inspect.',
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function renderPage(selectedPropertyId = propertyId, properties = [property]) {
  const entry = selectedPropertyId
    ? `/properties/${selectedPropertyId}/viewing-requests`
    : '/viewing-requests'

  return render(
    <OwnedPropertiesContext.Provider value={{
      status: 'ready',
      properties,
      error: '',
      retry: vi.fn(),
    }}>
      <MemoryRouter initialEntries={[entry]}>
        <Routes>
          <Route path="/viewing-requests" element={<ViewingRequestsPage />} />
          <Route
            path="/properties/:propertyId/viewing-requests"
            element={<ViewingRequestsPage />}
          />
        </Routes>
      </MemoryRouter>
    </OwnedPropertiesContext.Provider>,
  )
}

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

describe('Landlord viewing requests', () => {
  it('uses the page title without a redundant workspace eyebrow', () => {
    renderPage(null)
    expect(screen.getByRole('heading', { name: 'Viewing Requests' })).toBeInTheDocument()
    expect(screen.queryByText('Landlord workspace')).not.toBeInTheDocument()
  })

  it('prioritizes pending requests and shows real references and messages', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(jsonResponse([approvedViewing, pendingViewing])),
    )

    renderPage()

    const cards = await screen.findAllByRole('article')
    expect(fetch).toHaveBeenCalledWith(
      expect.stringContaining(`/api/viewings/property/${propertyId}`),
      expect.any(Object),
    )
    expect(cards).toHaveLength(2)
    expect(screen.getByRole('link', { name: 'Back to Property' }))
      .toHaveAttribute('href', `/properties/${propertyId}`)
    expect(screen.getByRole('group', { name: 'Selected property' }))
      .toHaveTextContent('Harbour View Residence18 Marine Drive, Colombo')
    const counts = screen.getByRole('group', { name: 'Viewing request counts' })
    expect(within(counts).getByText('Total').parentElement).toHaveTextContent('2')
    expect(within(counts).getByText('Pending').parentElement).toHaveTextContent('1')
    expect(within(cards[0]).getByText('Pending')).toBeInTheDocument()
    expect(within(cards[0]).getByText(tenantId)).toBeInTheDocument()
    expect(within(cards[0]).getByText('Harbour View Residence')).toBeInTheDocument()
    expect(within(cards[0]).getByText('18 Marine Drive, Colombo')).toBeInTheDocument()
    expect(within(cards[0]).getByText('Submitted').nextElementSibling)
      .toHaveAttribute('datetime', pendingViewing.createdAt)
    expect(
      within(cards[0]).getByText(
        'Could I see the storage space during the viewing?',
      ),
    ).toBeInTheDocument()
    expect(
      within(cards[1]).getByText(
        'The storage space will be available to inspect.',
      ),
    ).toBeInTheDocument()
    expect(screen.getAllByRole('button', { name: 'Approve request' }))
      .toHaveLength(1)
    expect(screen.getAllByRole('button', { name: 'Reject request' }))
      .toHaveLength(1)
    expect(within(cards[1]).queryByRole('button', { name: 'Approve request' }))
      .not.toBeInTheDocument()
    expect(within(cards[1]).queryByRole('button', { name: 'Reject request' }))
      .not.toBeInTheDocument()

    const statusFilters = screen.getByRole('group', { name: 'Request status' })
    expect(within(statusFilters).getAllByRole('button').map((button) => button.textContent))
      .toEqual(['All', 'Pending', 'Approved', 'Rejected'])
  })

  it('approves a pending request through the existing API action', async () => {
    let finishApproval
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse([pendingViewing]))
      .mockImplementationOnce(() => new Promise((resolve) => {
        finishApproval = () => resolve(jsonResponse({
          ...pendingViewing,
          status: 1,
          landlordResponse: 'The requested time works.',
        }))
      }))
    vi.stubGlobal('fetch', fetchMock)

    renderPage()
    await userEvent.click(
      await screen.findByRole('button', { name: 'Approve request' }),
    )
    await userEvent.type(
      screen.getByLabelText('Response (optional)'),
      'The requested time works.',
    )
    await userEvent.click(
      screen.getByRole('button', { name: 'Confirm approval' }),
    )

    expect(within(screen.getByRole('article')).getByText('Pending')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Saving…' })).toBeDisabled()

    await act(async () => { finishApproval() })

    expect(await screen.findByRole('status')).toHaveTextContent(
      'Viewing request approved.',
    )
    expect(within(screen.getByRole('article')).getByText('Approved')).toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: 'Approve request' }),
    ).not.toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to Property' }))
      .toHaveAttribute('href', `/properties/${propertyId}`)
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(fetchMock.mock.calls[1][0]).toContain(
      '/api/viewings/pending-viewing/approve',
    )
    expect(JSON.parse(fetchMock.mock.calls[1][1].body)).toEqual({
      status: 1,
      landlordResponse: 'The requested time works.',
    })
  })

  it('validates rejection and keeps API action errors with the request', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse([pendingViewing]))
      .mockResolvedValueOnce(
        jsonResponse(
          { detail: 'Only pending viewings can be rejected.' },
          409,
        ),
      )
    vi.stubGlobal('fetch', fetchMock)

    renderPage()
    await userEvent.click(
      await screen.findByRole('button', { name: 'Reject request' }),
    )
    await userEvent.click(
      screen.getByRole('button', { name: 'Confirm rejection' }),
    )

    expect(
      screen.getByText('Enter a reason before rejecting this request.'),
    ).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)

    await userEvent.type(
      screen.getByLabelText('Rejection reason'),
      'The property is unavailable at this time.',
    )
    await userEvent.click(
      screen.getByRole('button', { name: 'Confirm rejection' }),
    )

    expect(
      await screen.findByText('Only pending viewings can be rejected.'),
    ).toBeInTheDocument()
    expect(within(screen.getByRole('article')).getByText('Pending')).toBeInTheDocument()
    expect(screen.queryByText('Viewing request rejected.')).not.toBeInTheDocument()
  })

  it('shows loading, retryable error, and empty states without fake content', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse({}, 500))
      .mockResolvedValueOnce(jsonResponse([]))
    vi.stubGlobal('fetch', fetchMock)

    renderPage()
    expect(screen.getByText('Loading viewing requests')).toBeInTheDocument()

    expect(
      await screen.findByRole('heading', {
        name: "We couldn't load the requests",
      }),
    ).toBeInTheDocument()
    expect(
      screen.getByText('The viewing request failed. Please try again.'),
    ).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))

    expect(
      await screen.findByRole('heading', { name: 'No viewing requests yet' }),
    ).toBeInTheDocument()
    const counts = screen.getByRole('group', { name: 'Viewing request counts' })
    expect(within(counts).getByText('Total').parentElement).toHaveTextContent('0')
    expect(within(counts).getByText('Pending').parentElement).toHaveTextContent('0')
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('preserves an unauthorized Viewing API response without exposing request data', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse({}, 403)))

    renderPage()

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'You do not have permission to access this resource.',
    )
    expect(screen.queryByRole('article')).not.toBeInTheDocument()
  })

  it('rejects mismatched property records returned by the scoped endpoint', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse([{
      ...pendingViewing,
      propertyId: '99999999-9999-9999-9999-999999999999',
    }])))

    renderPage()

    expect(await screen.findByRole('heading', { name: "We couldn't load the requests" })).toBeInTheDocument()
    expect(screen.queryByRole('article')).not.toBeInTheDocument()
  })

  it('does not show a successful decision for a mismatched mutation response', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(jsonResponse([pendingViewing]))
      .mockResolvedValueOnce(jsonResponse({
        ...pendingViewing,
        id: 'different-viewing',
        status: 1,
      }))
    vi.stubGlobal('fetch', fetchMock)

    renderPage()
    await userEvent.click(await screen.findByRole('button', { name: 'Approve request' }))
    await userEvent.click(screen.getByRole('button', { name: 'Confirm approval' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Unable to update this viewing request. Please try again.',
    )
    expect(within(screen.getByRole('article')).getByText('Pending')).toBeInTheDocument()
    expect(screen.queryByText('Viewing request approved.')).not.toBeInTheDocument()
  })

  it('combines search and status filters over returned request data', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(jsonResponse([approvedViewing, pendingViewing])),
    )

    renderPage()
    await screen.findAllByRole('article')

    await userEvent.click(screen.getByRole('button', { name: 'Approved' }))
    expect(screen.getAllByRole('article')).toHaveLength(1)
    expect(screen.getByText('The storage space will be available to inspect.')).toBeInTheDocument()

    await userEvent.type(screen.getByRole('searchbox', { name: 'Search viewing requests' }), tenantId)
    expect(screen.getByText('No matching viewing requests')).toBeInTheDocument()
  })

  it('refreshes the same property scope and preserves the Back to Property route', async () => {
    const fetchMock = vi.fn().mockImplementation(() => (
      Promise.resolve(jsonResponse([pendingViewing]))
    ))
    vi.stubGlobal('fetch', fetchMock)

    renderPage()
    await screen.findByRole('article')
    await userEvent.click(screen.getByRole('button', { name: 'Refresh' }))
    await screen.findByRole('article')

    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(fetchMock.mock.calls.every(([url]) => (
      url.includes(`/api/viewings/property/${propertyId}`)
    ))).toBe(true)
    expect(screen.getByRole('link', { name: 'Back to Property' }))
      .toHaveAttribute('href', `/properties/${propertyId}`)
  })

  it('requires a property selection without calling the API with a fallback ID', () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    renderPage(null)

    expect(
      screen.getByRole('heading', { name: 'Select a property' }),
    ).toBeInTheDocument()
    expect(screen.getByText(/Choose one of your owned properties/)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Harbour View Residence/ }))
      .toHaveAttribute('href', `/properties/${propertyId}/viewing-requests`)
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('blocks a property outside the authenticated portfolio without loading requests', () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    renderPage('99999999-9999-9999-9999-999999999999')

    expect(screen.getByRole('heading', { name: 'Property unavailable' })).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'Back to Property' })).not.toBeInTheDocument()
    expect(fetchMock).not.toHaveBeenCalled()
  })
})
