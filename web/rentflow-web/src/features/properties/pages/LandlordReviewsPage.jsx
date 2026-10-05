import { useEffect, useState } from 'react'
import { apiRequest } from '../../../core/api/apiClient.js'
import { PageHeader } from '../../../shared/ui/States.jsx'
import { validViewingSummary } from '../useViewingReviews.js'
import { ViewingReviewSummary } from '../components/ViewingReviews.jsx'

export default function LandlordReviewsPage() {
  const [state, setState] = useState({ loading: true, data: null, error: false })
  const [retry, setRetry] = useState(0)
  useEffect(() => {
    let active = true
    apiRequest('/api/landlord/viewing-reviews/summary', { cache: 'no-store', errorMessage: 'Could not load viewing feedback.' }).then((data) => {
      if (!validViewingSummary(data?.landlord) || !Array.isArray(data.properties)
        || data.properties.some((property) => typeof property.propertyId !== 'string' || typeof property.title !== 'string' || !validViewingSummary({ ...property, reviews: property.recentReviews }))) throw new Error('Invalid feedback')
      if (active) setState({ loading: false, data, error: false })
    }).catch(() => { if (active) setState({ loading: false, data: null, error: true }) })
    return () => { active = false }
  }, [retry])
  const empty = state.data && state.data.landlord.reviewCount === 0 && state.data.properties.every((p) => p.reviewCount === 0)
  return <main className="shared-page">
    <PageHeader eyebrow="LANDLORD" title="Reviews" />
    {state.loading && <p role="status">Loading viewing feedback…</p>}
    {state.error && <div role="alert"><p>Could not load viewing feedback.</p><button type="button" onClick={() => { setState({ loading: true, data: null, error: false }); setRetry((value) => value + 1) }}>Try again</button></div>}
    {empty && <section><h2>No viewing feedback yet</h2><p>Verified feedback will appear here after tenants complete viewings and leave a review.</p></section>}
    {state.data && <>
      {!empty && <ViewingReviewSummary summary={state.data.landlord} title="Your landlord experience" showEmpty />}
      {state.data.properties.length > 0 && <section aria-label="Property feedback"><h2>Property feedback</h2>
        {state.data.properties.map((property) => <ViewingReviewSummary key={property.propertyId} title={property.title} summary={{ ...property, reviews: property.recentReviews }} showEmpty />)}
      </section>}
    </>}
  </main>
}
