import { cleanup, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
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
  it('shows every real image in a keyboard-accessible details gallery', async () => {
    getPropertyImages.mockResolvedValue([
      { id: 'image-1' },
      { id: 'image-2' },
      { id: 'image-3' },
      { id: 'image-4' },
    ])
    getPropertyImageUrl.mockImplementation((propertyId, imageId) => (
      Promise.resolve({ url: `https://images.example/${propertyId}/${imageId}.jpg` })
    ))

    render(
      <PropertyImageGallery
        propertyId="property-1"
        alt="Harbour View"
        variant="details"
        matchScore={97}
      />,
    )

    expect(await screen.findByRole('img', { name: 'Harbour View property photo 1 of 4' }))
      .toHaveAttribute('src', 'https://images.example/property-1/image-1.jpg')
    expect(screen.getByLabelText('97 percent AI match')).toBeInTheDocument()
    expect(screen.getAllByRole('button', { name: /Show image/ })).toHaveLength(4)

    await userEvent.click(screen.getByRole('button', { name: 'Next image for Harbour View' }))
    expect(screen.getByRole('img', { name: 'Harbour View property photo 2 of 4' }))
      .toHaveAttribute('src', 'https://images.example/property-1/image-2.jpg')

    await userEvent.click(screen.getByRole('button', { name: 'Show image 4 of 4 for Harbour View' }))
    expect(screen.getByRole('img', { name: 'Harbour View property photo 4 of 4' }))
      .toHaveAttribute('src', 'https://images.example/property-1/image-4.jpg')
    expect(screen.getByRole('button', { name: 'Show image 4 of 4 for Harbour View' }))
      .toHaveAttribute('aria-pressed', 'true')
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
