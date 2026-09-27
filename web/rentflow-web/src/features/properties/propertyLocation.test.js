import { describe, expect, it } from 'vitest'
import { cityFromAddressComponents } from './propertyLocation.js'

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
})
