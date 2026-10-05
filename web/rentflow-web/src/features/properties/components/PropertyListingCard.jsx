import { Link } from 'react-router-dom'
import Icon from '../../../shared/ui/Icons.jsx'
import PropertyImageCarousel from './PropertyImageCarousel.jsx'

const money = new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 })

export default function PropertyListingCard({ property, images, match, liked, favoritePending, onToggleFavorite, children }) {
  return <article className="property-card">
    <PropertyImageCarousel property={property} images={images} match={match} liked={liked}
      favoritePending={favoritePending} onToggleFavorite={onToggleFavorite} />
    <div className="property-card__body">
      <div className="property-card__summary">
        <div>
          <h2><Link to={`/properties/${encodeURIComponent(property.id)}`}>{property.title}</Link></h2>
          <p className="property-card__location"><Icon name="location" size={14} />{property.city}</p>
        </div>
        <div className="property-card__price"><strong>Rs. {money.format(Number(property.monthlyRent))}</strong><span>/month</span></div>
      </div>
      <div className="property-card__features">
        <span><Icon name="bed" size={16} />{property.bedrooms} {property.bedrooms === 1 ? 'bed' : 'beds'}</span>
        <span><Icon name="bath" size={16} />{property.bathrooms} {property.bathrooms === 1 ? 'bath' : 'baths'}</span>
        {property.area != null && <span className="property-card__area">{money.format(Number(property.area))} {property.areaUnit || ''}</span>}
      </div>
      {children}
    </div>
  </article>
}
