import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import PublicLandlordProfilePage from './PublicLandlordProfilePage.jsx'
import { getLandlordContact, getPublicLandlordSummary, getPublicLandlordProperties, getPropertyImages, getPropertyImageUrl } from '../services/propertyApiService.js'
import { useAuth } from '../../auth/useAuth.js'

vi.mock('../../auth/useAuth.js', () => ({ useAuth: vi.fn() }))

vi.mock('../services/propertyApiService.js', () => ({
  getPublicLandlordSummary: vi.fn(), getPublicLandlordProperties: vi.fn(),
  getLandlordContact: vi.fn(),
  getPropertyImages: vi.fn(), getPropertyImageUrl: vi.fn(),
  getPublicLandlordImageUrl: vi.fn((id) => `/api/properties/${id}/landlord-summary/image`),
}))

const summary = { displayName: 'Lena Landlord', memberSinceYear: 2022, hasProfileImage: false }
const property = { id: 'property-2', title: 'Garden Apartment', city: 'Colombo', monthlyRent: 100000,
  bedrooms: 2, bathrooms: 1, isAvailable: true }

function renderProfile() {
  return render(<MemoryRouter initialEntries={['/properties/property-1/landlord']}><Routes>
    <Route path="/properties/:propertyId/landlord" element={<PublicLandlordProfilePage />} />
    <Route path="/properties/:propertyId" element={<h1>Property details destination</h1>} />
  </Routes></MemoryRouter>)
}

describe('protected landlord contact', () => {
  it('shows the separately loaded phone as plain text and removes it on authoritative refresh', async () => {
    getLandlordContact.mockResolvedValue({ displayName: summary.displayName, phoneNumber: '+94771234567' })
    const { container } = renderProfile()
    expect(await screen.findByText('+94771234567')).toBeInTheDocument()
    expect(container.querySelector('a[href^="tel:"]')).toBeNull()
    expect(screen.queryByRole('button', { name: /Call/ })).not.toBeInTheDocument()
    getLandlordContact.mockResolvedValue(null)
    await act(async () => { window.dispatchEvent(new Event('focus')) })
    expect(screen.queryByRole('region', { name: 'Contact landlord' })).not.toBeInTheDocument()
  })

  it.each(['Landlord', 'Admin', 'MaintenanceTechnician', null])('does not fetch contact for %s', async (role) => {
    useAuth.mockReturnValue({ user: role ? { role } : null })
    renderProfile()
    await screen.findByRole('heading', { name: 'Lena Landlord' })
    expect(getLandlordContact).not.toHaveBeenCalled()
    expect(screen.queryByText('Contact landlord')).not.toBeInTheDocument()
  })

  it('omits failed contact requests without losing the public profile', async () => {
    getLandlordContact.mockRejectedValue(new Error('Unavailable contact'))
    renderProfile()
    await screen.findByRole('heading', { name: 'Lena Landlord' })
    expect(screen.queryByText('Contact landlord')).not.toBeInTheDocument()
  })
})

beforeEach(() => {
  vi.resetAllMocks()
  useAuth.mockReturnValue({ user: { role: 'Tenant' } })
  getLandlordContact.mockResolvedValue(null)
  getPublicLandlordSummary.mockResolvedValue(summary)
  getPublicLandlordProperties.mockResolvedValue([property])
  getPropertyImages.mockResolvedValue([])
})
afterEach(cleanup)

