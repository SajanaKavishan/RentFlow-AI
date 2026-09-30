import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter, RouterProvider } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../../App.jsx'
import { AuthContext } from '../../auth/useAuth.js'
import {
  createProperty,
  deletePropertyImage,
  getMyProperties,
  getPropertyImages,
  reorderPropertyImages,
  setPrimaryPropertyImage,
  updatePropertyListing,
  uploadPropertyImages,
} from '../services/propertyApiService.js'
import { loadGoogleLocationTools, loadGooglePlaces } from '../googleMapsLoader.js'

vi.mock('../../notifications/notificationsApi.js', async (importOriginal) => ({
  ...(await importOriginal()), getUnreadCount: vi.fn().mockResolvedValue(0),
}))

vi.mock('../services/propertyApiService.js', async (importOriginal) => ({
  ...(await importOriginal()),
  createProperty: vi.fn(),
  deletePropertyImage: vi.fn(),
  getMyProperties: vi.fn(),
  getPropertyImages: vi.fn(),
  reorderPropertyImages: vi.fn(),
  setPrimaryPropertyImage: vi.fn(),
  updatePropertyListing: vi.fn(),
  uploadPropertyImages: vi.fn(),
}))

vi.mock('../googleMapsLoader.js', () => ({
  loadGoogleLocationTools: vi.fn(),
  loadGooglePlaces: vi.fn(),
}))

const propertyId = '11111111-1111-1111-1111-111111111111'
const newPropertyId = '77777777-7777-7777-7777-777777777777'
const property = {
  id: propertyId,
  landlordId: '22222222-2222-2222-2222-222222222222',
  title: 'Harbour View Residence',
  description: 'A bright apartment near the coast.',
  address: '18 Marine Drive',
  city: 'Colombo',
  latitude: null,
  longitude: null,
  googlePlaceId: null,
  monthlyRent: 185000,
  bedrooms: 3,
  bathrooms: 2,
  area: 1450,
  areaUnit: 'sqft',
  areaType: 'FloorArea',
  availableFrom: '2026-11-01',
  isAvailable: true,
  amenities: ['Parking', 'Security'],
}

let autocompleteElement
let mapClickHandler
let advancedMarker
let placeFetchFields
const originalGeolocation = navigator.geolocation

const reverseGeocodeResult = {
  formatted_address: '25 Lake Road, Kandy, Sri Lanka',
  address_components: [{ long_name: 'Kandy', types: ['locality'] }],
  place_id: 'ChIJ-reverse-geocoded',
}

function configureGoogleAutocomplete() {
  loadGooglePlaces.mockResolvedValue({
    PlaceAutocompleteElement: class {
      constructor() {
        autocompleteElement = document.createElement('div')
        return autocompleteElement
      }
    },
  })
}

function configureGoogleLocationTools({
  result = reverseGeocodeResult,
  geocodeError = null,
  geocodeImplementation = null,
  placeResult = null,
  placeError = null,
} = {}) {
  const geocode = geocodeImplementation || (geocodeError
    ? vi.fn().mockRejectedValue(geocodeError)
    : vi.fn().mockResolvedValue({ results: result ? [result] : [] }))
  placeFetchFields = placeError
    ? vi.fn().mockRejectedValue(placeError)
    : vi.fn().mockResolvedValue(undefined)

  class MapMock {
    addListener(name, handler) {
      if (name === 'click') mapClickHandler = handler
      return { remove: vi.fn() }
    }

    panTo() {}
  }

  class AdvancedMarkerElementMock {
    constructor(options) {
      Object.assign(this, options)
      this.listeners = {}
      advancedMarker = this
    }

    addEventListener(name, handler) { this.listeners[name] = handler }
    removeEventListener(name) { delete this.listeners[name] }
  }

  class GeocoderMock {
    geocode(request) { return geocode(request) }
  }

  class PlaceMock {
    constructor({ id }) { this.id = id }

    async fetchFields(options) {
      await placeFetchFields(options)
      if (placeResult) Object.assign(this, placeResult)
    }
  }

  loadGoogleLocationTools.mockResolvedValue({
    Map: MapMock,
    AdvancedMarkerElement: AdvancedMarkerElementMock,
    Geocoder: GeocoderMock,
    Place: PlaceMock,
  })
  return geocode
}

async function selectGooglePlace(overrides = {}) {
  await waitFor(() => expect(autocompleteElement).toBeInTheDocument())
  const place = {
    id: 'ChIJ-lake-house',
    formattedAddress: '25 Lake Road, Kandy, Sri Lanka',
    addressComponents: [{ longText: 'Kandy', types: ['locality'] }],
    location: { lat: () => 7.290572, lng: () => 80.633728 },
    fetchFields: vi.fn().mockResolvedValue(undefined),
    ...overrides,
  }
  const event = new Event('gmp-select')
  event.placePrediction = { toPlace: () => place }
  autocompleteElement.dispatchEvent(event)
  await waitFor(() => expect(place.fetchFields).toHaveBeenCalled())
  return place
}

