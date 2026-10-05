import { useEffect, useState } from 'react'
import { apiRequest } from '../../../core/api/apiClient.js'
import { PageHeader } from '../../../shared/ui/States.jsx'
import { validViewingSummary } from '../useViewingReviews.js'
import { CompactViewingRating, ViewingReviewSummary } from '../components/ViewingReviews.jsx'
import './landlord-reviews.css'

function PropertyFeedback({ property }) {
  const [expanded, setExpanded] = useState(false)
  const [full, setFull] = useState(null)
  const [attempt, setAttempt] = useState(0)
  const [error, setError] = useState(false)
  useEffect(() => {
    if (!expanded || full) return undefined
    let active = true
    apiRequest(`/api/landlord/viewing-reviews/properties/${encodeURIComponent(property.propertyId)}`, {
      cache: 'no-store', errorMessage: 'Could not load all property reviews.',
    }).then((summary) => {
      if (!validViewingSummary(summary)) throw new Error('Invalid feedback')
      if (active) setFull(summary)
    }).catch(() => { if (active) setError(true) })
    return () => { active = false }
  }, [expanded, full, property.propertyId, attempt])

  const summary = expanded && full ? full : { ...property, reviews: property.recentReviews }
  return <div className="landlord-reviews__feedback">
    <ViewingReviewSummary summary={summary} title={property.title} showEmpty
      reviewLimit={expanded && full ? full.reviews.length : 3} showUnwritten={expanded && Boolean(full)} />
    {expanded && !full && !error && <p role="status">Loading all property reviews…</p>}
    {expanded && error && !full && <div role="alert" className="landlord-reviews__error">
      <p>Could not load all property reviews.</p>
      <button type="button" className="shared-button shared-button--outline" onClick={() => { setError(false); setAttempt((value) => value + 1) }}>Try again</button>
    </div>}
    {(property.reviewCount > 3 || property.recentReviews.length > 3) && <button type="button"
      className="shared-button shared-button--outline landlord-reviews__expand" aria-expanded={expanded}
      onClick={() => { setError(false); setExpanded((value) => !value) }}>{expanded ? 'Show less' : 'View all reviews'}</button>}
  </div>
}

export default function LandlordReviewsPage() {
  const [state, setState] = useState({ loading: true, data: null, error: false })
  const [retry, setRetry] = useState(0)
  const [selectedId, setSelectedId] = useState(null)
  useEffect(() => {
    let active = true
    apiRequest('/api/landlord/viewing-reviews/summary', { cache: 'no-store', errorMessage: 'Could not load viewing feedback.' }).then((data) => {
      if (!validViewingSummary(data?.landlord) || !Array.isArray(data.properties)
        || data.properties.some((property) => typeof property.propertyId !== 'string' || !property.propertyId.trim() || typeof property.title !== 'string' || !validViewingSummary({ ...property, reviews: property.recentReviews }))
        || new Set(data.properties.map((property) => property.propertyId)).size !== data.properties.length) throw new Error('Invalid feedback')
      if (active) setState({ loading: false, data, error: false })
    }).catch(() => { if (active) setState({ loading: false, data: null, error: true }) })
    return () => { active = false }
  }, [retry])
  const selected = state.data?.properties.find((property) => property.propertyId === selectedId) || state.data?.properties[0]
  return <main className="shared-page landlord-reviews-page">
    <PageHeader eyebrow="LANDLORD" title="Reviews" />
    {state.loading && <p role="status">Loading viewing feedback…</p>}
    {state.error && <div role="alert"><p>Could not load viewing feedback.</p><button type="button" onClick={() => { setState({ loading: true, data: null, error: false }); setRetry((value) => value + 1) }}>Try again</button></div>}
    {state.data && <>
      <ViewingReviewSummary summary={state.data.landlord} title="Your landlord experience" showEmpty />
      <section aria-label="Property feedback" className="landlord-reviews__properties">
        <h2>Property feedback</h2>
        {state.data.properties.length === 0 ? <p className="landlord-reviews__empty">Your owned properties will appear here.</p> : <>
          <p className="landlord-reviews__intro">Select a property to see its verified viewing feedback.</p>
          <div className="landlord-reviews__selector" role="group" aria-label="Select a property">
            {state.data.properties.map((property) => <button key={property.propertyId} type="button"
              className="landlord-reviews__property" aria-pressed={selected.propertyId === property.propertyId}
              onClick={() => setSelectedId(property.propertyId)}>
              <span className="landlord-reviews__property-name">{property.title}</span>
              {property.reviewCount > 0 ? <CompactViewingRating summary={property} /> : <span className="landlord-reviews__property-empty">No verified reviews yet</span>}
              <span className="landlord-reviews__selected">{selected.propertyId === property.propertyId ? 'Selected' : 'View feedback'}</span>
            </button>)}
          </div>
          <PropertyFeedback key={selected.propertyId} property={selected} />
        </>}
      </section>
    </>}
  </main>
}
