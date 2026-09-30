import { useEffect, useState } from 'react'
import Icon from '../../../shared/ui/Icons.jsx'
import {
  deletePropertyImage,
  getPropertyImages,
  getPropertyImageUrl,
  reorderPropertyImages,
  setPrimaryPropertyImage,
} from '../services/propertyApiService.js'

export default function PropertyImageGallery({
  propertyId,
  variant = 'gallery',
  alt = 'Property',
  matchScore = null,
  manageable = false,
}) {
  const [images, setImages] = useState([])
  const [loading, setLoading] = useState(true)
  const [failed, setFailed] = useState(false)
  const [activeIndex, setActiveIndex] = useState(0)
  const [imageAction, setImageAction] = useState('')
  const [actionError, setActionError] = useState('')

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

  async function markPrimary(imageId) {
    setImageAction(`primary-${imageId}`)
    setActionError('')
    try {
      await setPrimaryPropertyImage(propertyId, imageId)
      setImages((current) => current.map((image) => ({
        ...image,
        isPrimary: image.id === imageId,
      })))
    } catch (error) {
      setActionError(error instanceof Error ? error.message : 'Unable to set the cover photo.')
    } finally {
      setImageAction('')
    }
  }

  async function deleteImage(image) {
    if (!window.confirm(`Delete ${image.originalFileName || 'this property photo'}?`)) return

    setImageAction(`delete-${image.id}`)
    setActionError('')
    try {
      await deletePropertyImage(propertyId, image.id)
      setImages((current) => {
        const remaining = current.filter((item) => item.id !== image.id)
        if (image.isPrimary && remaining.length > 0) {
          return remaining.map((item, index) => ({ ...item, isPrimary: index === 0 }))
        }
        return remaining
      })
    } catch (error) {
      setActionError(error instanceof Error ? error.message : 'Unable to delete the photo.')
    } finally {
      setImageAction('')
    }
  }

  async function moveImage(index, direction) {
    const destination = index + direction
    if (destination < 0 || destination >= images.length) return

    const reordered = [...images]
    const [moved] = reordered.splice(index, 1)
    reordered.splice(destination, 0, moved)
    setImageAction(`order-${moved.id}`)
    setActionError('')
    try {
      const response = await reorderPropertyImages(
        propertyId,
        reordered.map((image) => image.id),
      )
      const metadata = new Map(response.map((image) => [image.id, image]))
      setImages(reordered.map((image) => ({ ...image, ...metadata.get(image.id) })))
    } catch (error) {
      setActionError(error instanceof Error ? error.message : 'Unable to reorder property photos.')
    } finally {
      setImageAction('')
    }
  }

  if (manageable) {
    return (
      <div className="property-image-manager">
        {actionError && <p className="property-image-manager__error" role="alert">{actionError}</p>}
        <ul>
          {images.map((image, index) => (
            <li key={image.id}>
              <img src={image.url} alt={`${alt} photo ${index + 1}`} />
              <div className="property-image-manager__details">
                <span>{image.isPrimary ? 'Cover photo' : `Photo ${index + 1}`}</span>
                <div className="property-image-manager__actions">
                  <button
                    type="button"
                    onClick={() => markPrimary(image.id)}
                    disabled={image.isPrimary || Boolean(imageAction)}
                  >
                    {image.isPrimary
                      ? 'Current cover'
                      : imageAction === `primary-${image.id}` ? 'Saving...' : 'Make cover'}
                  </button>
                  <button
                    type="button"
                    aria-label={`Move photo ${index + 1} left`}
                    onClick={() => moveImage(index, -1)}
                    disabled={index === 0 || Boolean(imageAction)}
                  >
                    <Icon name="chevronLeft" size={17} />
                  </button>
                  <button
                    type="button"
                    aria-label={`Move photo ${index + 1} right`}
                    onClick={() => moveImage(index, 1)}
                    disabled={index === images.length - 1 || Boolean(imageAction)}
                  >
                    <Icon name="chevronRight" size={17} />
                  </button>
                  <button
                    type="button"
                    className="is-danger"
                    onClick={() => deleteImage(image)}
                    disabled={Boolean(imageAction)}
                  >
                    {imageAction === `delete-${image.id}` ? 'Deleting...' : 'Delete'}
                  </button>
                </div>
              </div>
            </li>
          ))}
        </ul>
      </div>
    )
  }

  if (variant === 'details') {
    const primary = images.find((image) => image.isPrimary)
    const displayImages = primary
      ? [primary, ...images.filter((image) => image.id !== primary.id)]
      : images
    const activeImage = displayImages[activeIndex] || displayImages[0]
    const accessibleAlt = alt === 'Property'
      ? `${alt} photo ${activeIndex + 1} of ${displayImages.length}`
      : `${alt} property photo ${activeIndex + 1} of ${displayImages.length}`
    const hasMultipleImages = displayImages.length > 1
    const resolvedMatchScore = Number(matchScore)
    const hasMatchScore = matchScore !== null
      && matchScore !== ''
      && Number.isFinite(resolvedMatchScore)
      && resolvedMatchScore >= 0
      && resolvedMatchScore <= 100
    const showPrevious = () => setActiveIndex((current) => (
      current === 0 ? displayImages.length - 1 : current - 1
    ))
    const showNext = () => setActiveIndex((current) => (
      current === displayImages.length - 1 ? 0 : current + 1
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
              <div className="property-image-gallery__dots" aria-label={`Choose hero image for ${alt}`}>
                {displayImages.map((image, index) => (
                  <button
                    type="button"
                    key={image.id}
                    className={index === activeIndex ? 'is-active' : ''}
                    aria-label={`Show hero image ${index + 1} of ${displayImages.length} for ${alt}`}
                    aria-current={index === activeIndex ? 'true' : undefined}
                    onClick={() => setActiveIndex(index)}
                  />
                ))}
              </div>
            </>
          )}
        </div>

        {hasMultipleImages && (
          <div className="property-image-gallery__thumbnails" aria-label="Choose a property photo">
            {displayImages.map((image, index) => (
              <button
                type="button"
                key={image.id}
                className={index === activeIndex ? 'is-active' : ''}
                aria-label={`Show image ${index + 1} of ${displayImages.length} for ${alt}`}
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

  const primaryImage = images.find((image) => image.isPrimary)
  const displayedImages = variant === 'cover'
    ? [primaryImage || images[0]]
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
