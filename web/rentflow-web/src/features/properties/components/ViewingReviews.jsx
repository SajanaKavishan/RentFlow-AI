import { useEffect, useState } from 'react'
import { apiRequest } from '../../../core/api/apiClient.js'
import './viewing-reviews.css'

export default function ViewingReviews({ propertyId, landlord = false, refreshVersion = 0 }) {
  const [loaded, setLoaded] = useState(null)
  useEffect(() => {
    let active = true
    apiRequest(`/api/properties/${encodeURIComponent(propertyId)}/${landlord ? 'landlord-viewing-reviews' : 'viewing-reviews'}`, {
      authenticated: false, cache: 'no-store', errorMessage: 'Viewing reviews unavailable.',
    }).then((summary) => {
      if (!Number.isInteger(summary?.reviewCount) || summary.reviewCount < 0 || !Array.isArray(summary.reviews)
        || (summary.reviewCount > 0 && (!Number.isFinite(summary.averageRating) || summary.averageRating < 1 || summary.averageRating > 5))
        || summary.reviews.some((review) => !Number.isInteger(review?.rating) || review.rating < 1 || review.rating > 5 || typeof review.comment !== 'string' || !/^\d{4}-\d{2}$/.test(review.reviewMonth))) return
      if (active) setLoaded({ propertyId, landlord, summary })
    }).catch(() => { if (active) setLoaded(null) })
    return () => { active = false }
  }, [propertyId, landlord, refreshVersion])
  if (loaded?.propertyId !== propertyId || loaded.landlord !== landlord || !loaded.summary.reviewCount) return null
  const { averageRating, reviewCount, reviews } = loaded.summary
  return <section className="viewing-reviews" aria-label={landlord ? 'Landlord experience' : 'Viewing experience'}>
    <h2>{landlord ? 'Landlord experience' : 'Viewing experience'}</h2>
    <p className="viewing-reviews__average">{averageRating.toFixed(1)} ★ <span>· {reviewCount} verified {reviewCount === 1 ? 'viewing' : 'viewings'}</span></p>
    {reviews.slice(0, 5).map((review, index) => <article key={`${review.reviewMonth}:${index}`}>
      <p className="viewing-reviews__stars" aria-label={`${review.rating} out of 5`}>{'★'.repeat(review.rating)}{'☆'.repeat(5 - review.rating)}</p>
      <p>{review.comment}</p>
      <small>Verified viewing · {formatMonth(review.reviewMonth)}</small>
    </article>)}
  </section>
}

function formatMonth(value) {
  if (!/^\d{4}-\d{2}$/.test(value)) return ''
  const date = new Date(`${value}-01T00:00:00Z`)
  return Number.isNaN(date.getTime()) ? '' : date.toLocaleDateString(undefined, { month: 'short', year: 'numeric', timeZone: 'UTC' })
}
