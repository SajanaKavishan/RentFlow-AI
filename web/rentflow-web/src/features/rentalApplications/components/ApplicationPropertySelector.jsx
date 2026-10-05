import { useNavigate } from 'react-router-dom'
import PropertySelectionState from '../../../shared/property/PropertySelectionState.jsx'
import { useOwnedProperties } from '../../../shared/property/useOwnedProperties.js'
import LandlordWorkspacePropertyCard, { LandlordWorkspacePropertyLoadingState } from '../../../shared/property/LandlordWorkspacePropertyCard.jsx'
import usePropertyCountSummary from '../../../shared/property/usePropertyCountSummary.js'
import { getOwnedPropertyApplicationActionCounts } from '../services/rentalApplicationApiService.js'

function PropertyCards({ properties, selectedPropertyId, refreshKey }) {
  const navigate = useNavigate()
  const counts = usePropertyCountSummary(getOwnedPropertyApplicationActionCounts, 'actionRequiredCount', refreshKey)

  return <section className="workspace-property-selector" aria-labelledby="application-property-selector-title">
    <h2 id="application-property-selector-title">{selectedPropertyId ? 'Property unavailable' : 'Select a property'}</h2>
    <p>{selectedPropertyId
      ? 'This property is not in your authenticated property portfolio. Choose one of your owned properties instead.'
      : 'Choose one of your owned properties to review its rental applications.'}</p>
    {counts.status === 'loading' && <p className="workspace-property-selector__notice" role="status">Loading application review counts…</p>}
    {counts.status === 'error' && <div className="workspace-property-selector__notice" role="status">
      <span>Application review counts are unavailable. You can still open a property.</span>
      <button type="button" className="button button--quiet" onClick={counts.retry}>Retry counts</button>
    </div>}
    <div className="workspace-property-selector__grid">
      {properties.map((property) => {
        const count = counts.status === 'ready' ? counts.values.get(property.id.toLowerCase()) ?? 0 : null
        const metadata = count === null ? 'Application review count unavailable'
          : count === 0 ? 'No applications need your attention'
            : `${count} ${count === 1 ? 'application needs' : 'applications need'} your attention`
        return <LandlordWorkspacePropertyCard key={property.id} property={property}
          accessibleLabel={`${property.title}, ${count === null ? 'rental application review count unavailable' : `${count} rental ${count === 1 ? 'application needs' : 'applications need'} attention`}`}
          badge={count > 0 ? `${count} to review` : null}
          metadata={counts.status === 'loading' ? 'Loading application review count…' : metadata}
          onSelect={(id) => navigate(`/properties/${encodeURIComponent(id)}/rental-applications`)} />
      })}
    </div>
  </section>
}

export default function ApplicationPropertySelector({ selectedPropertyId = null, refreshKey = 0 }) {
  const collection = useOwnedProperties()
  if (collection?.status === 'loading') return <LandlordWorkspacePropertyLoadingState className="applications-state" />
  if (collection?.status !== 'ready' || !collection.properties.length) {
    return <PropertySelectionState className="applications-state" destination="rental-applications" selectedPropertyId={selectedPropertyId} />
  }
  return <PropertyCards properties={collection.properties} selectedPropertyId={selectedPropertyId} refreshKey={refreshKey} />
}
