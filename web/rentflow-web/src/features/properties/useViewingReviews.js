import { useEffect, useState } from 'react'
import { apiRequest } from '../../core/api/apiClient.js'

export function validViewingSummary(summary) {
  return Number.isInteger(summary?.reviewCount) && summary.reviewCount >= 0 && Array.isArray(summary.reviews)
    && (summary.reviewCount === 0 || (Number.isFinite(summary.averageRating) && summary.averageRating >= 1 && summary.averageRating <= 5))
    && summary.reviews.every((review) => Number.isInteger(review?.rating) && review.rating >= 1 && review.rating <= 5 && typeof review.comment === 'string' && /^\d{4}-(0[1-9]|1[0-2])$/.test(review.reviewMonth))
}

export function useViewingReviews(propertyId, landlord = false, refreshVersion = 0, enabled = true) {
  const [loaded, setLoaded] = useState(null)
  useEffect(() => {
    if (!enabled || !propertyId) return
    let active = true
    apiRequest(`/api/properties/${encodeURIComponent(propertyId)}/${landlord ? 'landlord-viewing-reviews' : 'viewing-reviews'}`, {
      authenticated: false, cache: 'no-store', errorMessage: 'Viewing reviews unavailable.',
    }).then((summary) => {
      if (active && validViewingSummary(summary)) setLoaded({ propertyId, landlord, refreshVersion, summary })
    }).catch(() => { if (active) setLoaded(null) })
    return () => { active = false }
  }, [propertyId, landlord, refreshVersion, enabled])
  return enabled && loaded?.propertyId === propertyId && loaded.landlord === landlord && loaded.refreshVersion === refreshVersion ? loaded.summary : null
}
