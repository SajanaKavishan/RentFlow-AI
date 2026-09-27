import { useEffect, useState } from 'react'
import {
  getPropertyImages,
  getPropertyImageUrl,
} from '../services/propertyApiService.js'

export default function PropertyImageGallery({
  propertyId,
  variant = 'gallery',
  alt = 'Property',
}) {
  const [images, setImages] = useState([])
  const [loading, setLoading] = useState(true)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    let active = true

    async function loadImages() {
      setLoading(true)
      setFailed(false)

      try {
        const imageRecords = await getPropertyImages(propertyId)

        const resolvedImages = await Promise.all(
          imageRecords.map(async (image) => {
            try {
              const result = await getPropertyImageUrl(
                propertyId,
                image.id,
              )

              return {
                ...image,
                url: result.url,
              }
            } catch {
              return null
            }
          }),
        )

        if (active) {
          const availableImages = resolvedImages.filter(Boolean)
          setImages(availableImages)
          setFailed(imageRecords.length > 0 && availableImages.length === 0)
        }
      } catch {
        if (active) {
          setImages([])
          setFailed(true)
        }
      } finally {
        if (active) setLoading(false)
      }
    }

    loadImages()

    return () => {
      active = false
    }
  }, [propertyId])

  if (loading) {
    return <div className="property-image-state" role="status">Loading property photos...</div>
  }

  if (failed) {
    return <div className="property-image-state" role="alert">Property photos unavailable.</div>
  }

  if (images.length === 0) {
    return <div className="property-image-state">No property photos uploaded yet.</div>
  }

  const displayedImages = variant === 'cover'
    ? images.slice(0, 1)
    : variant === 'details'
      ? images.slice(0, 3)
      : images

  return (
    <div className={`property-image-gallery property-image-gallery--${variant} property-image-gallery--count-${displayedImages.length}`}>
      {displayedImages.map((image, index) => (
        <img
          key={image.id}
          src={image.url}
          alt={alt === 'Property' ? alt : `${alt} property photo ${index + 1}`}
          loading="lazy"
        />
      ))}
    </div>
  )
}
