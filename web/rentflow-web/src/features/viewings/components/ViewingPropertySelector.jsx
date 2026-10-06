import { useNavigate } from 'react-router-dom'
import PropertySelectionState from '../../../shared/property/PropertySelectionState.jsx'
import { useOwnedProperties } from '../../../shared/property/useOwnedProperties.js'
import LandlordWorkspacePropertyCard, { LandlordWorkspacePropertyLoadingState } from '../../../shared/property/LandlordWorkspacePropertyCard.jsx'
import usePropertyCountSummary from '../../../shared/property/usePropertyCountSummary.js'
import { getOwnedPropertyPendingViewingCounts } from '../services/viewingApiService.js'
import './viewing-property-selector.css'

function PropertyCards({ properties, selectedPropertyId }) {
  const navigate = useNavigate()
  const counts = usePropertyCountSummary(getOwnedPropertyPendingViewingCounts, 'pendingCount')

  return <section className="workspace-property-selector" aria-labelledby="workspace-property-selector-title">
    <h2 id="workspace-property-selector-title">{selectedPropertyId ? 'Property unavailable' : 'Select a property'}</h2>
    <p>{selectedPropertyId
      ? 'This property is not in your authenticated property portfolio. Choose one of your owned properties instead.'
      : 'Choose one of your owned properties to review its viewing requests.'}</p>
    {counts.status === 'loading' && <p className="workspace-property-selector__notice" role="status">Loading pending request counts…</p>}
    {counts.status === 'error' && <div className="workspace-property-selector__notice" role="status">
      <span>Pending request counts are unavailable. You can still open a property.</span>
      <button type="button" className="button button--quiet" onClick={counts.retry}>Retry counts</button>
    </div>}
    <div className="workspace-property-selector__grid">
      {properties.map((property) => {
        const count = counts.status === 'ready' ? counts.values.get(property.id.toLowerCase()) ?? 0 : null
        const metadata = count === null ? 'Pending request count unavailable'
          : count === 0 ? 'No pending viewing requests'
            : `${count} viewing ${count === 1 ? 'request needs' : 'requests need'} your attention`
        return <LandlordWorkspacePropertyCard key={property.id} property={property}
          accessibleLabel={`${property.title}, ${count === null ? 'pending viewing count unavailable' : `${count} pending viewing ${count === 1 ? 'request' : 'requests'}`}`}
          badge={count > 0 ? `${count} pending` : null}
          metadata={counts.status === 'loading' ? 'Loading pending request count…' : metadata}
          onSelect={(id) => navigate(`/properties/${encodeURIComponent(id)}/viewing-requests`)} />
      })}
    </div>
  </section>
}

export default function ViewingPropertySelector({ selectedPropertyId = null }) {
  const collection = useOwnedProperties()
  if (collection?.status === 'loading') return <LandlordWorkspacePropertyLoadingState className="page-state" />
  if (collection?.status !== 'ready' || !collection.properties.length) {
    return <PropertySelectionState className="page-state" destination="viewing-requests" selectedPropertyId={selectedPropertyId} />
  }
  return <PropertyCards properties={collection.properties} selectedPropertyId={selectedPropertyId} />
}
