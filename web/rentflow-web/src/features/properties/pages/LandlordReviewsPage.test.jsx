import { act, cleanup, render, screen, within } from '@testing-library/react'
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
  expect(screen.getByRole('button', { name: /Owned home/ })).toHaveAttribute('aria-pressed', 'true')
  expect(apiRequest).toHaveBeenCalledTimes(1)
  expect(apiRequest).toHaveBeenCalledWith('/api/landlord/viewing-reviews/summary', expect.not.objectContaining({ authenticated: false }))
})
it('shows a truthful empty state without fake zero stars', async () => {
  apiRequest.mockResolvedValue({ landlord: { averageRating: null, reviewCount: 0, reviews: [] }, properties: [] })
  render(<LandlordReviewsPage />)
  expect(await screen.findByRole('region', { name: 'Your landlord experience' })).toHaveTextContent('No verified viewing feedback yet.')
  expect(screen.getByText('Your owned properties will appear here.')).toBeInTheDocument()
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

const propertyReviews = Array.from({ length: 7 }, (_, index) => ({ ...written, comment: `Home feedback ${index + 1}` }))
const selectionData = {
  ...data,
  properties: [
    { ...data.properties[0], reviewCount: 7, recentReviews: propertyReviews.slice(0, 5) },
    { propertyId: 'garden-id', title: 'Garden apartment', averageRating: 5, reviewCount: 1, recentReviews: [{ ...written, rating: 5, comment: 'Garden feedback' }] },
    { propertyId: 'empty-id', title: 'New apartment', averageRating: null, reviewCount: 0, recentReviews: [] },
  ],
}
const fullSummary = { averageRating: 3.5, reviewCount: 7, reviews: propertyReviews }

it('selects real properties and renders feedback only for the highlighted selection', async () => {
  apiRequest.mockResolvedValue(selectionData)
  const { container } = render(<LandlordReviewsPage />)
  const first = await screen.findByRole('button', { name: /Owned home/ })
  const garden = screen.getByRole('button', { name: /Garden apartment/ })
  expect(first).toHaveAttribute('aria-pressed', 'true')
  expect(screen.queryByText('Garden feedback')).not.toBeInTheDocument()
  await userEvent.click(garden)
  expect(garden).toHaveAttribute('aria-pressed', 'true')
  expect(first).toHaveAttribute('aria-pressed', 'false')
  expect(screen.getByText('Garden feedback')).toBeInTheDocument()
  expect(screen.queryByText('Home feedback 1')).not.toBeInTheDocument()
  expect(screen.getByText('Helpful explanation.')).toBeInTheDocument()
  expect(container.textContent).not.toMatch(/owned-home|garden-id|empty-id|secret-author|private-viewing|private@example/)
})

it('shows three reviews initially and fetches the complete selected list on View all, with Show less', async () => {
  apiRequest.mockResolvedValueOnce(selectionData).mockResolvedValueOnce(fullSummary)
  render(<LandlordReviewsPage />)
  const property = await screen.findByRole('region', { name: 'Owned home' })
  expect(within(property).getAllByRole('article')).toHaveLength(3)
  expect(screen.queryByText('Home feedback 4')).not.toBeInTheDocument()
  expect(apiRequest).toHaveBeenCalledTimes(1)
  await userEvent.click(screen.getByRole('button', { name: 'View all reviews' }))
  expect(await screen.findByText('Home feedback 7')).toBeInTheDocument()
  expect(within(property).getAllByRole('article')).toHaveLength(7)
  expect(apiRequest).toHaveBeenLastCalledWith('/api/landlord/viewing-reviews/properties/owned-home', expect.not.objectContaining({ authenticated: false }))
  await userEvent.click(screen.getByRole('button', { name: 'Show less' }))
  expect(within(property).getAllByRole('article')).toHaveLength(3)
  expect(screen.queryByText('Home feedback 4')).not.toBeInTheDocument()
  expect(screen.getByRole('button', { name: 'View all reviews' })).toHaveAttribute('aria-expanded', 'false')
})

it('shows a compact empty state for a zero-review selection without fabricated ratings', async () => {
  apiRequest.mockResolvedValue(selectionData)
  render(<LandlordReviewsPage />)
  await userEvent.click(await screen.findByRole('button', { name: /New apartment/ }))
  const property = screen.getByRole('region', { name: 'New apartment' })
  expect(within(property).getByText('No verified viewing feedback yet.')).toBeInTheDocument()
  expect(within(property).queryAllByRole('article')).toHaveLength(0)
  expect(within(property).queryByLabelText(/out of 5/)).not.toBeInTheDocument()
  expect(screen.queryByRole('button', { name: 'View all reviews' })).not.toBeInTheDocument()
})

it('discards an in-flight expanded response when selecting another property', async () => {
  let resolveFull
  apiRequest.mockResolvedValueOnce(selectionData).mockImplementationOnce(() => new Promise((resolve) => { resolveFull = resolve }))
  render(<LandlordReviewsPage />)
  await userEvent.click(await screen.findByRole('button', { name: 'View all reviews' }))
  expect(screen.getByRole('status')).toHaveTextContent('Loading all property reviews')
  await userEvent.click(screen.getByRole('button', { name: /Garden apartment/ }))
  await act(async () => resolveFull(fullSummary))
  expect(screen.getByText('Garden feedback')).toBeInTheDocument()
  expect(screen.queryByText('Home feedback 7')).not.toBeInTheDocument()
})

it('retries full-list errors while retaining the three-review preview', async () => {
  apiRequest.mockResolvedValueOnce(selectionData).mockRejectedValueOnce(new Error('Unavailable')).mockResolvedValueOnce(fullSummary)
  render(<LandlordReviewsPage />)
  await userEvent.click(await screen.findByRole('button', { name: 'View all reviews' }))
  expect(await screen.findByRole('alert')).toHaveTextContent('Could not load all property reviews.')
  expect(within(screen.getByRole('region', { name: 'Owned home' })).getAllByRole('article')).toHaveLength(3)
  await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
  expect(await screen.findByText('Home feedback 7')).toBeInTheDocument()
})
