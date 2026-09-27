import Icon from '../../../shared/ui/Icons.jsx'
import {
  getGoogleMapsEmbedUrl,
  getGoogleMapsSearchUrl,
  getPropertyLocation,
} from '../propertyMap.js'

export default function PropertyLocationMap({ address, city }) {
  const location = getPropertyLocation(address, city)
  const embedUrl = getGoogleMapsEmbedUrl(
    import.meta.env.VITE_GOOGLE_MAPS_API_KEY,
    location,
  )
  const mapsUrl = getGoogleMapsSearchUrl(location)

  return (
    <section className="property-details-section property-location" aria-labelledby="property-location-title">
      <div className="property-location__heading">
        <div>
          <span className="property-section-number">Neighbourhood</span>
          <h2 id="property-location-title">Location</h2>
          <p className="property-location__address">
            <Icon name="pin" size={17} />
            <span>{location || 'No property address is available.'}</span>
          </p>
        </div>

        {mapsUrl && (
          <a href={mapsUrl} target="_blank" rel="noreferrer">
            Open in Google Maps <span aria-hidden="true">↗</span>
          </a>
        )}
      </div>

      {embedUrl ? (
        <div className="property-location__map">
          <iframe
            title={`Map showing ${location}`}
            src={embedUrl}
            loading="lazy"
            referrerPolicy="no-referrer-when-downgrade"
            allowFullScreen
          />
        </div>
      ) : (
        <div className="property-location__unavailable" role="status">
          <Icon name="pin" size={20} />
          <div>
            <strong>Map preview unavailable</strong>
            <span>
              {location
                ? 'The property address is shown above.'
                : 'This property does not include a usable address.'}
            </span>
          </div>
        </div>
      )}
    </section>
  )
}
