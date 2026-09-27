import { cleanup, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import PropertyImageGallery from './PropertyImageGallery.jsx'
import {
  getPropertyImages,
  getPropertyImageUrl,
} from '../services/propertyApiService.js'

vi.mock('../services/propertyApiService.js', () => ({
  getPropertyImages: vi.fn(),
  getPropertyImageUrl: vi.fn(),
}))

afterEach(() => {
  cleanup()
  vi.clearAllMocks()
})

describe('PropertyImageGallery', () => {
  it('shows one primary and at most two real secondary images for details', async () => {
    getPropertyImages.mockResolvedValue([
      { id: 'image-1' },
      { id: 'image-2' },
      { id: 'image-3' },
      { id: 'image-4' },
    ])
    getPropertyImageUrl.mockImplementation((propertyId, imageId) => (
      Promise.resolve({ url: `https://images.example/${propertyId}/${imageId}.jpg` })
    ))

    const { container } = render(
      <PropertyImageGallery propertyId="property-1" alt="Harbour View" variant="details" />,
    )

    await waitFor(() => expect(screen.getAllByRole('img')).toHaveLength(3))
    expect(screen.getAllByRole('img').map((image) => image.getAttribute('src'))).toEqual([
      'https://images.example/property-1/image-1.jpg',
      'https://images.example/property-1/image-2.jpg',
      'https://images.example/property-1/image-3.jpg',
    ])
    expect(container.querySelector('.property-image-gallery--details'))
      .toHaveClass('property-image-gallery--count-3')
  })

  it('preserves the no-photo and failed-photo fallback states', async () => {
    getPropertyImages.mockResolvedValueOnce([])
    const { rerender } = render(
      <PropertyImageGallery propertyId="property-empty" variant="details" />,
    )

    expect(await screen.findByText('No property photos uploaded yet.')).toBeInTheDocument()

    getPropertyImages.mockRejectedValueOnce(new Error('Unavailable'))
    rerender(<PropertyImageGallery propertyId="property-failed" variant="details" />)

    expect(await screen.findByRole('alert')).toHaveTextContent('Property photos unavailable.')
  })
})
