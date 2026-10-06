import { act, cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes, useNavigate } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import OwnedPropertiesContext from '../../../shared/property/OwnedPropertiesContext.js'
import RentalApplicationsPage from '../pages/RentalApplicationsPage.jsx'
import { getOwnedPropertyApplicationActionCounts, getApplicationsByProperty } from '../services/rentalApplicationApiService.js'
import { getPropertyImages, getPropertyImageUrl } from '../../properties/services/propertyApiService.js'
import ApplicationPropertySelector from './ApplicationPropertySelector.jsx'

vi.mock('../services/rentalApplicationApiService.js', async (importOriginal) => ({
  ...await importOriginal(),
  getOwnedPropertyApplicationActionCounts: vi.fn(),
  getApplicationsByProperty: vi.fn(),
}))
vi.mock('../../properties/services/propertyApiService.js', () => ({
  getPropertyImages: vi.fn(), getPropertyImageUrl: vi.fn(),
}))

const properties = [
  { id: '22222222-2222-2222-2222-222222222222', title: 'Port city residence', address: '18 Marine Drive', city: 'Colombo' },
  { id: '33333333-3333-3333-3333-333333333333', title: 'Garden home', address: '7 Park Road', city: 'Kandy' },
  { id: '44444444-4444-4444-4444-444444444444', title: 'Hill cottage', address: '3 Hill Lane', city: 'Galle' },
]
const ready = { status: 'ready', properties, retry: vi.fn() }

function BackButton() {
  const navigate = useNavigate()
  return <button onClick={() => navigate(-1)}>Browser back</button>
}

function setup(collection = ready, page = false) {
  return render(<OwnedPropertiesContext.Provider value={collection}>
    <MemoryRouter initialEntries={['/rental-applications']}>
      <BackButton />
      <Routes>
        <Route path="/rental-applications" element={page ? <RentalApplicationsPage /> : <ApplicationPropertySelector />} />
        <Route path="/properties/:propertyId/rental-applications" element={<RentalApplicationsPage />} />
      </Routes>
    </MemoryRouter>
  </OwnedPropertiesContext.Provider>)
}

beforeEach(() => {
  vi.clearAllMocks()
  getOwnedPropertyApplicationActionCounts.mockResolvedValue([
    { propertyId: properties[0].id, actionRequiredCount: 2 },
    { propertyId: properties[1].id, actionRequiredCount: 1 },
  ])
  getPropertyImages.mockResolvedValue([])
  getPropertyImageUrl.mockResolvedValue({ url: 'https://images.example.test/cover.jpg' })
  getApplicationsByProperty.mockResolvedValue([])
})
afterEach(cleanup)

