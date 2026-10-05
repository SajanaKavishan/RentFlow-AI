import { useViewingReviews } from '../useViewingReviews.js'
import './viewing-reviews.css'

export function CompactViewingRating({ summary, onClick }) {
  if (!summary?.reviewCount) return null
  const label = `${summary.averageRating.toFixed(1)} out of 5 from ${summary.reviewCount} verified ${summary.reviewCount === 1 ? 'viewing' : 'viewings'}`
  const content = <><span className="compact-viewing-rating__star" aria-hidden="true">★</span><strong>{summary.averageRating.toFixed(1)}</strong><span>{summary.reviewCount} verified {summary.reviewCount === 1 ? 'viewing' : 'viewings'}</span></>
  return onClick
    ? <button type="button" className="compact-viewing-rating" aria-label={label} onClick={onClick}>{content}</button>
    : <span className="compact-viewing-rating" aria-label={label}>{content}</span>
}

export function ViewingReviewSummary({ summary, title = 'Viewing experience', showEmpty = false, sectionRef }) {
  if (!summary || (!summary.reviewCount && !showEmpty)) return null
  return <section ref={sectionRef} tabIndex={-1} className="viewing-reviews" aria-label={title}>
    <h2>{title}</h2>
    {summary.reviewCount === 0 ? <p>No verified viewing feedback yet.</p> : <>
      <p className="viewing-reviews__average" aria-label={`${summary.averageRating.toFixed(1)} out of 5`}>{summary.averageRating.toFixed(1)} <span aria-hidden="true">★</span></p>
      <p className="viewing-reviews__count">{summary.reviewCount} verified {summary.reviewCount === 1 ? 'viewing' : 'viewings'}</p>
      {summary.reviews.filter((review) => review.comment.trim()).slice(0, 5).map((review, index) => <article key={`${review.reviewMonth}:${index}`}>
        <p className="viewing-reviews__stars" aria-label={`${review.rating} out of 5`}>{'★'.repeat(review.rating)}{'☆'.repeat(5 - review.rating)}</p>
        <p>{review.comment}</p>
        <small>Verified viewing · {formatMonth(review.reviewMonth)}</small>
      </article>)}
    </>}
  </section>
}

export default function ViewingReviews({ propertyId, landlord = false, refreshVersion = 0 }) {
  const summary = useViewingReviews(propertyId, landlord, refreshVersion)
  return <ViewingReviewSummary summary={summary} title={landlord ? 'Landlord experience' : 'Viewing experience'} />
}

function formatMonth(value) {
  const date = new Date(`${value}-01T00:00:00Z`)
  return Number.isNaN(date.getTime()) ? '' : date.toLocaleDateString(undefined, { month: 'short', year: 'numeric', timeZone: 'UTC' })
}