describe('Public landlord profile', () => {
  it('shows real identity, safe public properties, and normal property navigation', async () => {
    renderProfile()
    expect(await screen.findByRole('heading', { name: 'Lena Landlord' })).toBeInTheDocument()
    expect(screen.getByText('Member since 2022')).toBeInTheDocument()
    expect(screen.getByRole('img', { name: 'Lena Landlord initials' })).toHaveTextContent('LL')
    expect(await screen.findByRole('link', { name: 'Garden Apartment' })).toHaveAttribute('href', '/properties/property-2')
    expect(screen.getByText('Rs. 100,000')).toBeInTheDocument()
    expect(getPublicLandlordSummary).toHaveBeenCalledWith('property-1')
    expect(getPublicLandlordProperties).toHaveBeenCalledWith('property-1')
    expect(screen.getByRole('link', { name: 'Back to property' })).toHaveAttribute('href', '/properties/property-1')
    await userEvent.click(screen.getByRole('link', { name: 'Garden Apartment' }))
    expect(screen.getByRole('heading', { name: 'Property details destination' })).toBeInTheDocument()
  })

  it('never renders extra contact, account, or fabricated reputation fields', async () => {
    getPublicLandlordSummary.mockResolvedValue({ ...summary, phoneNumber: '+94112223344', email: 'private@example.test',
      passwordHash: 'secret-hash', tokenVersion: 3, company: 'Fake Company', rating: 5, verified: true })
    const { container } = renderProfile()
    await screen.findByRole('heading', { name: 'Lena Landlord' })
    expect(container.textContent).not.toMatch(/private@example|94112223344|secret-hash|Fake Company|rating|review|verified/i)
    expect(container.querySelector('a[href^="tel:"], a[href^="mailto:"]')).toBeNull()
    expect(screen.queryByRole('button', { name: /call|contact|message/i })).not.toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'About' })).not.toBeInTheDocument()
  })

  it('uses the existing safe profile image endpoint and falls back on image failure', async () => {
    getPublicLandlordSummary.mockResolvedValue({ ...summary, hasProfileImage: true })
    renderProfile()
    const image = await screen.findByRole('img', { name: 'Lena Landlord profile' })
    expect(image).toHaveAttribute('src', '/api/properties/property-1/landlord-summary/image')
    fireEvent.error(image)
    expect(screen.getByRole('img', { name: 'Lena Landlord initials' })).toHaveTextContent('LL')
  })

  it('shows separate profile and listings loading states', async () => {
    let resolveSummary, resolveProperties
    getPublicLandlordSummary.mockReturnValue(new Promise((resolve) => { resolveSummary = resolve }))
    getPublicLandlordProperties.mockReturnValue(new Promise((resolve) => { resolveProperties = resolve }))
    renderProfile()
    expect(screen.getByText('Loading landlord profile')).toBeInTheDocument()
    await act(async () => { resolveSummary(summary) })
    expect(screen.getByText('Loading properties…')).toBeInTheDocument()
    await act(async () => { resolveProperties([]) })
    expect(screen.getByText('No other properties are currently available.')).toBeInTheDocument()
  })

  it('shows the honest empty state', async () => {
    getPublicLandlordProperties.mockResolvedValue([])
    renderProfile()
    expect(await screen.findByText('No other properties are currently available.')).toBeInTheDocument()
    expect(screen.getByText('0 properties')).toBeInTheDocument()
  })

  it('shows a safe profile error and retries without exposing backend details', async () => {
    getPublicLandlordSummary.mockRejectedValueOnce(new Error('private-email@example.test secret backend exception'))
    renderProfile()
    expect(await screen.findByRole('heading', { name: 'Landlord profile unavailable' })).toBeInTheDocument()
    expect(screen.queryByText(/secret backend/)).not.toBeInTheDocument()
    expect(getPublicLandlordProperties).not.toHaveBeenCalled()
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByRole('heading', { name: 'Lena Landlord' })).toBeInTheDocument()
  })

  it('keeps identity visible when listings fail', async () => {
    getPublicLandlordProperties.mockRejectedValue(new Error('private storage key'))
    renderProfile()
    expect(await screen.findByText('Unable to load this landlord’s properties.')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Lena Landlord' })).toBeInTheDocument()
    expect(screen.queryByText('private storage key')).not.toBeInTheDocument()
  })

  it('handles partial image URL failures and broken property images without losing the profile', async () => {
    getPropertyImages.mockResolvedValue([{ id: 'bad' }, { id: 'good' }])
    getPropertyImageUrl.mockRejectedValueOnce(new Error('unavailable')).mockResolvedValueOnce({ url: 'https://images.test/garden.jpg' })
    renderProfile()
    const image = await screen.findByRole('img', { name: /Garden Apartment.*photo/ })
    expect(image).toHaveAttribute('src', 'https://images.test/garden.jpg')
    fireEvent.error(image)
    expect(screen.getByText('No property photos yet')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Lena Landlord' })).toBeInTheDocument()
  })

  it('rejects a listings response containing unavailable properties', async () => {
    getPublicLandlordProperties.mockResolvedValue([{ ...property, isAvailable: false }])
    renderProfile()
    await screen.findByText('Unable to load this landlord’s properties.')
    expect(screen.queryByRole('link', { name: 'Garden Apartment' })).not.toBeInTheDocument()
  })
})
