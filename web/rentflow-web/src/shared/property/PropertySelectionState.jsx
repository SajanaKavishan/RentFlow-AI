import { Link } from 'react-router-dom'
import { useOwnedProperties } from './useOwnedProperties.js'
import './property-selection.css'

function destinationPath(destination, propertyId) {
  if (destination === 'dashboard') {
    return `/dashboard?${new URLSearchParams({ propertyId })}`
  }
  return `/properties/${encodeURIComponent(propertyId)}/${destination}`
}

export default function PropertySelectionState({ className, destination = 'dashboard', selectedPropertyId = null }) {
  const collection = useOwnedProperties()

  if (collection?.status === 'loading') {
    return <section className={className} role="status">
      <h2>Loading your properties</h2>
      <p>Please wait while we load your authenticated property portfolio.</p>
    </section>
  }

  if (collection?.status === 'error') {
    return <section className={className} role="alert">
      <h2>We could not load your properties</h2>
      <p>{collection.error}</p>
      <button type="button" className="property-selection__button" onClick={collection.retry}>Try again</button>
    </section>
  }

  if (collection?.status === 'ready' && collection.properties.length === 0) {
    return <section className={className} role="status">
      <h2>No owned properties</h2>
      <p>Add a property before opening landlord viewing and application workflows.</p>
      <Link className="property-selection__button" to="/modules/manage-properties">Manage properties</Link>
    </section>
  }

  const properties = collection?.status === 'ready' ? collection.properties : []
  return (
    <section className={className} role="status">
      <h2>{selectedPropertyId ? 'Property unavailable' : 'Select a property'}</h2>
      <p>
        {selectedPropertyId
          ? 'This property is not in your authenticated property portfolio. Choose one of your owned properties instead.'
          : 'Choose one of your owned properties to open this workspace.'}
      </p>
      {properties.length > 0 && <div className="property-selection__list">
        {properties.map((property) => <Link key={property.id} to={destinationPath(destination, property.id)}>
          <strong>{property.title}</strong>
          <span>{[property.address, property.city].filter(Boolean).join(', ')}</span>
        </Link>)}
      </div>}
      {!collection && <Link className="property-selection__button" to="/modules/manage-properties">Open Manage Properties</Link>}
    </section>
  )
}
