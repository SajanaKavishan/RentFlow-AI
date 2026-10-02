import { describe, expect, it } from 'vitest'
import { getAmenityPresentation } from './propertyListingCatalog'

describe('amenity presentation', () => {
  it('resolves older listing names without canonical metadata', () => {
    expect(getAmenityPresentation('Wi-Fi').icon).toBe('wifi')
    expect(getAmenityPresentation({ name: 'Car parking', canonicalKey: null }).icon).toBe('car')
    expect(getAmenityPresentation('Air Conditioning').icon).toBe('wind')
    expect(getAmenityPresentation('Swimming Pool').icon).toBe('waves')
    expect(getAmenityPresentation('Balcony').icon).toBe('balcony')
  })

  it('honors canonical metadata and preserves custom amenities', () => {
    expect(getAmenityPresentation({ name: 'Private lift', canonicalKey: 'elevator' }).icon).toBe('elevator')
    expect(getAmenityPresentation('Custom terrace')).toEqual({
      key: 'Custom terrace', label: 'Custom terrace', icon: 'amenity',
    })
  })
})
