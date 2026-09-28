const numberFormatter = new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 })

export default function MatchPreferenceSummary({ preferences, onEdit, compact = false }) {
  const items = [
    preferences.preferredCity,
    preferences.maximumMonthlyRent != null ? `Up to Rs. ${numberFormatter.format(preferences.maximumMonthlyRent)}` : null,
    preferences.minimumBedrooms != null ? `${preferences.minimumBedrooms}+ bedrooms` : null,
    preferences.minimumBathrooms != null ? `${preferences.minimumBathrooms}+ bathrooms` : null,
    preferences.preferredAmenities?.length ? preferences.preferredAmenities.join(', ') : null,
  ].filter(Boolean)

  return <section className={`match-preference-summary${compact ? ' match-preference-summary--compact' : ''}`} aria-label="Your match preferences">
    <div><span className="match-preference-summary__eyebrow">Your match preferences</span><div className="match-preference-summary__items">{items.map((item) => <span key={item}>{item}</span>)}</div></div>
    {onEdit && <button type="button" className="property-button property-button--outline" onClick={onEdit}>Edit preferences</button>}
  </section>
}
