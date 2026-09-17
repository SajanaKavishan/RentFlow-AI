import { cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import ViewingRequestsPage from './ViewingRequestsPage.jsx'

const tenantId = '11111111-1111-1111-1111-111111111112'
const propertyId = '22222222-2222-2222-2222-222222222222'

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

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

describe('Landlord viewing requests', () => {
  it('prioritizes pending requests and shows real references and messages', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(jsonResponse([approvedViewing, pendingViewing])),
    )

    render(<ViewingRequestsPage />)

    const cards = await screen.findAllByRole('article')
    expect(cards).toHaveLength(2)
    expect(within(cards[0]).getByText('Pending')).toBeInTheDocument()
    expect(within(cards[0]).getByText(tenantId)).toBeInTheDocument()
    expect(within(cards[0]).getByText(propertyId)).toBeInTheDocument()
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
    expect(screen.getByText('1', { selector: '.viewings-summary__number' }))
      .toBeInTheDocument()
    expect(screen.getAllByRole('button', { name: 'Approve request' }))
      .toHaveLength(1)
    expect(screen.getAllByRole('button', { name: 'Reject request' }))
      .toHaveLength(1)
  })

  it('approves a pending request through the existing API action', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse([pendingViewing]))
      .mockResolvedValueOnce(
        jsonResponse({
          ...pendingViewing,
          status: 1,
          landlordResponse: 'The requested time works.',
        }),
      )
    vi.stubGlobal('fetch', fetchMock)

    render(<ViewingRequestsPage />)
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

    expect(await screen.findByRole('status')).toHaveTextContent(
      'Viewing request approved.',
    )
    expect(screen.getByText('Approved')).toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: 'Approve request' }),
    ).not.toBeInTheDocument()
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

    render(<ViewingRequestsPage />)
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
    expect(screen.getByText('Pending')).toBeInTheDocument()
    expect(screen.queryByText('Viewing request rejected.')).not.toBeInTheDocument()
  })

  it('shows loading, retryable error, and empty states without fake content', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse({}, 500))
      .mockResolvedValueOnce(jsonResponse([]))
    vi.stubGlobal('fetch', fetchMock)

    render(<ViewingRequestsPage />)
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
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })
})