function renderApp(entry) {
  const router = createMemoryRouter([{ path: '*', element: <App /> }], {
    initialEntries: [entry],
  })
  render(
    <AuthContext.Provider value={{
      user: {
        id: property.landlordId,
        fullName: 'Nila Perera',
        email: 'nila@example.com',
        role: 'Landlord',
      },
      isAuthenticated: true,
      isLoading: false,
      logout: vi.fn(),
    }}>
      <RouterProvider router={router} />
    </AuthContext.Provider>,
  )
  return router
}

async function completeBasicDetails() {
  await userEvent.type(screen.getByLabelText('Property title'), 'Lake House')
  await userEvent.type(screen.getByLabelText('Description'), 'A quiet lakeside home.')
  await userEvent.type(screen.getByLabelText('Address'), '25 Lake Road')
  await userEvent.type(screen.getByLabelText('City'), 'Kandy')
  await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
}

async function completePropertyDetails() {
  await userEvent.type(screen.getByLabelText('Monthly rent'), '95000')
  await userEvent.type(screen.getByLabelText('Bedrooms'), '2')
  await userEvent.type(screen.getByLabelText('Bathrooms'), '1')
  await userEvent.type(screen.getByLabelText('Size'), '1250')
  await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
  await userEvent.click(screen.getByLabelText('Parking'))
  await userEvent.click(screen.getByLabelText('Garden'))
  await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
}

beforeEach(() => {
  vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', '')
  loadGooglePlaces.mockReset()
  loadGoogleLocationTools.mockReset()
  autocompleteElement = null
  mapClickHandler = null
  advancedMarker = null
  placeFetchFields = null
  getMyProperties.mockReset().mockResolvedValue([property])
  getPropertyImages.mockReset().mockResolvedValue([])
  deletePropertyImage.mockReset().mockResolvedValue(undefined)
  reorderPropertyImages.mockReset().mockResolvedValue([])
  setPrimaryPropertyImage.mockReset().mockResolvedValue({})
  createProperty.mockReset().mockResolvedValue({ id: newPropertyId })
  updatePropertyListing.mockReset().mockResolvedValue(property)
  uploadPropertyImages.mockReset().mockResolvedValue([])
})

afterEach(() => {
  cleanup()
  vi.unstubAllEnvs()
  Object.defineProperty(navigator, 'geolocation', { configurable: true, value: originalGeolocation })
})

