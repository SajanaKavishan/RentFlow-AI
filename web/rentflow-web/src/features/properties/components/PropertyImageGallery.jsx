import { useEffect, useState } from 'react'
import Icon from '../../../shared/ui/Icons.jsx'
import {
  getPropertyImages,
  getPropertyImageUrl,
} from '../services/propertyApiService.js'

export default function PropertyImageGallery({
  propertyId,
  variant = 'gallery',
  alt = 'Property',
  matchScore = null,
}) {
  const [images, setImages] = useState([])
  const [loading, setLoading] = useState(true)
  const [failed, setFailed] = useState(false)
  const [activeIndex, setActiveIndex] = useState(0)

  useEffect(() => {
    let active = true

    async function loadImages() {
      setLoading(true)
      setFailed(false)
      setActiveIndex(0)

      try {
        const imageRecords = await getPropertyImages(propertyId)
        const resolvedImages = await Promise.all(
          imageRecords.map(async (image) => {
            try {
              const result = await getPropertyImageUrl(propertyId, image.id)
              return { ...image, url: result.url }
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
    return () => { active = false }
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

  if (variant === 'details') {
    const activeImage = images[activeIndex] || images[0]
    const accessibleAlt = alt === 'Property'
      ? `${alt} photo ${activeIndex + 1} of ${images.length}`
      : `${alt} property photo ${activeIndex + 1} of ${images.length}`
    const hasMultipleImages = images.length > 1
    const resolvedMatchScore = Number(matchScore)
    const hasMatchScore = matchScore !== null
      && matchScore !== ''
      && Number.isFinite(resolvedMatchScore)
      && resolvedMatchScore >= 0
      && resolvedMatchScore <= 100
    const showPrevious = () => setActiveIndex((current) => (
      current === 0 ? images.length - 1 : current - 1
    ))
    const showNext = () => setActiveIndex((current) => (
      current === images.length - 1 ? 0 : current + 1
    ))

    return (
      <div className="property-image-gallery property-image-gallery--details">
        <div className="property-image-gallery__stage">
          <img src={activeImage.url} alt={accessibleAlt} />

          {hasMatchScore && (
            <span
              className="property-image-gallery__match"
              aria-label={`${Math.round(resolvedMatchScore)} percent AI match`}
            >
              <Icon name="sparkles" size={15} />
              {Math.round(resolvedMatchScore)}% AI Match
            </span>
          )}

          {hasMultipleImages && (
            <>
              <button
                type="button"
                className="property-image-gallery__arrow property-image-gallery__arrow--previous"
                aria-label={`Previous image for ${alt}`}
                onClick={showPrevious}
              >
                <Icon name="chevronLeft" size={22} />
              </button>
              <button
                type="button"
                className="property-image-gallery__arrow property-image-gallery__arrow--next"
                aria-label={`Next image for ${alt}`}
                onClick={showNext}
              >
                <Icon name="chevronRight" size={22} />
              </button>
              <span className="property-image-gallery__count" aria-live="polite">
                {activeIndex + 1} / {images.length}
              </span>
            </>
          )}
        </div>

        {hasMultipleImages && (
          <div className="property-image-gallery__thumbnails" aria-label="Choose a property photo">
            {images.map((image, index) => (
              <button
                type="button"
                key={image.id}
                className={index === activeIndex ? 'is-active' : ''}
                aria-label={`Show image ${index + 1} of ${images.length} for ${alt}`}
                aria-pressed={index === activeIndex}
                onClick={() => setActiveIndex(index)}
              >
                <img src={image.url} alt="" loading="lazy" />
              </button>
            ))}
          </div>
        )}
      </div>
    )
  }

  const displayedImages = variant === 'cover' ? images.slice(0, 1) : images

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
