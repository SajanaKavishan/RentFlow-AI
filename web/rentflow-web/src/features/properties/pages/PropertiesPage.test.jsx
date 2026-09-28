import { cleanup, render, screen, waitFor, within } from '@testing-library/react'
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
    const cards = screen.getAllByRole('article')
    expect(within(cards[0]).getByRole('heading', { name: 'Garden House' })).toBeInTheDocument()
    await userEvent.click(within(cards[0]).getByRole('button', { name: /Why this matches/ }))
    expect(within(cards[0]).getByText('Preferred city matches.')).toBeInTheDocument()
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
})
