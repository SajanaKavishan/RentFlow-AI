import { cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import PropertiesPage from './PropertiesPage.jsx'
import {
  getMatchPreferences,
  getProperties,
  getPropertyImages,
  getSavedPropertyMatches,
  saveMatchPreferences,
} from '../services/propertyApiService.js'

vi.mock('../services/propertyApiService.js', () => ({
  getMatchPreferences: vi.fn(),
  getProperties: vi.fn(),
  getPropertyImages: vi.fn(),
  getPropertyImageUrl: vi.fn(),
  getSavedPropertyMatches: vi.fn(),
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
