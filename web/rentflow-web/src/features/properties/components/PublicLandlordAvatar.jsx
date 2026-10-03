import { useState } from 'react'
import { getPublicLandlordImageUrl } from '../services/propertyApiService.js'

export default function PublicLandlordAvatar({ propertyId, summary, className = '' }) {
  const [failedImage, setFailedImage] = useState(null)
  const imageUrl = getPublicLandlordImageUrl(propertyId)
  const initials = summary.displayName.trim().split(/\s+/).filter(Boolean)
    .slice(0, 2).map((part) => Array.from(part)[0].toUpperCase()).join('') || 'L'
  return <span className={`property-listed-by__avatar ${className}`}>
    {summary.hasProfileImage && failedImage !== imageUrl
      ? <img src={imageUrl} alt={`${summary.displayName} profile`} onError={() => setFailedImage(imageUrl)} />
      : <span role="img" aria-label={`${summary.displayName} initials`}>{initials}</span>}
  </span>
}
