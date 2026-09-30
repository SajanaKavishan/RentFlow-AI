import { cleanup, render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import PropertyDetailsPage from './PropertyDetailsPage.jsx'
import { useAuth } from '../../auth/useAuth.js'
import {
  getMyProperties,
  getProperty,
  getPublicLandlordSummary,
  getSavedPropertyMatches,
} from '../services/propertyApiService.js'
import { getMyViewings } from '../../viewings/services/viewingApiService.js'
import { getMyApplications } from '../../rentalApplications/services/rentalApplicationApiService.js'

vi.mock('../../auth/useAuth.js', () => ({ useAuth: vi.fn() }))
vi.mock('../services/propertyApiService.js', () => ({
  deleteProperty: vi.fn(),
  getMyProperties: vi.fn(),
  getProperty: vi.fn(),
  getPublicLandlordImageUrl: vi.fn(() => 'https://example.test/landlord-image'),
  getPublicLandlordSummary: vi.fn(),
  getSavedPropertyMatches: vi.fn(),
  updateProperty: vi.fn(),
}))
vi.mock('../../viewings/services/viewingApiService.js', () => ({ getMyViewings: vi.fn() }))
vi.mock('../../rentalApplications/services/rentalApplicationApiService.js', () => ({
  getMyApplications: vi.fn(),
  RENTAL_APPLICATION_STATUS: {
    DRAFT: 0,
    SUBMITTED: 1,
    UNDER_REVIEW: 2,
    CHANGES_REQUESTED: 3,
  },
}))
vi.mock('../components/PropertyImageGallery.jsx', () => ({
  default: ({ alt, matchScore }) => (
    <div data-testid="details-gallery">{alt} gallery {matchScore == null ? '' : `${matchScore}% match`}</div>
  ),
}))
vi.mock('../components/PropertyLocationMap.jsx', () => ({
  default: ({ address, city }) => <section><h2>Location</h2><p>{address}, {city}</p></section>,
}))

const property = {
  id: 'property-1',
  landlordId: 'landlord-1',
  title: 'Lake View Apartment',
  description: 'A bright home beside the lake.',
  address: '18 Lake Road',
  city: 'Colombo',
  monthlyRent: 120000,
  bedrooms: 2,
  bathrooms: 2,
  area: 1100,
  areaUnit: 'sqft',
  areaType: 'FloorArea',
  availableFrom: '2026-11-01',
  isAvailable: true,
  amenities: ['Parking', 'Security'],
}

function renderPage() {
  return render(
    <MemoryRouter initialEntries={['/properties/property-1']}>
      <Routes>
        <Route path="/properties/:propertyId" element={<PropertyDetailsPage />} />
        <Route path="/modules/my-viewings" element={<p>My viewings</p>} />
        <Route path="/modules/my-applications" element={<p>My applications</p>} />
      </Routes>
    </MemoryRouter>,
  )
}

beforeEach(() => {
  useAuth.mockReturnValue({
    user: { id: 'tenant-1', role: 'Tenant', fullName: 'Taylor Tenant' },
  })
  getProperty.mockResolvedValue(property)
  getMyProperties.mockResolvedValue([property])
  getPublicLandlordSummary.mockResolvedValue({
    displayName: 'Lena Landlord',
    memberSinceYear: 2022,
    hasProfileImage: false,
  })
  getMyViewings.mockResolvedValue([])
  getMyApplications.mockResolvedValue([])
  getSavedPropertyMatches.mockResolvedValue({
    matches: [{ propertyId: 'property-1', matchScore: 97 }],
  })
})

afterEach(() => {
  cleanup()
  vi.clearAllMocks()
})

describe('tenant property details', () => {
  it('uses real listing data in the redesigned marketplace layout', async () => {
    renderPage()

    expect(await screen.findByRole('heading', { name: 'Lake View Apartment' })).toBeInTheDocument()
    expect(screen.getByText('2 Bedrooms')).toBeInTheDocument()
    expect(screen.getByText('2 Bathrooms')).toBeInTheDocument()
    expect(screen.getByText('Floor area: 1,100 sq ft')).toBeInTheDocument()
    expect(screen.getByText('Available now')).toBeInTheDocument()
    expect(screen.getByText('Available from Nov 1, 2026')).toBeInTheDocument()
    expect(screen.getByText('Rs. 120,000')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Book a Viewing' }))
      .toHaveAttribute('href', '/modules/my-viewings?propertyId=property-1')
    expect(screen.getByRole('link', { name: 'Apply for Rental' }))
      .toHaveAttribute('href', '/modules/my-applications?propertyId=property-1')
    await waitFor(() => expect(screen.getByTestId('details-gallery')).toHaveTextContent('97% match'))

    expect(screen.queryByText(/security deposit/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/lease term/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/pets allowed/i)).not.toBeInTheDocument()
  })

  it('shows only the real public landlord summary after location with initials fallback', async () => {
    renderPage()

    const location = await screen.findByRole('heading', { name: 'Location' })
    const listedBy = screen.getByRole('heading', { name: 'Listed by' })
    expect(location.compareDocumentPosition(listedBy) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
    expect(await screen.findByText('Lena Landlord')).toBeInTheDocument()
    expect(screen.getByText('Member since 2022')).toBeInTheDocument()
    expect(screen.getByText('LL')).toBeInTheDocument()
    expect(screen.queryByText(/@/)).not.toBeInTheDocument()
    expect(screen.queryByText(/phone/i)).not.toBeInTheDocument()
  })

  it('keeps property details usable when the landlord summary fails', async () => {
    getPublicLandlordSummary.mockRejectedValue(new Error('Unavailable'))
    renderPage()

    expect(await screen.findByRole('heading', { name: 'Lake View Apartment' })).toBeInTheDocument()
    expect(await screen.findByText('Landlord details unavailable')).toBeInTheDocument()
    expect(screen.getByText('This listing remains available to review.')).toBeInTheDocument()
  })

  it('disables new actions for unavailable properties but keeps existing tenant state accessible', async () => {
    getProperty.mockResolvedValue({ ...property, isAvailable: false })
    getMyViewings.mockResolvedValue([{ propertyId: 'property-1' }])
    getMyApplications.mockResolvedValue([{ propertyId: 'property-1', status: 2 }])
    renderPage()

    expect(await screen.findByRole('link', { name: 'View viewing requests' }))
      .toHaveAttribute('href', '/modules/my-viewings?propertyId=property-1')
    expect(screen.getByRole('link', { name: 'View application' }))
      .toHaveAttribute('href', '/modules/my-applications?propertyId=property-1')
    expect(screen.getByText('This property is currently unavailable. Existing requests and applications remain accessible.'))
      .toBeInTheDocument()
  })

  it('truthfully disables unavailable-property CTAs when no existing records are known', async () => {
    getProperty.mockResolvedValue({ ...property, isAvailable: false })
    renderPage()

    expect(await screen.findByRole('link', { name: 'Book a Viewing' }))
      .toHaveAttribute('aria-disabled', 'true')
    expect(screen.getByRole('link', { name: 'Apply for Rental' }))
      .toHaveAttribute('aria-disabled', 'true')
  })

  it('preserves landlord management tools without tenant CTAs', async () => {
    useAuth.mockReturnValue({
      user: { id: 'landlord-1', role: 'Landlord', fullName: 'Lena Landlord' },
    })
    renderPage()

    expect(await screen.findByRole('heading', { name: 'Manage this property' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Viewing Requests/ })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Rental Applications/ })).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'Book a Viewing' })).not.toBeInTheDocument()
  })
})
