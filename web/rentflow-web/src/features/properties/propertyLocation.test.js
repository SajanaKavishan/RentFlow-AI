import { describe, expect, it } from 'vitest'
import {
  cityFromAddressComponents,
  locationFromGeocoderResult,
  locationFromGeocoderResults,
} from './propertyLocation.js'

describe('property location normalization', () => {
  it('prefers a structured locality over broader address components', () => {
    expect(cityFromAddressComponents([
      { longText: 'Western Province', types: ['administrative_area_level_1'] },
      { longText: 'Colombo', types: ['locality'] },
      { longText: 'Colombo District', types: ['administrative_area_level_2'] },
    ])).toBe('Colombo')
  })

  it('uses only supported structured city-like component types', () => {
    expect(cityFromAddressComponents([
      { longText: 'London', types: ['postal_town'] },
    ])).toBe('London')
    expect(cityFromAddressComponents([
      { longText: 'Arbitrary display text', types: ['route'] },
    ])).toBe('')
  })

  it('normalizes a reverse-geocoder result without retaining the raw response', () => {
    expect(locationFromGeocoderResult({
      formatted_address: '18 Marine Drive, Colombo, Sri Lanka',
      address_components: [{ long_name: 'Colombo', types: ['locality'] }],
      place_id: 'ChIJ-colombo',
      geometry: { viewport: 'must not be copied' },
    }, 6.927079, 79.861244)).toEqual({
      address: '18 Marine Drive, Colombo, Sri Lanka',
      city: 'Colombo',
      latitude: 6.927079,
      longitude: 79.861244,
      googlePlaceId: 'ChIJ-colombo',
    })
  })

  it('accepts a locality-only reverse-geocode result without requiring a street route', () => {
    expect(locationFromGeocoderResults([{
      formatted_address: 'Meemure, Sri Lanka',
      address_components: [{ long_name: 'Meemure', types: ['locality'] }],
    }], 7.4321, 80.8421)).toEqual({
      address: 'Meemure, Sri Lanka',
      city: 'Meemure',
      latitude: 7.4321,
      longitude: 80.8421,
      googlePlaceId: null,
    })
  })

  it('uses the preferred admin-area fallback across all geocoder results', () => {
    const location = locationFromGeocoderResults([
      {
        formatted_address: 'Central Province, Sri Lanka',
        address_components: [{ long_name: 'Udunuwara', types: ['administrative_area_level_3'] }],
      },
      {
        address_components: [{ long_name: 'Kandy District', types: ['administrative_area_level_2'] }],
      },
    ], 7.25, 80.56)

    expect(location.city).toBe('Kandy District')
    expect(location.address).toBe('Central Province, Sri Lanka')
  })

  it('keeps exact coordinates when Google returns no usable geocoder result', () => {
    expect(locationFromGeocoderResults([], 7.123456, 80.654321)).toEqual({
      address: '',
      city: '',
      latitude: 7.123456,
      longitude: 80.654321,
      googlePlaceId: null,
    })
  })
})
