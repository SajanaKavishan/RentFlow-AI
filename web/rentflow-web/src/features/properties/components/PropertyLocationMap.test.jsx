import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import PropertyLocationMap from './PropertyLocationMap.jsx'

afterEach(() => {
  cleanup()
  vi.unstubAllEnvs()
})

describe('PropertyLocationMap', () => {
  it('renders an accessible lazy map with a browser key and real address', () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')

    render(<PropertyLocationMap address="18 Marine Drive" city="Colombo" />)

    const frame = screen.getByTitle('Map showing 18 Marine Drive, Colombo')
    const url = new URL(frame.getAttribute('src'))
    expect(frame).toHaveAttribute('loading', 'lazy')
    expect(url.searchParams.get('key')).toBe('test-browser-key')
    expect(url.searchParams.get('q')).toBe('18 Marine Drive, Colombo')
    expect(screen.getByRole('link', { name: /Open in Google Maps/ }))
      .toHaveAttribute('href', expect.stringContaining('query=18+Marine+Drive%2C+Colombo'))
  })

  it('keeps the real address and shows a truthful fallback without a key', () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', '')

    render(<PropertyLocationMap address="18 Marine Drive" city="Colombo" />)

    expect(screen.getByText('18 Marine Drive, Colombo')).toBeInTheDocument()
    expect(screen.getByText('Map preview unavailable')).toBeInTheDocument()
    expect(screen.queryByTitle(/Map showing/)).not.toBeInTheDocument()
  })

  it('prefers saved coordinates for the map and place ID for the external action', () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')

    render(
      <PropertyLocationMap
        address="18 Marine Drive"
        city="Colombo"
        latitude={6.927079}
        longitude={79.861244}
        googlePlaceId="ChIJ-real-place"
      />,
    )

    const frameUrl = new URL(screen.getByTitle('Map showing 18 Marine Drive, Colombo').getAttribute('src'))
    expect(frameUrl.searchParams.get('q')).toBe('6.927079,79.861244')
    const actionUrl = new URL(screen.getByRole('link', { name: /Open in Google Maps/ }).getAttribute('href'))
    expect(actionUrl.searchParams.get('query_place_id')).toBe('ChIJ-real-place')
  })

  it('does not offer fabricated navigation when no location is available', () => {
    vi.stubEnv('VITE_GOOGLE_MAPS_API_KEY', 'test-browser-key')

    render(<PropertyLocationMap address=" " city={null} />)

    expect(screen.getByText('No property address is available.')).toBeInTheDocument()
    expect(screen.getByText('This property does not include a usable address.')).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: /Open in Google Maps/ })).not.toBeInTheDocument()
    expect(screen.queryByTitle(/Map showing/)).not.toBeInTheDocument()
  })
})
