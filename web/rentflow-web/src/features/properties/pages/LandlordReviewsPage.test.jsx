import { cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import { apiRequest } from '../../../core/api/apiClient.js'
import LandlordReviewsPage from './LandlordReviewsPage.jsx'

vi.mock('../../../core/api/apiClient.js', async (importOriginal) => ({ ...await importOriginal(), apiRequest: vi.fn() }))
beforeEach(() => vi.resetAllMocks())
afterEach(cleanup)
const written = { rating: 4, comment: 'Helpful explanation.', reviewMonth: '2026-09', tenantId: 'secret-author', email: 'private@example.test', viewingId: 'private-viewing', createdAt: '2026-09-23T12:30:00Z' }
const data = {
  landlord: { averageRating: 4.8, reviewCount: 12, reviews: [written] },
  properties: [{ propertyId: 'owned-home', title: 'Owned home', averageRating: 3.5, reviewCount: 1, recentReviews: [{ ...written, comment: 'Property matched the listing.' }, { ...written, comment: ' ' }] }],
}
it('shows own dimensional aggregates and written comments only, with no identity or mutation controls', async () => {
  apiRequest.mockResolvedValue(data)
  const { container } = render(<LandlordReviewsPage />)
  const landlord = await screen.findByRole('region', { name: 'Your landlord experience' })
  expect(within(landlord).getByLabelText('4.8 out of 5')).toBeInTheDocument()
  expect(within(landlord).getByText('12 verified viewings')).toBeInTheDocument()
  const property = screen.getByRole('region', { name: 'Owned home' })
  expect(within(property).getByLabelText('3.5 out of 5')).toBeInTheDocument()
  expect(within(property).getByText('1 verified viewing')).toBeInTheDocument()
  expect(within(property).getAllByRole('article')).toHaveLength(1)
  expect(screen.getAllByText('Verified viewing · Sep 2026')).toHaveLength(2)
  expect(container.textContent).not.toMatch(/secret-author|private@example|private-viewing|12:30|Delete|Hide|Edit/)
  expect(screen.queryAllByRole('button')).toHaveLength(0)
  expect(apiRequest).toHaveBeenCalledTimes(1)
  expect(apiRequest).toHaveBeenCalledWith('/api/landlord/viewing-reviews/summary', expect.not.objectContaining({ authenticated: false }))
})
it('shows a truthful empty state without fake zero stars', async () => {
  apiRequest.mockResolvedValue({ landlord: { averageRating: null, reviewCount: 0, reviews: [] }, properties: [] })
  render(<LandlordReviewsPage />)
  expect(await screen.findByText('No viewing feedback yet')).toBeInTheDocument()
  expect(screen.getByText('Verified feedback will appear here after tenants complete viewings and leave a review.')).toBeInTheDocument()
  expect(screen.queryByText(/0.0/)).not.toBeInTheDocument()
})
it('shows failure and retries instead of claiming there is no feedback', async () => {
  apiRequest.mockRejectedValueOnce(new Error('Unavailable')).mockResolvedValueOnce(data)
  render(<LandlordReviewsPage />)
  expect(await screen.findByRole('alert')).toHaveTextContent('Could not load viewing feedback.')
  expect(screen.queryByText('No viewing feedback yet')).not.toBeInTheDocument()
  await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
  expect(await screen.findByText('Your landlord experience')).toBeInTheDocument()
  expect(apiRequest).toHaveBeenCalledTimes(2)
})
