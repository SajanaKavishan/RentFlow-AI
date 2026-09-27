import { describe, expect, it } from 'vitest'
import {
  getGoogleMapsEmbedUrl,
  getGoogleMapsSearchUrl,
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
})
