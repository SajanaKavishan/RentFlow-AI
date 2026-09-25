import { act, cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createSupportTicket, getMySupportTickets } from '../../features/supportTickets/supportTicketsApi.js'
import SupportRequestsSection from './SupportRequestsSection.jsx'

vi.mock('../../features/supportTickets/supportTicketsApi.js', () => ({
  SUPPORT_CATEGORIES: [
    { value: 'TechnicalIssue', label: 'Technical issue' },
    { value: 'AccountLogin', label: 'Account or login' },
    { value: 'PropertyApplication', label: 'Property or application' },
    { value: 'Payment', label: 'Payment' },
    { value: 'Other', label: 'Other' },
  ],
  createSupportTicket: vi.fn(),
  getMySupportTickets: vi.fn(),
}))

const existingTicket = {
  id: '11111111-1111-1111-1111-111111111111',
  category: 'Payment',
  subject: 'Payment receipt missing',
  message: 'I need a receipt for my payment.',
  status: 'Open',
  createdAt: '2026-09-25T10:00:00Z',
  updatedAt: '2026-09-25T10:00:00Z',
}

beforeEach(() => {
  getMySupportTickets.mockResolvedValue([existingTicket])
  createSupportTicket.mockReset()
})
afterEach(() => { cleanup(); vi.restoreAllMocks() })

describe('profile support requests', () => {
  it('loads and displays only ticket data returned by the authenticated API', async () => {
    render(<SupportRequestsSection />)

    expect(screen.getByText('Loading support requests…')).toBeInTheDocument()
    expect(await screen.findByText('Payment receipt missing')).toBeInTheDocument()
    expect(screen.getByText(/Payment ·/)).toBeInTheDocument()
    expect(screen.getByText('Open')).toBeInTheDocument()
    expect(getMySupportTickets).toHaveBeenCalledTimes(1)
  })

  it('opens an accessible form and validates whitespace before submitting', async () => {
    render(<SupportRequestsSection />)
    await screen.findByText('Payment receipt missing')
    await userEvent.click(screen.getByRole('button', { name: /Contact support/ }))
    const dialog = screen.getByRole('dialog', { name: 'Contact support' })

    expect(dialog).toHaveAttribute('aria-modal', 'true')
    expect(within(dialog).getByLabelText('Category')).toHaveFocus()
    await userEvent.selectOptions(within(dialog).getByLabelText('Category'), 'TechnicalIssue')
    await userEvent.type(within(dialog).getByLabelText('Subject'), '   ')
    await userEvent.type(within(dialog).getByLabelText('Message'), 'A useful message')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Submit request' }))

    expect(within(dialog).getByRole('alert')).toHaveTextContent('Enter a subject.')
    expect(createSupportTicket).not.toHaveBeenCalled()
  })

  it('does not claim success or add a ticket until creation is confirmed', async () => {
    let confirmCreation
    createSupportTicket.mockReturnValue(new Promise((resolve) => { confirmCreation = resolve }))
    const created = {
      ...existingTicket,
      id: '22222222-2222-2222-2222-222222222222',
      category: 'AccountLogin',
      subject: 'Cannot sign in',
      message: 'The login form returns an error.',
      createdAt: '2026-09-26T10:00:00Z',
      updatedAt: '2026-09-26T10:00:00Z',
    }
    render(<SupportRequestsSection />)
    await screen.findByText('Payment receipt missing')
    await userEvent.click(screen.getByRole('button', { name: /Contact support/ }))
    const dialog = screen.getByRole('dialog', { name: 'Contact support' })
    await userEvent.selectOptions(within(dialog).getByLabelText('Category'), 'AccountLogin')
    await userEvent.type(within(dialog).getByLabelText('Subject'), '  Cannot sign in  ')
    await userEvent.type(within(dialog).getByLabelText('Message'), '  The login form returns an error.  ')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Submit request' }))

    expect(createSupportTicket).toHaveBeenCalledWith({
      category: 'AccountLogin',
      subject: 'Cannot sign in',
      message: 'The login form returns an error.',
    })
    expect(within(dialog).getByRole('button', { name: 'Submitting…' })).toBeDisabled()
    expect(within(dialog).queryByText('Request submitted')).not.toBeInTheDocument()
    expect(screen.queryByText('Cannot sign in')).not.toBeInTheDocument()

    await act(async () => confirmCreation(created))
    expect(await within(dialog).findByRole('heading', { name: 'Request submitted' })).toBeInTheDocument()
    expect(screen.getByText('Cannot sign in')).toBeInTheDocument()
  })

  it('keeps entered data on API errors and supports list retries', async () => {
    getMySupportTickets.mockRejectedValueOnce(new Error('Support list unavailable.'))
      .mockResolvedValueOnce([])
    createSupportTicket.mockRejectedValue(new Error('Support service unavailable.'))
    render(<SupportRequestsSection />)

    expect(await screen.findByRole('alert')).toHaveTextContent('Support list unavailable.')
    await userEvent.click(screen.getByRole('button', { name: 'Retry' }))
    await waitFor(() => expect(screen.getByText('No support requests yet.')).toBeInTheDocument())

    await userEvent.click(screen.getByRole('button', { name: /Contact support/ }))
    const dialog = screen.getByRole('dialog', { name: 'Contact support' })
    await userEvent.selectOptions(within(dialog).getByLabelText('Category'), 'Other')
    await userEvent.type(within(dialog).getByLabelText('Subject'), 'Need help')
    await userEvent.type(within(dialog).getByLabelText('Message'), 'Please help with my account.')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Submit request' }))

    expect(await within(dialog).findByRole('alert')).toHaveTextContent('Support service unavailable.')
    expect(within(dialog).getByLabelText('Subject')).toHaveValue('Need help')
    expect(within(dialog).getByLabelText('Message')).toHaveValue('Please help with my account.')
  })
})