describe('Rental application property cards', () => {
  it('renders owned properties with independent counts and no attention badge for zero', async () => {
    setup()
    const first = await screen.findByRole('button', { name: 'Port city residence, 2 rental applications need attention' })
    expect(within(first).getByText('2 to review')).toBeInTheDocument()
    expect(first).toHaveTextContent('18 Marine Drive, Colombo')
    expect(first).toHaveTextContent('2 applications need your attention')
    const second = screen.getByRole('button', { name: 'Garden home, 1 rental application needs attention' })
    expect(second).toHaveTextContent('1 application needs your attention')
    const zero = screen.getByRole('button', { name: 'Hill cottage, 0 rental applications need attention' })
    expect(zero).toHaveTextContent('No applications need your attention')
    expect(zero.querySelector('.workspace-property-card__badge')).toBeNull()
    expect(getOwnedPropertyApplicationActionCounts).toHaveBeenCalledTimes(1)
    expect(getApplicationsByProperty).not.toHaveBeenCalled()
  })

  it('uses the real primary photo, first photo fallback, and decorative building fallback', async () => {
    getPropertyImages.mockImplementation((id) => Promise.resolve(id === properties[0].id
      ? [{ id: 'first' }, { id: 'cover', isPrimary: true }]
      : id === properties[1].id ? [{ id: 'garden' }] : []))
    setup()
    const image = await screen.findByRole('img', { name: 'Port city residence — property photo' })
    expect(image).toHaveAttribute('src', 'https://images.example.test/cover.jpg')
    expect(image).toHaveAttribute('loading', 'lazy')
    expect(getPropertyImageUrl).toHaveBeenCalledWith(properties[0].id, 'cover')
    expect(getPropertyImageUrl).toHaveBeenCalledWith(properties[1].id, 'garden')
    const zero = screen.getByRole('button', { name: 'Hill cottage, 0 rental applications need attention' })
    expect(zero.querySelector('.workspace-property-card__fallback')).toHaveAttribute('aria-hidden', 'true')
    fireEvent.error(image)
    expect(screen.queryByRole('img', { name: /Port city/ })).not.toBeInTheDocument()
  })

  it.each(['click', 'Enter', ' '])('opens the exact existing workspace using %s and preserves return navigation', async (method) => {
    setup(ready, true)
    const card = await screen.findByRole('button', { name: 'Garden home, 1 rental application needs attention' })
    if (method === 'click') await userEvent.click(card)
    else { card.focus(); await userEvent.keyboard(method === 'Enter' ? '{Enter}' : ' ') }
    expect(await screen.findByText('No rental applications yet')).toBeInTheDocument()
    expect(getApplicationsByProperty).toHaveBeenCalledWith(properties[1].id)
    expect(screen.getByRole('group', { name: 'Selected property' })).toHaveTextContent('Garden home')
    expect(screen.getByRole('link', { name: 'Change property' })).toHaveAttribute('href', '/rental-applications')
    await userEvent.click(screen.getByRole('button', { name: 'Browser back' }))
    expect(await screen.findByRole('button', { name: 'Garden home, 1 rental application needs attention' })).toBeInTheDocument()
  })

  it('keeps cards usable during count loading and retries count errors without false zero', async () => {
    let rejectCounts
    getOwnedPropertyApplicationActionCounts.mockReturnValueOnce(new Promise((_, reject) => { rejectCounts = reject }))
    setup()
    expect(screen.getByText('Loading application review counts…')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Port city residence, rental application review count unavailable' })).toBeEnabled()
    expect(screen.queryByText('No applications need your attention')).not.toBeInTheDocument()
    await act(async () => rejectCounts(new Error('Unavailable')))
    expect(screen.getByText(/You can still open a property/)).toBeInTheDocument()
    expect(screen.queryByText('No applications need your attention')).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Retry counts' }))
    expect(await screen.findByRole('button', { name: 'Port city residence, 2 rental applications need attention' })).toBeInTheDocument()
  })

  it.each([null, [{ propertyId: properties[0].id, actionRequiredCount: -1 }], [
    { propertyId: properties[0].id, actionRequiredCount: 2 }, { propertyId: properties[0].id, actionRequiredCount: 3 },
  ]])('treats malformed summary %j as unavailable', async (rows) => {
    getOwnedPropertyApplicationActionCounts.mockResolvedValue(rows)
    setup()
    expect(await screen.findByText(/You can still open a property/)).toBeInTheDocument()
    expect(screen.queryByText('No applications need your attention')).not.toBeInTheDocument()
  })

  it('opens a property when the count service is unavailable', async () => {
    getOwnedPropertyApplicationActionCounts.mockRejectedValue(new Error('Unavailable'))
    setup(ready, true)
    await screen.findByText(/You can still open a property/)
    await userEvent.click(screen.getByRole('button', { name: 'Port city residence, rental application review count unavailable' }))
    expect(await screen.findByText('No rental applications yet')).toBeInTheDocument()
    expect(getApplicationsByProperty).toHaveBeenCalledWith(properties[0].id)
  })

  it('refreshes summary counts after returning from the property workspace', async () => {
    getOwnedPropertyApplicationActionCounts.mockResolvedValueOnce([{ propertyId: properties[0].id, actionRequiredCount: 2 }])
      .mockResolvedValueOnce([])
    setup(ready, true)
    await userEvent.click(await screen.findByRole('button', { name: 'Port city residence, 2 rental applications need attention' }))
    await screen.findByText('No rental applications yet')
    await userEvent.click(screen.getByRole('link', { name: 'Change property' }))
    const card = await screen.findByRole('button', { name: 'Port city residence, 0 rental applications need attention' })
    expect(card.querySelector('.workspace-property-card__badge')).toBeNull()
    expect(getOwnedPropertyApplicationActionCounts).toHaveBeenCalledTimes(2)
  })

  it('refreshes property-card counts once through the page Refresh without requesting every application list', async () => {
    let finishRefresh
    getOwnedPropertyApplicationActionCounts.mockResolvedValueOnce([{ propertyId: properties[0].id, actionRequiredCount: 2 }])
      .mockReturnValueOnce(new Promise((resolve) => { finishRefresh = resolve }))
    setup(ready, true)
    await screen.findByRole('button', { name: 'Port city residence, 2 rental applications need attention' })
    await userEvent.click(screen.getByRole('button', { name: 'Refresh' }))
    expect(screen.getByText('Loading application review counts…')).toBeInTheDocument()
    expect(screen.queryByText('No applications need your attention')).not.toBeInTheDocument()
    expect(getOwnedPropertyApplicationActionCounts).toHaveBeenCalledTimes(2)
    expect(getApplicationsByProperty).not.toHaveBeenCalled()
    await act(async () => finishRefresh([{ propertyId: properties[0].id, actionRequiredCount: 1 }]))
    expect(await screen.findByRole('button', { name: 'Port city residence, 1 rental application needs attention' })).toBeInTheDocument()
    expect(getPropertyImages).toHaveBeenCalledTimes(3)
  })

  it.each([
    [{ status: 'loading', properties: [] }, 'Loading your properties'],
    [{ status: 'error', properties: [], error: 'Please retry', retry: vi.fn() }, 'We could not load your properties'],
    [{ status: 'ready', properties: [] }, 'No owned properties'],
  ])('preserves truthful property state %s', async (collection, heading) => {
    setup(collection)
    expect(screen.getByRole('heading', { name: heading })).toBeInTheDocument()
    expect(getOwnedPropertyApplicationActionCounts).not.toHaveBeenCalled()
    expect(getPropertyImages).not.toHaveBeenCalled()
    if (collection.status === 'loading') {
      expect(document.querySelectorAll('.workspace-property-skeleton')).toHaveLength(2)
      expect(document.querySelector('.workspace-property-selector__grid')).toHaveAttribute('aria-hidden', 'true')
    }
    if (collection.status === 'error') {
      await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
      expect(collection.retry).toHaveBeenCalledTimes(1)
    }
  })

  it('shows a fallback when the image service fails', async () => {
    getPropertyImages.mockRejectedValue(new Error('Image unavailable'))
    setup()
    const card = await screen.findByRole('button', { name: 'Port city residence, 2 rental applications need attention' })
    expect(card.querySelector('.workspace-property-card__fallback')).toBeInTheDocument()
    expect(screen.queryByRole('img')).not.toBeInTheDocument()
  })
})
