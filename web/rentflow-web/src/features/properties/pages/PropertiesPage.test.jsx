import { act, cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import PropertiesPage from './PropertiesPage.jsx'
import {
  addPropertyFavorite,
  getMatchPreferences,
  getProperties,
  getPropertyFavorites,
  getPropertyImages,
  getPropertyImageUrl,
  getSavedPropertyMatches,
  removePropertyFavorite,
  saveMatchPreferences,
} from '../services/propertyApiService.js'

vi.mock('../services/propertyApiService.js', () => ({
  getMatchPreferences: vi.fn(),
  getProperties: vi.fn(),
  getPropertyImages: vi.fn(),
  getPropertyImageUrl: vi.fn(),
  getSavedPropertyMatches: vi.fn(),
  getPropertyFavorites: vi.fn(),
  addPropertyFavorite: vi.fn(),
  removePropertyFavorite: vi.fn(),
  resetMatchPreferences: vi.fn(),
  saveMatchPreferences: vi.fn(),
}))

const properties = [
  { id: 'one', title: 'City Studio', description: 'Compact home', address: '1 Main Street', city: 'Colombo', monthlyRent: 80000, bedrooms: 1, bathrooms: 1, amenities: ['Security'], isAvailable: true, createdAt: '2026-09-20T00:00:00Z' },
  { id: 'two', title: 'Garden House', description: 'Family home', address: '2 Lake Road', city: 'Kurunegala', monthlyRent: 120000, bedrooms: 3, bathrooms: 2, amenities: ['Parking', 'Security'], isAvailable: true, createdAt: '2026-09-10T00:00:00Z' },
]
const preferences = { isConfigured: true, preferredCity: 'Kurunegala', maximumMonthlyRent: 150000, minimumBedrooms: 2, minimumBathrooms: 2, preferredAmenities: ['Parking', 'Security'] }
const matches = {
  summary: 'Ranked from saved preferences.',
  matches: [
    { propertyId: 'two', matchScore: 100, matchReasons: ['Preferred city matches.', 'Matches 2 of 2 preferred amenities.'] },
    { propertyId: 'one', matchScore: 25, matchReasons: ['Within maximum monthly rent.'] },
  ],
}

function renderPage(path = '/modules/properties') {
  return render(<MemoryRouter initialEntries={[path]}><Routes><Route path="/modules/properties" element={<PropertiesPage />} /></Routes></MemoryRouter>)
}

beforeEach(() => {
  getProperties.mockResolvedValue(properties)
  getPropertyImages.mockResolvedValue([])
  getSavedPropertyMatches.mockResolvedValue(matches)
  getPropertyFavorites.mockResolvedValue({ propertyIds: [] })
  addPropertyFavorite.mockResolvedValue(undefined)
  removePropertyFavorite.mockResolvedValue(undefined)
})

afterEach(() => {
  cleanup()
  vi.clearAllMocks()
})

describe('tenant property matching', () => {
  it('keeps normal browsing and never shows a fabricated score without preferences', async () => {
    getMatchPreferences.mockResolvedValue({ isConfigured: false, preferredAmenities: [] })
    renderPage()

    expect(await screen.findByRole('heading', { name: 'Get personalized matches' })).toBeInTheDocument()
    expect(await screen.findByRole('heading', { name: 'City Studio' })).toBeInTheDocument()
    expect(screen.queryByText(/% Match/)).not.toBeInTheDocument()
    expect(screen.queryByRole('option', { name: 'Best Match' })).not.toBeInTheDocument()
    expect(getSavedPropertyMatches).not.toHaveBeenCalled()
    expect(screen.getAllByRole('button', { name: 'Set match preferences' })).toHaveLength(1)

    expect(screen.queryByLabelText('City')).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Filters' }))
    expect(screen.getByLabelText('City')).toBeInTheDocument()
  })

  it('shows all real property images as a navigable slideshow', async () => {
    getMatchPreferences.mockResolvedValue({ isConfigured: false, preferredAmenities: [] })
    getPropertyImages.mockImplementation((propertyId) => Promise.resolve(propertyId === 'one' ? [{ id: 'photo-a' }, { id: 'photo-b' }] : []))
    getPropertyImageUrl.mockImplementation((_propertyId, imageId) => Promise.resolve({ url: `https://images.example/${imageId}.jpg` }))
    renderPage()

    const firstImage = await screen.findByRole('img', { name: 'City Studio — photo 1 of 2' })
    expect(firstImage).toHaveAttribute('src', 'https://images.example/photo-a.jpg')
    await userEvent.click(screen.getByRole('button', { name: 'Next image for City Studio' }))
    expect(screen.getByRole('img', { name: 'City Studio — photo 2 of 2' })).toHaveAttribute('src', 'https://images.example/photo-b.jpg')
    await userEvent.click(screen.getByRole('button', { name: 'Show image 1 of 2 for City Studio' }))
    expect(screen.getByRole('img', { name: 'City Studio — photo 1 of 2' })).toBeInTheDocument()
  })

  it('persists heart selections and exposes them through the Liked option', async () => {
    getMatchPreferences.mockResolvedValue({ isConfigured: false, preferredAmenities: [] })
    renderPage()

    const likeButton = await screen.findByRole('button', { name: 'Add City Studio to liked properties' })
    await userEvent.click(likeButton)
    expect(addPropertyFavorite).toHaveBeenCalledWith('one')
    expect(screen.getByRole('button', { name: 'Remove City Studio from liked properties' })).toHaveAttribute('aria-pressed', 'true')

    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Sort properties' }), 'liked')
    expect(screen.getByRole('heading', { name: 'City Studio' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Garden House' })).not.toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Remove City Studio from liked properties' }))
    expect(removePropertyFavorite).toHaveBeenCalledWith('one')
    expect(await screen.findByRole('heading', { name: 'No liked properties yet.' })).toBeInTheDocument()
  })

  it('loads saved preferences, automatically ranks matches, and exposes real reasons', async () => {
    getMatchPreferences.mockResolvedValue(preferences)
    renderPage()

    expect(await screen.findByLabelText('100 percent match')).toBeInTheDocument()
    expect(getSavedPropertyMatches).toHaveBeenCalledTimes(1)
    expect(screen.getByRole('combobox', { name: 'Sort properties' })).toHaveValue('bestMatch')
    expect(screen.getAllByRole('button', { name: 'Edit preferences' })).toHaveLength(1)
    expect(screen.queryByRole('button', { name: 'Edit Match Preferences' })).not.toBeInTheDocument()
    const cards = screen.getAllByRole('article')
    expect(within(cards[0]).getByRole('heading', { name: 'Garden House' })).toBeInTheDocument()
    await userEvent.click(within(cards[0]).getByRole('button', { name: /Why this matches/ }))
    expect(within(cards[0]).getByText('Preferred city matches.')).toBeInTheDocument()
  })

  it('keeps deterministic matches usable when the advisory explanation is unavailable', async () => {
    getMatchPreferences.mockResolvedValue(preferences)
    getSavedPropertyMatches.mockResolvedValue({
      ...matches,
      explanationAvailable: false,
      summary: 'Properties ranked using your saved match preferences.',
    })
    renderPage()

    expect(await screen.findByLabelText('100 percent match')).toBeInTheDocument()
    expect(screen.getByRole('combobox', { name: 'Sort properties' })).toHaveValue('bestMatch')
    expect(screen.getByText('AI explanation is temporarily unavailable. Match scores are based on your saved preferences.')).toBeInTheDocument()
    expect(screen.queryByText("We couldn't calculate your matches.")).not.toBeInTheDocument()
    const cards = screen.getAllByRole('article')
    expect(within(cards[0]).getByRole('heading', { name: 'Garden House' })).toBeInTheDocument()
    await userEvent.click(within(cards[0]).getByRole('button', { name: /Why this matches/ }))
    expect(within(cards[0]).getByText('Preferred city matches.')).toBeInTheDocument()
  })

  it('shows a matching error only when the matching request itself fails', async () => {
    getMatchPreferences.mockResolvedValue(preferences)
    getSavedPropertyMatches.mockRejectedValue(new Error('Matching data is unavailable.'))
    renderPage()

    const error = await screen.findByRole('alert')
    expect(error).toHaveTextContent("We couldn't calculate your matches.")
    expect(error).toHaveTextContent('Matching data is unavailable.')
    expect(screen.queryByText('AI explanation is temporarily unavailable. Match scores are based on your saved preferences.')).not.toBeInTheDocument()
  })

  it('only enables saving when match preferences have changed', async () => {
    getMatchPreferences.mockResolvedValue(preferences)
    renderPage()

    await userEvent.click(await screen.findByRole('button', { name: 'Edit preferences' }))
    const dialog = await screen.findByRole('dialog', { name: 'Edit match preferences' })
    const saveButton = within(dialog).getByRole('button', { name: 'Save preferences' })
    const cityInput = within(dialog).getByLabelText('Preferred city')

    expect(saveButton).toBeDisabled()
    await userEvent.clear(cityInput)
    await userEvent.type(cityInput, 'Colombo')
    expect(saveButton).toBeEnabled()
    await userEvent.clear(cityInput)
    await userEvent.type(cityInput, 'Kurunegala')
    expect(saveButton).toBeDisabled()
  })

  it('saves preferences before rematching and keeps filters working', async () => {
    getMatchPreferences.mockResolvedValue({ isConfigured: false, preferredAmenities: [] })
    let confirmSave
    saveMatchPreferences.mockReturnValue(new Promise((resolve) => { confirmSave = resolve }))
    renderPage('/modules/properties?preferences=edit')

    const dialog = await screen.findByRole('dialog', { name: 'Set match preferences' })
    await userEvent.type(within(dialog).getByLabelText('Preferred city'), 'Kurunegala')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save preferences' }))
    expect(within(dialog).getByRole('button', { name: 'Saving…' })).toBeDisabled()
    expect(getSavedPropertyMatches).not.toHaveBeenCalled()

    confirmSave(preferences)
    await waitFor(() => expect(getSavedPropertyMatches).toHaveBeenCalledTimes(1))
    expect(await screen.findByLabelText('100 percent match')).toBeInTheDocument()

    await userEvent.type(screen.getByRole('searchbox', { name: 'Search properties' }), 'studio')
    expect(screen.getByRole('heading', { name: 'City Studio' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Garden House' })).not.toBeInTheDocument()
  })

  it.each(['before', 'during', 'after'])('keeps search focused when rematching finishes %s typing', async (matchTiming) => {
    getMatchPreferences.mockResolvedValue({ isConfigured: false, preferredAmenities: [] })
    let confirmSave
    let confirmMatches
    let restoreFocus
    saveMatchPreferences.mockReturnValue(new Promise((resolve) => { confirmSave = resolve }))
    getSavedPropertyMatches.mockReturnValue(new Promise((resolve) => { confirmMatches = resolve }))
    vi.spyOn(window, 'requestAnimationFrame').mockImplementation((callback) => {
      restoreFocus = callback
      return 1
    })
    const user = userEvent.setup()
    renderPage('/modules/properties?preferences=edit')

    const dialog = await screen.findByRole('dialog', { name: 'Set match preferences' })
    await user.type(within(dialog).getByLabelText('Preferred city'), 'Kurunegala')
    await user.click(within(dialog).getByRole('button', { name: 'Save preferences' }))
    expect(getSavedPropertyMatches).not.toHaveBeenCalled()
    await act(async () => { confirmSave(preferences) })
    expect(getSavedPropertyMatches).toHaveBeenCalledTimes(1)

    if (matchTiming === 'before') await act(async () => { confirmMatches(matches) })
    const search = screen.getByRole('searchbox', { name: 'Search properties' })
    await user.type(search, 's')
    if (matchTiming === 'during') await act(async () => { confirmMatches(matches) })

    // Deliver the pending focus restoration between search keystrokes.
    if (matchTiming !== 'after') act(() => { restoreFocus(0) })
    await user.keyboard('tudio')
    expect(screen.queryByRole('heading', { name: 'Garden House' })).not.toBeInTheDocument()
    if (matchTiming === 'after') {
      await act(async () => { confirmMatches(matches) })
      act(() => { restoreFocus(0) })
    }
    expect(screen.queryByRole('heading', { name: 'Garden House' })).not.toBeInTheDocument()
    expect(search).toHaveValue('studio')
    expect(search).toHaveFocus()
    expect(screen.getByRole('heading', { name: 'City Studio' })).toBeInTheDocument()
  })

  it('restores focus to the preference action when no other control has been focused', async () => {
    getMatchPreferences.mockResolvedValue(preferences)
    let restoreFocus
    vi.spyOn(window, 'requestAnimationFrame').mockImplementation((callback) => {
      restoreFocus = callback
      return 1
    })
    const user = userEvent.setup()
    renderPage()

    await user.click(await screen.findByRole('button', { name: 'Edit preferences' }))
    await user.click(screen.getByRole('button', { name: 'Cancel' }))
    expect(document.activeElement).toBe(document.body)
    act(() => { restoreFocus(0) })
    expect(screen.getByRole('button', { name: 'Edit preferences' })).toHaveFocus()
  })

  it.each([
    ['Search properties', 'studio', 'City Studio', 'Garden House'],
    ['City', 'Colombo', 'City Studio', 'Garden House'],
    ['Maximum rent', '90000', 'City Studio', 'Garden House'],
    ['Bedrooms', '2', 'Garden House', 'City Studio'],
    ['Bathrooms', '2', 'Garden House', 'City Studio'],
    ['Amenity', 'Parking', 'Garden House', 'City Studio'],
    ['Sort properties', 'liked', 'City Studio', 'Garden House'],
  ])('preserves the %s filter and selected sort through a late rematch', async (label, value, visible, hidden) => {
    getMatchPreferences.mockResolvedValue({ isConfigured: false, preferredAmenities: [] })
    getPropertyFavorites.mockResolvedValue({ propertyIds: ['one'] })
    let confirmSave
    let confirmMatches
    saveMatchPreferences.mockReturnValue(new Promise((resolve) => { confirmSave = resolve }))
    getSavedPropertyMatches.mockReturnValue(new Promise((resolve) => { confirmMatches = resolve }))
    const user = userEvent.setup()
    renderPage()

    await screen.findByRole('heading', { name: 'City Studio' })
    await user.click(screen.getByRole('button', { name: 'Filters' }))
    const filter = screen.getByLabelText(label)
    if (label !== 'Sort properties') {
      if (filter.tagName === 'SELECT') await user.selectOptions(filter, value)
      else await user.type(filter, value)
    }
    await user.click(screen.getByRole('button', { name: 'Set match preferences' }))
    const dialog = screen.getByRole('dialog', { name: 'Set match preferences' })
    await user.type(within(dialog).getByLabelText('Preferred city'), 'Kurunegala')
    await user.click(within(dialog).getByRole('button', { name: 'Save preferences' }))
    expect(getSavedPropertyMatches).not.toHaveBeenCalled()
    await act(async () => { confirmSave(preferences) })
    expect(getSavedPropertyMatches).toHaveBeenCalledTimes(1)

    const sort = screen.getByRole('combobox', { name: 'Sort properties' })
    const selectedSort = label === 'Sort properties' ? 'liked' : 'highestRent'
    await user.selectOptions(sort, selectedSort)
    expect(screen.getByRole('heading', { name: visible })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: hidden })).not.toBeInTheDocument()

    await act(async () => { confirmMatches(matches) })
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(filter).toHaveValue(label === 'Maximum rent' ? Number(value) : value)
    expect(sort).toHaveValue(selectedSort)
    expect(screen.getByRole('heading', { name: visible })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: hidden })).not.toBeInTheDocument()

    if (label !== 'Sort properties') {
      await user.click(screen.getByRole('button', { name: 'Clear filters' }))
      const cards = screen.getAllByRole('article')
      expect(within(cards[0]).getByRole('heading', { name: 'Garden House' })).toBeInTheDocument()
      expect(within(cards[1]).getByRole('link', { name: 'City Studio' })).toHaveAttribute('href', '/properties/one')
    }
  })
})
