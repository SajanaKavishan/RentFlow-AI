import { describe, expect, it } from 'vitest'
import {
  getGoogleMapsEmbedUrl,
  getGoogleMapsSearchUrl,
  getPropertyMapQuery,
  getPropertyLocation,
} from './propertyMap.js'

describe('property map URLs', () => {
  it('builds its location from only the trimmed property address and city', () => {
    expect(getPropertyLocation(' 12 King’s Road #4 ', ' Colombo 03 '))
      .toBe('12 King’s Road #4, Colombo 03')
    expect(getPropertyLocation('', ' Colombo ')).toBe('Colombo')
    expect(getPropertyLocation(undefined, null)).toBe('')
  })

  it('encodes the real location and key for Maps Embed', () => {
    const url = new URL(getGoogleMapsEmbedUrl(
      'browser-key&safe',
      '12 King’s Road #4, Colombo 03',
    ))

    expect(`${url.origin}${url.pathname}`).toBe('https://www.google.com/maps/embed/v1/place')
    expect(url.searchParams.get('key')).toBe('browser-key&safe')
    expect(url.searchParams.get('q')).toBe('12 King’s Road #4, Colombo 03')
  })

  it('does not build an embed URL without both a key and usable location', () => {
    expect(getGoogleMapsEmbedUrl('', '18 Marine Drive, Colombo')).toBe('')
    expect(getGoogleMapsEmbedUrl('browser-key', '')).toBe('')
  })

  it('builds a key-free Google Maps search action from the real location', () => {
    const url = new URL(getGoogleMapsSearchUrl('18 Marine Drive, Colombo'))

    expect(`${url.origin}${url.pathname}`).toBe('https://www.google.com/maps/search/')
    expect(url.searchParams.get('api')).toBe('1')
    expect(url.searchParams.get('query')).toBe('18 Marine Drive, Colombo')
  })

  it('prefers stored coordinates and otherwise falls back to address and city', () => {
    expect(getPropertyMapQuery({
      address: '18 Marine Drive', city: 'Colombo', latitude: 6.927079, longitude: 79.861244,
    })).toBe('6.927079,79.861244')
    expect(getPropertyMapQuery({
      address: '18 Marine Drive', city: 'Colombo', latitude: null, longitude: null,
    })).toBe('18 Marine Drive, Colombo')
  })

  it('adds a real Google place ID to the external Maps action when available', () => {
    const url = new URL(getGoogleMapsSearchUrl('6.927079,79.861244', 'ChIJ-real-place'))
    expect(url.searchParams.get('query')).toBe('6.927079,79.861244')
    expect(url.searchParams.get('query_place_id')).toBe('ChIJ-real-place')
  })
})
