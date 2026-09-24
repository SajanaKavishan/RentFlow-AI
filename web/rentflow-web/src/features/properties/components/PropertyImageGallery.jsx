import { useEffect, useState } from 'react'
import {
  getPropertyImages,
  getPropertyImageUrl,
} from '../services/propertyApiService.js'

export default function PropertyImageGallery({ propertyId }) {
  const [images, setImages] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let active = true

    async function loadImages() {
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
          setImages(resolvedImages.filter(Boolean))
        }
      } catch {
        if (active) setImages([])
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
    return <p>Loading property images...</p>
  }

  if (images.length === 0) {
    return <p>No property images uploaded yet.</p>
  }

  return (
    <div className="property-image-gallery">
      {images.map((image) => (
        <img
          key={image.id}
          src={image.url}
          alt="Property"
          loading="lazy"
        />
      ))}
    </div>
  )
}