describe('property form wizard', () => {
  it('validates each step and preserves entered values while moving backward and forward', async () => {
    renderApp('/properties/new')

    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))

    expect(screen.getByRole('heading', { name: 'Basic Details' })).toBeInTheDocument()
    expect(screen.getByText('Property title is required.')).toBeInTheDocument()
    expect(screen.getByText('Description is required.')).toBeInTheDocument()
    expect(createProperty).not.toHaveBeenCalled()

    await completeBasicDetails()

    expect(screen.getByRole('heading', { name: 'Property Details' })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    expect(screen.getByText('Enter a valid monthly rent.')).toBeInTheDocument()
    expect(createProperty).not.toHaveBeenCalled()

    await completePropertyDetails()

    expect(screen.getByRole('heading', { name: 'Photos & Publication' })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Back' }))
    expect(screen.getByLabelText('Parking')).toBeChecked()
    expect(screen.getByLabelText('Garden')).toBeChecked()
    await userEvent.click(screen.getByRole('button', { name: 'Back' }))
    expect(screen.getByLabelText('Monthly rent')).toHaveValue(95000)

    await userEvent.click(screen.getByRole('button', { name: 'Back' }))
    expect(screen.getByLabelText('Property title')).toHaveValue('Lake House')
    expect(screen.getByLabelText('Description')).toHaveValue('A quiet lakeside home.')

    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    expect(screen.getByLabelText('Bedrooms')).toHaveValue(2)
    expect(createProperty).not.toHaveBeenCalled()
  })

  it('blocks zero monthly rent before leaving Property Details', async () => {
    renderApp('/properties/new')
    await completeBasicDetails()

    await userEvent.type(screen.getByLabelText('Monthly rent'), '0')
    await userEvent.type(screen.getByLabelText('Bedrooms'), '2')
    await userEvent.type(screen.getByLabelText('Bathrooms'), '1')
    await userEvent.type(screen.getByLabelText('Size'), '900')
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))

    expect(screen.getByText('Enter a valid monthly rent.')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Property Details' })).toBeInTheDocument()
    expect(createProperty).not.toHaveBeenCalled()
  })

  it('validates and preserves rental preferences, utilities, and custom amenities', async () => {
    renderApp('/properties/new')
    await completeBasicDetails()
    await userEvent.type(screen.getByLabelText('Monthly rent'), '95000')
    await userEvent.type(screen.getByLabelText('Bedrooms'), '2')
    await userEvent.type(screen.getByLabelText('Bathrooms'), '1')
    await userEvent.type(screen.getByLabelText('Size'), '1250')
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))

    await userEvent.type(screen.getByLabelText('Advertised security deposit'), '-1')
    await userEvent.type(screen.getByLabelText('Preferred lease term'), '121')
    await userEvent.selectOptions(screen.getByLabelText('Pet policy'), 'Conditional')
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    expect(screen.getByText('Advertised security deposit must be zero or more.')).toBeInTheDocument()
    expect(screen.getByText('Preferred lease term must be 1 to 120 months.')).toBeInTheDocument()
    expect(screen.getByText('Add meaningful notes for a conditional pet policy.')).toBeInTheDocument()

    await userEvent.clear(screen.getByLabelText('Advertised security deposit'))
    await userEvent.type(screen.getByLabelText('Advertised security deposit'), '190000')
    await userEvent.clear(screen.getByLabelText('Preferred lease term'))
    await userEvent.type(screen.getByLabelText('Preferred lease term'), '12')
    await userEvent.type(screen.getByLabelText('Pet notes'), 'Landlord approval required')
    await userEvent.click(screen.getByText('I want to provide utility information'))
    await userEvent.click(screen.getByLabelText('Water'))
    await userEvent.click(screen.getByLabelText('Internet'))
    await userEvent.type(screen.getByPlaceholderText('Other amenity'), 'Solar inverter')
    await userEvent.click(screen.getByRole('button', { name: '+ Add' }))
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    await userEvent.click(screen.getByRole('button', { name: 'Create Property' }))

    await waitFor(() => expect(createProperty).toHaveBeenCalledWith(expect.objectContaining({
      advertisedSecurityDeposit: 190000,
      preferredLeaseTermMonths: 12,
      petPolicy: 'Conditional',
      petPolicyNotes: 'Landlord approval required',
      includedUtilities: ['water', 'internet'],
      amenityDetails: [{ canonicalKey: null, customName: 'Solar inverter' }],
    })))
  }, 10000)

  it('persists an unavailable create selection and keeps available-from optional', async () => {
    renderApp('/properties/new')
    await completeBasicDetails()
    await completePropertyDetails()

    await userEvent.click(screen.getByLabelText(/Available for rent/))
    await userEvent.click(screen.getByRole('button', { name: 'Create Property' }))

    await waitFor(() => expect(createProperty).toHaveBeenCalledWith(expect.objectContaining({
      isAvailable: false,
      availableFrom: null,
    })))
  })

  it('collects explicit land-area semantics and an optional available-from date', async () => {
    renderApp('/properties/new')
    await completeBasicDetails()

    await userEvent.type(screen.getByLabelText('Monthly rent'), '95000')
    await userEvent.type(screen.getByLabelText('Bedrooms'), '2')
    await userEvent.type(screen.getByLabelText('Bathrooms'), '1')
    await userEvent.type(screen.getByLabelText('Size'), '15')
    await userEvent.selectOptions(screen.getByLabelText('Size type'), 'LandArea')
    await userEvent.selectOptions(screen.getByLabelText('Size unit'), 'perch')
    await userEvent.type(screen.getByLabelText('Available from'), '2026-11-01')
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    await userEvent.click(screen.getByRole('button', { name: 'Create Property' }))

    await waitFor(() => expect(createProperty).toHaveBeenCalledWith(expect.objectContaining({
      area: 15,
      areaType: 'LandArea',
      areaUnit: 'perch',
      availableFrom: '2026-11-01',
    })))
  })

  it('creates only at the final action and uploads photos with the returned property ID', async () => {
    const router = renderApp('/properties/new')
    await completeBasicDetails()
    await completePropertyDetails()
    const photo = new File(['property-photo'], 'lake-house.png', { type: 'image/png' })

    await userEvent.upload(screen.getByLabelText('Choose property photos'), photo)
    expect(createProperty).not.toHaveBeenCalled()
    await userEvent.click(screen.getByRole('button', { name: 'Create Property' }))

    await waitFor(() => expect(router.state.location.pathname).toBe('/modules/manage-properties'))
    expect(createProperty).toHaveBeenCalledWith({
      title: 'Lake House',
      description: 'A quiet lakeside home.',
      address: '25 Lake Road',
      city: 'Kandy',
      latitude: null,
      longitude: null,
      googlePlaceId: null,
      monthlyRent: 95000,
      bedrooms: 2,
      bathrooms: 1,
      area: 1250,
      areaUnit: 'sqft',
      areaType: 'FloorArea',
      availableFrom: null,
      isAvailable: true,
      advertisedSecurityDeposit: null,
      preferredLeaseTermMonths: null,
      petPolicy: null,
      petPolicyNotes: null,
      includedUtilities: null,
      amenities: [],
      amenityDetails: [
        { canonicalKey: 'parking', customName: null },
        { canonicalKey: 'garden', customName: null },
      ],
    })
    expect(uploadPropertyImages).toHaveBeenCalledWith(newPropertyId, [photo])
    expect(createProperty.mock.invocationCallOrder[0])
      .toBeLessThan(uploadPropertyImages.mock.invocationCallOrder[0])
    const createdMessage = await screen.findByText('Lake House was created successfully with 1 photo.')
    expect(createdMessage.closest('.property-toast')).toHaveClass('property-toast--success')
  })

  it('treats an early form submit as Continue instead of creating the property', async () => {
    renderApp('/properties/new')
    await completeBasicDetails()

    await userEvent.type(screen.getByLabelText('Monthly rent'), '95000')
    await userEvent.type(screen.getByLabelText('Bedrooms'), '2')
    await userEvent.type(screen.getByLabelText('Bathrooms'), '1')
    await userEvent.type(screen.getByLabelText('Size'), '1250')

    fireEvent.submit(screen.getByLabelText('Monthly rent').closest('form'))

    expect(screen.getByRole('heading', { name: 'Rental Preferences & Amenities' })).toBeInTheDocument()
    expect(createProperty).not.toHaveBeenCalled()
  })

  it('loads an owned property into the edit route and saves through the existing update flow', async () => {
    const router = renderApp(`/properties/${propertyId}/edit`)

    expect(await screen.findByRole('heading', { name: 'Edit Property' })).toBeInTheDocument()
    expect(screen.getByLabelText('Property title')).toHaveValue(property.title)
    expect(screen.getByLabelText('Description')).toHaveValue(property.description)
    expect(getMyProperties).toHaveBeenCalledTimes(1)

    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    expect(screen.getByLabelText('Monthly rent')).toHaveValue(property.monthlyRent)
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    expect(screen.getByRole('button', { name: 'Remove Parking' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Remove Security' })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))

    expect(screen.getByRole('heading', { name: 'Photos & Publication' })).toBeInTheDocument()
    expect(updatePropertyListing).not.toHaveBeenCalled()
    expect(await screen.findByText('No property photos uploaded yet.')).toBeInTheDocument()
    const saveButton = screen.getByRole('button', { name: 'Save Changes' })
    expect(saveButton).toBeDisabled()

    await userEvent.click(screen.getByLabelText(/Available for rent/))
    expect(saveButton).toBeEnabled()
    await userEvent.click(saveButton)

    await waitFor(() => expect(router.state.location.pathname).toBe('/modules/manage-properties'))
    expect(updatePropertyListing).toHaveBeenCalledWith(propertyId, {
      title: property.title,
      description: property.description,
      address: property.address,
      city: property.city,
      latitude: null,
      longitude: null,
      googlePlaceId: null,
      monthlyRent: property.monthlyRent,
      bedrooms: property.bedrooms,
      bathrooms: property.bathrooms,
      area: property.area,
      areaUnit: property.areaUnit,
      areaType: property.areaType,
      availableFrom: property.availableFrom,
      isAvailable: false,
      advertisedSecurityDeposit: null,
      preferredLeaseTermMonths: null,
      petPolicy: null,
      petPolicyNotes: null,
      includedUtilities: null,
      amenities: [],
      amenityDetails: [
        { canonicalKey: null, customName: 'Parking' },
        { canonicalKey: null, customName: 'Security' },
      ],
    })
    expect(uploadPropertyImages).not.toHaveBeenCalled()
    const updatedMessage = await screen.findByText('Harbour View Residence was updated successfully.')
    expect(updatedMessage.closest('.property-toast')).toHaveClass('property-toast--success')
  })

  it('keeps a legacy property without area semantics editable without inventing a type', async () => {
    getMyProperties.mockResolvedValue([{ ...property, areaType: null, availableFrom: null }])
    renderApp(`/properties/${propertyId}/edit`)

    await screen.findByRole('heading', { name: 'Edit Property' })
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    expect(screen.getByLabelText('Size type')).toHaveValue('')
    expect(screen.getByRole('option', { name: 'Not specified (legacy listing)' })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    await userEvent.click(screen.getByLabelText(/Available for rent/))
    await userEvent.click(screen.getByRole('button', { name: 'Save Changes' }))

    await waitFor(() => expect(updatePropertyListing).toHaveBeenCalledWith(
      propertyId,
      expect.objectContaining({ areaType: null, availableFrom: null }),
    ))
  })

  it('requires an actual Google suggestion selection and preserves it across wizard navigation', async () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')
    configureGoogleAutocomplete()
    renderApp('/properties/new')

    await userEvent.type(screen.getByLabelText('Property title'), 'Lake House')
    await userEvent.type(screen.getByLabelText('Description'), 'A quiet lakeside home.')
    expect(await screen.findByLabelText('Search address, building or place')).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    expect(screen.getByText('Select a Google place, use your current location, choose a point on the map, or enter the address manually.')).toBeInTheDocument()

    await selectGooglePlace()

    expect(await screen.findByText('25 Lake Road, Kandy, Sri Lanka')).toBeInTheDocument()
    const preview = screen.getByTitle('Map preview for 25 Lake Road, Kandy, Sri Lanka')
    expect(new URL(preview.getAttribute('src')).searchParams.get('q')).toBe('7.290572,80.633728')

    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    expect(screen.getByRole('heading', { name: 'Property Details' })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Back' }))
    expect(screen.getByTitle('Map preview for 25 Lake Road, Kandy, Sri Lanka')).toBeInTheDocument()
    expect(screen.getByText('Kandy')).toBeInTheDocument()
  })

  it('submits authoritative Google location metadata after a selected place', async () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')
    configureGoogleAutocomplete()
    renderApp('/properties/new')

    await userEvent.type(screen.getByLabelText('Property title'), 'Lake House')
    await userEvent.type(screen.getByLabelText('Description'), 'A quiet lakeside home.')
    await selectGooglePlace()
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    await completePropertyDetails()
    await userEvent.click(screen.getByRole('button', { name: 'Create Property' }))

    await waitFor(() => expect(createProperty).toHaveBeenCalledWith(expect.objectContaining({
      address: '25 Lake Road, Kandy, Sri Lanka',
      city: 'Kandy',
      latitude: 7.290572,
      longitude: 80.633728,
      googlePlaceId: 'ChIJ-lake-house',
    })))
  })

  it('clears authoritative metadata when a selected place is replaced by manual entry', async () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')
    configureGoogleAutocomplete()
    renderApp('/properties/new')

    await userEvent.type(screen.getByLabelText('Property title'), 'Lake House')
    await userEvent.type(screen.getByLabelText('Description'), 'A quiet lakeside home.')
    await selectGooglePlace()
    await userEvent.click(screen.getByRole('button', { name: 'Enter address manually' }))
    expect(screen.getByLabelText('Address')).toHaveValue('25 Lake Road, Kandy, Sri Lanka')
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    await completePropertyDetails()
    await userEvent.click(screen.getByRole('button', { name: 'Create Property' }))

    await waitFor(() => expect(createProperty).toHaveBeenCalledWith(expect.objectContaining({
      latitude: null,
      longitude: null,
      googlePlaceId: null,
    })))
  })

  it('uses the manual fallback without fabricating location metadata when no key is configured', async () => {
    renderApp('/properties/new')

    expect(screen.getByLabelText('Address')).toBeInTheDocument()
    expect(screen.getByLabelText('City')).toBeInTheDocument()
    expect(screen.queryByLabelText('Search address, building or place')).not.toBeInTheDocument()
    await completeBasicDetails()
    await completePropertyDetails()
    await userEvent.click(screen.getByRole('button', { name: 'Create Property' }))

    await waitFor(() => expect(createProperty).toHaveBeenCalledWith(expect.objectContaining({
      latitude: null,
      longitude: null,
      googlePlaceId: null,
    })))
  })

  it('offers the manual fallback when the Google Places library is unavailable', async () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')
    loadGooglePlaces.mockRejectedValue(new Error('network unavailable'))
    renderApp('/properties/new')

    expect(await screen.findByText('Google location search is unavailable right now. Choose another location method.')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Enter address manually' }))
    expect(screen.getByLabelText('Address')).toBeInTheDocument()
    expect(screen.getByLabelText('City')).toBeInTheDocument()
  })

  it('requests current position only after explicit action and confirms reverse-geocoded metadata', async () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')
    configureGoogleAutocomplete()
    const getCurrentPosition = vi.fn((success) => success({
      coords: { latitude: 7.290572, longitude: 80.633728 },
    }))
    Object.defineProperty(navigator, 'geolocation', {
      configurable: true,
      value: { getCurrentPosition },
    })
    const geocode = configureGoogleLocationTools()
    renderApp('/properties/new')

    expect(getCurrentPosition).not.toHaveBeenCalled()
    await userEvent.click(screen.getByRole('button', { name: 'Use my current location' }))
    expect(getCurrentPosition).not.toHaveBeenCalled()
    await userEvent.click(screen.getByRole('button', { name: 'Find my location' }))

    await waitFor(() => expect(screen.getByLabelText('Address')).toHaveValue(reverseGeocodeResult.formatted_address))
    expect(geocode).toHaveBeenCalledWith({ location: { lat: 7.290572, lng: 80.633728 } })
    expect(getCurrentPosition).toHaveBeenCalledWith(expect.any(Function), expect.any(Function), {
      enableHighAccuracy: true,
      timeout: 10000,
      maximumAge: 0,
    })
    await userEvent.click(screen.getByRole('button', { name: 'Confirm current location' }))
    expect(screen.getByText('Source: Current location')).toBeInTheDocument()
    expect(screen.getByText('Latitude: 7.290572')).toBeInTheDocument()
  })

  it.each([
    [1, 'Location permission was denied. Allow access in your browser or choose another method.'],
    [2, 'Your current position is unavailable. Try again or choose another method.'],
  ])('shows a useful geolocation error for browser code %s', async (code, message) => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')
    configureGoogleAutocomplete()
    Object.defineProperty(navigator, 'geolocation', {
      configurable: true,
      value: { getCurrentPosition: vi.fn((success, error) => error({ code })) },
    })
    renderApp('/properties/new')

    await userEvent.click(screen.getByRole('button', { name: 'Use my current location' }))
    await userEvent.click(screen.getByRole('button', { name: 'Find my location' }))
    expect(await screen.findByText(message)).toBeInTheDocument()
  })

  it('keeps current coordinates when reverse geocoding fails and accepts a manually confirmed address', async () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')
    configureGoogleAutocomplete()
    configureGoogleLocationTools({ geocodeError: new Error('geocoder unavailable') })
    Object.defineProperty(navigator, 'geolocation', {
      configurable: true,
      value: { getCurrentPosition: vi.fn((success) => success({ coords: { latitude: 6.927079, longitude: 79.861244 } })) },
    })
    renderApp('/properties/new')

    await userEvent.click(screen.getByRole('button', { name: 'Use my current location' }))
    await userEvent.click(screen.getByRole('button', { name: 'Find my location' }))
    expect(await screen.findByText(/Google could not find a complete street address/)).toBeInTheDocument()
    await userEvent.type(screen.getByLabelText('Address'), '18 Marine Drive')
    await userEvent.type(screen.getByLabelText('City'), 'Colombo')
    await userEvent.click(screen.getByRole('button', { name: 'Confirm current location' }))

    expect(screen.getByText('Source: Current location')).toBeInTheDocument()
    expect(screen.getByText('Latitude: 6.927079')).toBeInTheDocument()
  })

  it('uses Place Details for a POI map click and populates its structured address', async () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')
    configureGoogleAutocomplete()
    const geocode = configureGoogleLocationTools({
      placeResult: {
        id: 'ChIJ-real-poi',
        formattedAddress: 'Temple of the Tooth, Kandy, Sri Lanka',
        addressComponents: [{ longText: 'Kandy', types: ['locality'] }],
        location: { lat: () => 7.293609, lng: () => 80.641325 },
      },
    })
    renderApp('/properties/new')

    await userEvent.click(screen.getByRole('button', { name: 'Pick on map' }))
    await waitFor(() => expect(mapClickHandler).toEqual(expect.any(Function)))
    const stop = vi.fn()
    await act(async () => mapClickHandler({
      placeId: 'ChIJ-real-poi',
      latLng: { lat: () => 7.2935, lng: () => 80.6412 },
      stop,
    }))

    expect(stop).toHaveBeenCalledTimes(1)
    expect(placeFetchFields).toHaveBeenCalledWith({
      fields: ['id', 'location', 'formattedAddress', 'addressComponents'],
    })
    expect(geocode).not.toHaveBeenCalled()
    expect(screen.getByLabelText('Address')).toHaveValue('Temple of the Tooth, Kandy, Sri Lanka')
    expect(screen.getByLabelText('City')).toHaveValue('Kandy')
    expect(screen.getByText('Latitude: 7.293609')).toBeInTheDocument()
    expect(screen.getByText('Longitude: 80.641325')).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Use this pin' }))
    await userEvent.type(screen.getByLabelText('Property title'), 'Temple View')
    await userEvent.type(screen.getByLabelText('Description'), 'A home near a known point of interest.')
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    await completePropertyDetails()
    await userEvent.click(screen.getByRole('button', { name: 'Create Property' }))
    await waitFor(() => expect(createProperty).toHaveBeenCalledWith(expect.objectContaining({
      googlePlaceId: 'ChIJ-real-poi',
      latitude: 7.293609,
      longitude: 80.641325,
    })))
  })

  it('selects and moves a map pin, reverse geocodes it, and keeps a nullable place ID valid', async () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')
    configureGoogleAutocomplete()
    configureGoogleLocationTools({ result: { ...reverseGeocodeResult, place_id: undefined } })
    renderApp('/properties/new')
    await userEvent.type(screen.getByLabelText('Property title'), 'Map House')
    await userEvent.type(screen.getByLabelText('Description'), 'Selected precisely on the map.')

    await userEvent.click(screen.getByRole('button', { name: 'Pick on map' }))
    await screen.findByRole('application', { name: /Interactive property location map/ })
    await waitFor(() => expect(mapClickHandler).toEqual(expect.any(Function)))
    await act(async () => mapClickHandler({ latLng: { lat: () => 7.290572, lng: () => 80.633728 } }))
    await waitFor(() => expect(screen.getByLabelText('Address')).toHaveValue(reverseGeocodeResult.formatted_address))

    advancedMarker.position = { lat: 7.291, lng: 80.634 }
    await act(async () => advancedMarker.listeners['gmp-dragend']())
    await waitFor(() => expect(screen.getByText('Latitude: 7.291000')).toBeInTheDocument())
    await userEvent.click(screen.getByRole('button', { name: 'Use this pin' }))
    expect(screen.getByText('Source: Map pin')).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    await completePropertyDetails()
    await userEvent.click(screen.getByRole('button', { name: 'Create Property' }))
    await waitFor(() => expect(createProperty).toHaveBeenCalledWith(expect.objectContaining({
      latitude: 7.291,
      longitude: 80.634,
      googlePlaceId: null,
    })))
  })

  it('keeps an exact map pin while the landlord refines an address after no geocoder result', async () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')
    configureGoogleAutocomplete()
    configureGoogleLocationTools({ result: null })
    renderApp('/properties/new')
    await userEvent.type(screen.getByLabelText('Property title'), 'Remote Cottage')
    await userEvent.type(screen.getByLabelText('Description'), 'A rural property with an exact map pin.')

    await userEvent.click(screen.getByRole('button', { name: 'Pick on map' }))
    await screen.findByRole('application', { name: /Interactive property location map/ })
    await waitFor(() => expect(mapClickHandler).toEqual(expect.any(Function)))
    await act(async () => mapClickHandler({
      latLng: { lat: () => 7.123456, lng: () => 80.654321 },
    }))

    expect(await screen.findByText('Exact location selected. Google could not find a complete address. Enter or confirm the address details below.')).toBeInTheDocument()
    expect(screen.getByLabelText('Address')).toHaveValue('')
    expect(screen.getByLabelText('City')).toHaveValue('')
    expect(screen.getByText('Latitude: 7.123456')).toBeInTheDocument()
    expect(screen.getByText('Longitude: 80.654321')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Use this pin' })).toBeEnabled()
    await userEvent.click(screen.getByRole('button', { name: 'Use this pin' }))

    expect(screen.getByText('Source: Map pin')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    expect(screen.getByText('Address is required.')).toBeInTheDocument()
    expect(screen.getByText('City is required.')).toBeInTheDocument()
    expect(screen.getByText('Latitude: 7.123456')).toBeInTheDocument()
    expect(screen.getByText('Longitude: 80.654321')).toBeInTheDocument()

    await userEvent.type(screen.getByLabelText('Address'), 'Near the Meemure trail entrance')
    await userEvent.type(screen.getByLabelText('City'), 'Meemure')
    expect(screen.getByText('Near the Meemure trail entrance')).toBeInTheDocument()
    expect(screen.getByText('Latitude: 7.123456')).toBeInTheDocument()
    expect(screen.getByText('Longitude: 80.654321')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    expect(screen.getByRole('heading', { name: 'Property Details' })).toBeInTheDocument()
  })

  it('preserves the pin and surfaces a configuration error when geocoding is denied', async () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')
    configureGoogleAutocomplete()
    configureGoogleLocationTools({ geocodeError: { code: 'REQUEST_DENIED' } })
    renderApp('/properties/new')

    await userEvent.click(screen.getByRole('button', { name: 'Pick on map' }))
    await waitFor(() => expect(mapClickHandler).toEqual(expect.any(Function)))
    await act(async () => mapClickHandler({
      latLng: { lat: () => 6.812345, lng: () => 80.112233 },
    }))

    expect(await screen.findByText('Location lookup is unavailable. Check the Google Geocoding API configuration.')).toBeInTheDocument()
    expect(screen.getByText('Latitude: 6.812345')).toBeInTheDocument()
    expect(screen.getByText('Longitude: 80.112233')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Use this pin' })).toBeEnabled()
  })

  it('does not let an older geocoder response overwrite a newer map click', async () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')
    configureGoogleAutocomplete()
    let resolveFirst
    let resolveSecond
    const geocode = vi.fn()
      .mockImplementationOnce(() => new Promise((resolve) => { resolveFirst = resolve }))
      .mockImplementationOnce(() => new Promise((resolve) => { resolveSecond = resolve }))
    configureGoogleLocationTools({ geocodeImplementation: geocode })
    renderApp('/properties/new')

    await userEvent.click(screen.getByRole('button', { name: 'Pick on map' }))
    await waitFor(() => expect(mapClickHandler).toEqual(expect.any(Function)))
    act(() => mapClickHandler({ latLng: { lat: () => 7.1, lng: () => 80.1 } }))
    act(() => mapClickHandler({ latLng: { lat: () => 7.2, lng: () => 80.2 } }))

    await act(async () => resolveSecond({ results: [{
      formatted_address: 'Newer location, Kandy',
      address_components: [{ long_name: 'Kandy', types: ['locality'] }],
    }] }))
    await waitFor(() => expect(screen.getByLabelText('Address')).toHaveValue('Newer location, Kandy'))

    await act(async () => resolveFirst({ results: [{
      formatted_address: 'Older location, Colombo',
      address_components: [{ long_name: 'Colombo', types: ['locality'] }],
    }] }))
    expect(screen.getByLabelText('Address')).toHaveValue('Newer location, Kandy')
    expect(screen.getByText('Latitude: 7.200000')).toBeInTheDocument()
    expect(screen.getByText('Longitude: 80.200000')).toBeInTheDocument()
  })

  it('shows a stored coordinate location when editing and allows it to be changed', async () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')
    configureGoogleAutocomplete()
    getMyProperties.mockResolvedValue([{
      ...property,
      latitude: 6.927079,
      longitude: 79.861244,
      googlePlaceId: 'ChIJ-harbour-view',
    }])

    renderApp(`/properties/${propertyId}/edit`)

    expect(await screen.findByTitle(`Map preview for ${property.address}`)).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Change location' }))
    expect(await screen.findByLabelText('Search address, building or place')).toBeInTheDocument()
    await selectGooglePlace({
      id: 'ChIJ-new-location',
      formattedAddress: '1 Temple Street, Kandy, Sri Lanka',
    })
    expect(await screen.findByText('1 Temple Street, Kandy, Sri Lanka')).toBeInTheDocument()
  })

  it('keeps a legacy edit address valid without inventing a map coordinate', async () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')
    configureGoogleAutocomplete()
    renderApp(`/properties/${propertyId}/edit`)

    expect(await screen.findByText('Legacy address — exact coordinates have not been saved.')).toBeInTheDocument()
    expect(screen.queryByTitle(/Map preview/)).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    expect(screen.getByRole('heading', { name: 'Property Details' })).toBeInTheDocument()
  })

  it('does not expose a property outside the authenticated owned collection', async () => {
    renderApp('/properties/99999999-9999-9999-9999-999999999999/edit')

    expect(await screen.findByRole('heading', { name: 'Property unavailable' })).toBeInTheDocument()
    expect(screen.getByText(/not in your authenticated property portfolio/)).toBeInTheDocument()
    expect(screen.queryByLabelText('Property title')).not.toBeInTheDocument()
  })

  it('confirms unsaved cancellation and provides a working back-to-list control', async () => {
    const router = renderApp('/properties/new')
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false)

    await userEvent.type(screen.getByLabelText('Property title'), 'Unsaved home')
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }))

    expect(confirm).toHaveBeenCalledWith('You have unsaved property changes. Leave without saving them?')
    expect(router.state.location.pathname).toBe('/properties/new')

    confirm.mockReturnValue(true)
    await userEvent.click(screen.getByRole('button', { name: 'Back to My Properties' }))

    await waitFor(() => expect(router.state.location.pathname).toBe('/modules/manage-properties'))
  })

  it('cancels a clean form without showing an unsaved warning', async () => {
    const router = renderApp('/properties/new')
    const confirm = vi.spyOn(window, 'confirm')

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }))

    await waitFor(() => expect(router.state.location.pathname).toBe('/modules/manage-properties'))
    expect(confirm).not.toHaveBeenCalled()
  })
})
