import { useEffect, useState } from 'react'
import Icon from '../ui/Icons.jsx'
import { getPropertyImages, getPropertyImageUrl } from '../../features/properties/services/propertyApiService.js'
import './landlord-workspace-property-selector.css'

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

  return <span className="workspace-property-card__thumbnail">
    {photo
      ? <img src={photo} alt={`${property.title} — property photo`} loading="lazy" onError={() => setPhoto(null)} />
      : <span className="workspace-property-card__fallback" aria-hidden="true"><Icon name="building" size={32} /></span>}
  </span>
}

export default function LandlordWorkspacePropertyCard({ property, badge, metadata, accessibleLabel, onSelect }) {
  return <button type="button" className="workspace-property-card" aria-label={accessibleLabel} onClick={() => onSelect(property.id)}>
    <PropertyThumbnail property={property} />
    <span className="workspace-property-card__body">
      <span className="workspace-property-card__heading"><strong>{property.title}</strong>
        {badge && <span className="workspace-property-card__badge">{badge}</span>}
      </span>
      <span className="workspace-property-card__address">{[property.address, property.city].filter(Boolean).join(', ')}</span>
      <span className="workspace-property-card__metadata">{metadata}</span>
    </span>
    <span className="workspace-property-card__arrow" aria-hidden="true"><Icon name="arrow" size={17} /></span>
  </button>
}

export function LandlordWorkspacePropertyLoadingState({ className }) {
  return <section className={className} role="status">
    <h2>Loading your properties</h2>
    <p>Please wait while we load your authenticated property portfolio.</p>
    <div className="workspace-property-selector__grid" aria-hidden="true">
      {[0, 1].map((key) => <div className="workspace-property-skeleton" key={key}>
        <span className="workspace-property-skeleton__image" />
        <span className="workspace-property-skeleton__body"><span /><span /><span /></span>
      </div>)}
    </div>
  </section>
}
