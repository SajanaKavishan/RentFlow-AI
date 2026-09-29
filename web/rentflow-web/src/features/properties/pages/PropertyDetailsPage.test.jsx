import { cleanup, render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import PropertyDetailsPage from './PropertyDetailsPage.jsx'
import { useAuth } from '../../auth/useAuth.js'
import {
  getProperty,
  getSavedPropertyMatches,
} from '../services/propertyApiService.js'

vi.mock('../../auth/useAuth.js', () => ({ useAuth: vi.fn() }))
vi.mock('../services/propertyApiService.js', () => ({
  deleteProperty: vi.fn(),
  getMyProperties: vi.fn(),
  getProperty: vi.fn(),
  getSavedPropertyMatches: vi.fn(),
  updateProperty: vi.fn(),
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
      .toHaveAttribute('href', '/modules/my-viewings')
    expect(screen.getByRole('link', { name: 'Apply for Rental' }))
      .toHaveAttribute('href', '/modules/my-applications')
    await waitFor(() => expect(screen.getByTestId('details-gallery')).toHaveTextContent('97% match'))

    expect(screen.queryByText(/security deposit/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/lease term/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/pets allowed/i)).not.toBeInTheDocument()
  })

  it('places location before the honest landlord fallback', async () => {
    renderPage()

    const location = await screen.findByRole('heading', { name: 'Location' })
    const listedBy = screen.getByRole('heading', { name: 'Listed by' })
    expect(location.compareDocumentPosition(listedBy) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
    expect(screen.getByText('Landlord profile details are not available for this listing.'))
      .toBeInTheDocument()
  })
})
