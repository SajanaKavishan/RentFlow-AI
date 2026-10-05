import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import Icon from '../../../shared/ui/Icons.jsx'

export default function PropertyImageCarousel({ property, images = [], match, liked, favoritePending, onToggleFavorite }) {
  const [activeIndex, setActiveIndex] = useState(0)
  const [failedImages, setFailedImages] = useState(() => new Set())
  const hasMultipleImages = images.length > 1

  useEffect(() => {
    if (!hasMultipleImages || window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return undefined
    const interval = window.setInterval(() => {
      setActiveIndex((current) => (current + 1) % images.length)
    }, 4500)
    return () => window.clearInterval(interval)
  }, [hasMultipleImages, images.length])

  const showPrevious = () => setActiveIndex((current) => (current - 1 + images.length) % images.length)
  const showNext = () => setActiveIndex((current) => (current + 1) % images.length)

  return <div className="property-card__image">
    <Link className="property-card__image-link" to={`/properties/${property.id}`} aria-label={`View ${property.title}`}>
      {images.length > 0 && !failedImages.has(images[activeIndex])
        ? <img src={images[activeIndex]} alt={`${property.title} — photo ${activeIndex + 1} of ${images.length}`}
            onError={() => setFailedImages((current) => new Set(current).add(images[activeIndex]))} />
        : <div className="property-card__placeholder"><Icon name="building" size={38} /><span>No property photos yet</span></div>}
    </Link>
    {match && <span className="property-card__match" aria-label={`${match.matchScore} percent match`}><Icon name="sparkles" size={13} />{match.matchScore}% Match</span>}
    {onToggleFavorite && <button type="button" className={`property-card__favorite${liked ? ' is-liked' : ''}`} aria-label={`${liked ? 'Remove' : 'Add'} ${property.title} ${liked ? 'from' : 'to'} liked properties`} aria-pressed={liked} disabled={favoritePending} onClick={() => onToggleFavorite(property.id)}><Icon name="heart" size={19} /></button>}
    {hasMultipleImages && <>
      <button type="button" className="property-card__carousel-button property-card__carousel-button--previous" aria-label={`Previous image for ${property.title}`} onClick={showPrevious}><Icon name="chevronLeft" size={18} /></button>
      <button type="button" className="property-card__carousel-button property-card__carousel-button--next" aria-label={`Next image for ${property.title}`} onClick={showNext}><Icon name="chevronRight" size={18} /></button>
      <div className="property-card__carousel-dots" aria-label={`Choose image for ${property.title}`}>{images.map((image, index) => <button key={image} type="button" className={index === activeIndex ? 'is-active' : ''} aria-label={`Show image ${index + 1} of ${images.length} for ${property.title}`} aria-current={index === activeIndex ? 'true' : undefined} onClick={() => setActiveIndex(index)} />)}</div>
    </>}
  </div>
}
