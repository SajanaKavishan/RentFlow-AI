import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import PropertySelectionState from '../../../shared/property/PropertySelectionState.jsx'
import { useOwnedProperties } from '../../../shared/property/useOwnedProperties.js'
import Icon from '../../../shared/ui/Icons.jsx'
import { getPropertyImages, getPropertyImageUrl } from '../../properties/services/propertyApiService.js'
import { getOwnedPropertyPendingViewingCounts } from '../services/viewingApiService.js'
import './viewing-property-selector.css'

function PropertyThumbnail({ property }) {
  const [photo, setPhoto] = useState(null)
  useEffect(() => {
    let active = true
    getPropertyImages(property.id).then(async (images) => {
      const first = images.find((image) => image.isPrimary) ?? images[0]
      if (!first) return
      const result = await getPropertyImageUrl(property.id, first.id)
      if (active && typeof result?.url === 'string' && result.url) setPhoto(result.url)
    }).catch(() => {})
    return () => { active = false }
  }, [property.id])

  return <span className="viewing-property-card__thumbnail">
    {photo
      ? <img src={photo} alt={`${property.title} — property photo`} loading="lazy" onError={() => setPhoto(null)} />
      : <span className="viewing-property-card__fallback" aria-hidden="true"><Icon name="building" size={32} /></span>}
  </span>
}

function propertyCounts(rows) {
  if (!Array.isArray(rows) || rows.some((row) => !row
    || typeof row.propertyId !== 'string' || !row.propertyId.trim()
    || !Number.isSafeInteger(row.pendingCount) || row.pendingCount < 0)
    || new Set(rows.map((row) => row.propertyId.toLowerCase())).size !== rows.length) {
    throw new TypeError('Invalid viewing count summary')
  }
  return new Map(rows.map((row) => [row.propertyId.toLowerCase(), row.pendingCount]))
}

function PropertyCards({ properties, selectedPropertyId }) {
  const navigate = useNavigate()
  const [attempt, setAttempt] = useState(0)
  const [result, setResult] = useState(null)
  const counts = result?.attempt === attempt ? result : { status: 'loading' }
  useEffect(() => {
    let active = true
    getOwnedPropertyPendingViewingCounts().then((rows) => {
      const values = propertyCounts(rows)
      if (active) setResult({ attempt, status: 'ready', values })
    }).catch(() => {
      if (active) setResult({ attempt, status: 'error' })
    })
    return () => { active = false }
  }, [attempt])

  return <section className="viewing-property-selector" aria-labelledby="viewing-property-selector-title">
    <h2 id="viewing-property-selector-title">{selectedPropertyId ? 'Property unavailable' : 'Select a property'}</h2>
    <p>{selectedPropertyId
      ? 'This property is not in your authenticated property portfolio. Choose one of your owned properties instead.'
      : 'Choose one of your owned properties to review its viewing requests.'}</p>
    {counts.status === 'loading' && <p className="viewing-property-selector__notice" role="status">Loading pending request counts…</p>}
    {counts.status === 'error' && <div className="viewing-property-selector__notice" role="status">
      <span>Pending request counts are unavailable. You can still open a property.</span>
      <button type="button" className="button button--quiet" onClick={() => setAttempt((value) => value + 1)}>Retry counts</button>
    </div>}
    <div className="viewing-property-selector__grid">
      {properties.map((property) => {
        const count = counts.status === 'ready' ? counts.values.get(property.id.toLowerCase()) ?? 0 : null
        const metadata = count === null ? 'Pending request count unavailable'
          : count === 0 ? 'No pending viewing requests'
            : `${count} viewing ${count === 1 ? 'request needs' : 'requests need'} your attention`
        return <button type="button" key={property.id} className="viewing-property-card"
          aria-label={`${property.title}, ${count === null ? 'pending viewing count unavailable' : `${count} pending viewing ${count === 1 ? 'request' : 'requests'}`}`}
          onClick={() => navigate(`/properties/${encodeURIComponent(property.id)}/viewing-requests`)}>
          <PropertyThumbnail property={property} />
          <span className="viewing-property-card__body">
            <span className="viewing-property-card__heading"><strong>{property.title}</strong>
              {count > 0 && <span className="viewing-property-card__badge">{count} pending</span>}
            </span>
            <span className="viewing-property-card__address">{[property.address, property.city].filter(Boolean).join(', ')}</span>
            <span className="viewing-property-card__metadata">{counts.status === 'loading' ? 'Loading pending request count…' : metadata}</span>
          </span>
          <span className="viewing-property-card__arrow" aria-hidden="true"><Icon name="arrow" size={17} /></span>
        </button>
      })}
    </div>
  </section>
}

export default function ViewingPropertySelector({ selectedPropertyId = null }) {
  const collection = useOwnedProperties()
  if (collection?.status !== 'ready' || !collection.properties.length) {
    return <PropertySelectionState className="page-state" destination="viewing-requests" selectedPropertyId={selectedPropertyId} />
  }
  return <PropertyCards properties={collection.properties} selectedPropertyId={selectedPropertyId} />
}
