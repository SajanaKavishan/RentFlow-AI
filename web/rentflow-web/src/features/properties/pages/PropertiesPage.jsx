import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import Icon from '../../../shared/ui/Icons.jsx'
import MatchPreferenceSummary from '../components/MatchPreferenceSummary.jsx'
import MatchPreferencesDialog from '../components/MatchPreferencesDialog.jsx'
import {
  getMatchPreferences,
  getProperties,
  getPropertyImages,
  getPropertyImageUrl,
  getSavedPropertyMatches,
  resetMatchPreferences,
  saveMatchPreferences,
} from '../services/propertyApiService.js'
import '../properties.css'

const initialFilters = { search: '', city: '', maxRent: '', minBedrooms: '', minBathrooms: '', amenity: '' }
const money = new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 })
const isPositiveReason = (reason) => !/^(above|does not|matches 0\b)/i.test(reason)

export default function PropertiesPage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const [properties, setProperties] = useState([])
  const [coverImages, setCoverImages] = useState({})
  const [propertyState, setPropertyState] = useState({ status: 'loading', message: '' })
  const [preferenceState, setPreferenceState] = useState({ status: 'loading', data: null, message: '' })
  const [matchState, setMatchState] = useState({ status: 'idle', data: null, message: '' })
  const [filters, setFilters] = useState(initialFilters)
  const [sortBy, setSortBy] = useState('newest')
  const [editingPreferences, setEditingPreferences] = useState(searchParams.get('preferences') === 'edit')
  const [expandedReasons, setExpandedReasons] = useState(() => new Set())
  const editButtonRef = useRef(null)

  const loadMatches = useCallback(async () => {
    setMatchState({ status: 'loading', data: null, message: '' })
    try {
      const result = await getSavedPropertyMatches()
      setMatchState({ status: 'ready', data: result, message: '' })
    } catch (error) {
      setMatchState({ status: 'error', data: null, message: error.message || "We couldn't calculate your matches." })
    }
  }, [])

  const loadPreferences = useCallback(async () => {
    setPreferenceState({ status: 'loading', data: null, message: '' })
    try {
      const result = await getMatchPreferences()
      setPreferenceState({ status: 'ready', data: result, message: '' })
      if (result.isConfigured) {
        setSortBy('bestMatch')
        await loadMatches()
      } else {
        setSortBy('newest')
        setMatchState({ status: 'idle', data: null, message: '' })
      }
    } catch (error) {
      setPreferenceState({ status: 'error', data: null, message: error.message || "We couldn't load your match preferences." })
    }
  }, [loadMatches])

  useEffect(() => {
    let active = true
    async function loadProperties() {
      setPropertyState({ status: 'loading', message: '' })
      try {
        const result = await getProperties({ isAvailable: true })
        if (!active) return
        const available = Array.isArray(result) ? result : []
        setProperties(available)
        setPropertyState({ status: 'ready', message: '' })
        const imageEntries = await Promise.all(available.map(async (property) => {
          try {
            const images = await getPropertyImages(property.id)
            if (!images?.length) return [property.id, null]
            const image = await getPropertyImageUrl(property.id, images[0].id)
            return [property.id, image?.url || null]
          } catch {
            return [property.id, null]
          }
        }))
        if (active) setCoverImages(Object.fromEntries(imageEntries.filter(([, url]) => url)))
      } catch (error) {
        if (active) setPropertyState({ status: 'error', message: error.message || 'Unable to load properties.' })
      }
    }
    loadProperties()
    Promise.resolve().then(loadPreferences)
    return () => { active = false }
  }, [loadPreferences])

  const openPreferences = () => {
    setEditingPreferences(true)
    setSearchParams({ preferences: 'edit' }, { replace: true })
  }
  const closePreferences = () => {
    setEditingPreferences(false)
    setSearchParams({}, { replace: true })
    window.requestAnimationFrame(() => editButtonRef.current?.focus())
  }
  const savePreferences = async (request) => {
    const saved = await saveMatchPreferences(request)
    setPreferenceState({ status: 'ready', data: saved, message: '' })
    setSortBy('bestMatch')
    await loadMatches()
    closePreferences()
  }
  const resetPreferences = async () => {
    await resetMatchPreferences()
    setPreferenceState({ status: 'ready', data: { isConfigured: false, preferredAmenities: [] }, message: '' })
    setMatchState({ status: 'idle', data: null, message: '' })
    setSortBy('newest')
    closePreferences()
  }

  const matchByPropertyId = useMemo(() => new Map(
    (matchState.data?.matches || []).map((match) => [match.propertyId, match]),
  ), [matchState.data])
  const hasPreferences = preferenceState.status === 'ready' && preferenceState.data?.isConfigured
  const visibleProperties = useMemo(() => {
    const search = filters.search.trim().toLowerCase()
    const city = filters.city.trim().toLowerCase()
    const amenity = filters.amenity.trim().toLowerCase()
    const filtered = properties.filter((property) => {
      const amenities = property.amenities || []
      return property.isAvailable !== false
        && (!search || [property.title, property.description, property.address, property.city].some((value) => String(value || '').toLowerCase().includes(search)))
        && (!city || String(property.city || '').toLowerCase().includes(city))
        && (!filters.maxRent || Number(property.monthlyRent) <= Number(filters.maxRent))
        && (!filters.minBedrooms || Number(property.bedrooms) >= Number(filters.minBedrooms))
        && (!filters.minBathrooms || Number(property.bathrooms) >= Number(filters.minBathrooms))
        && (!amenity || amenities.some((item) => String(item).toLowerCase().includes(amenity)))
    })
    return [...filtered].sort((a, b) => {
      if (sortBy === 'bestMatch') return (matchByPropertyId.get(b.id)?.matchScore ?? -1) - (matchByPropertyId.get(a.id)?.matchScore ?? -1) || Number(a.monthlyRent) - Number(b.monthlyRent)
      if (sortBy === 'lowestRent') return Number(a.monthlyRent) - Number(b.monthlyRent)
      if (sortBy === 'highestRent') return Number(b.monthlyRent) - Number(a.monthlyRent)
      return Date.parse(b.createdAt || 0) - Date.parse(a.createdAt || 0)
    })
  }, [filters, matchByPropertyId, properties, sortBy])

  const hasFilters = Object.values(filters).some(Boolean)
  const updateFilter = (event) => {
    const { name, value } = event.target
    setFilters((current) => ({ ...current, [name]: value }))
  }
  const toggleReasons = (propertyId) => {
    setExpandedReasons((current) => {
      const next = new Set(current)
      if (next.has(propertyId)) next.delete(propertyId)
      else next.add(propertyId)
      return next
    })
  }

  return <main className="properties-page" aria-busy={propertyState.status === 'loading' || preferenceState.status === 'loading'}>
    <header className="properties-page__header">
      <div><span className="properties-page__eyebrow">Property marketplace</span><h1>Find a home that fits</h1><p className="properties-page__description">Browse real available rentals and use your saved preferences to see the strongest matches first.</p>{propertyState.status === 'ready' && <p className="properties-page__count">{visibleProperties.length} {visibleProperties.length === 1 ? 'property' : 'properties'} available</p>}</div>
      <button ref={editButtonRef} type="button" className="property-button property-button--primary properties-page__match-action" onClick={openPreferences}><Icon name="sparkles" size={18} />{hasPreferences ? 'Edit Match Preferences' : 'Set Match Preferences'}</button>
    </header>

    {preferenceState.status === 'loading' && <section className="match-preference-loading" role="status"><span className="property-spinner" aria-hidden="true" />Loading your match preferences…</section>}
    {preferenceState.status === 'error' && <section className="match-preference-error" role="alert"><div><strong>We couldn't load your match preferences.</strong><p>{preferenceState.message}</p></div><button type="button" className="property-button property-button--outline" onClick={loadPreferences}>Retry</button></section>}
    {preferenceState.status === 'ready' && !hasPreferences && <section className="match-onboarding" aria-labelledby="match-onboarding-title"><span className="match-onboarding__icon"><Icon name="sparkles" size={25} /></span><div><h2 id="match-onboarding-title">Get personalized matches</h2><p>Tell us what you're looking for and RentFlow AI will rank suitable properties for you.</p></div><button type="button" className="property-button property-button--primary" onClick={openPreferences}>Set match preferences</button></section>}
    {hasPreferences && <MatchPreferenceSummary preferences={preferenceState.data} onEdit={openPreferences} />}
    {hasPreferences && matchState.status === 'loading' && <div className="match-inline-state" role="status"><span className="property-spinner" aria-hidden="true" />Finding properties that match your preferences…</div>}
    {hasPreferences && matchState.status === 'error' && <section className="match-preference-error" role="alert"><div><strong>We couldn't calculate your matches.</strong><p>{matchState.message}</p></div><button type="button" className="property-button property-button--outline" onClick={loadMatches}>Retry</button></section>}

    <section className="property-filters" aria-label="Property filters">
      <div className="property-filters__top"><div className="property-filters__search"><Icon name="search" size={19} /><input type="search" name="search" value={filters.search} onChange={updateFilter} placeholder="Search properties, addresses or locations" aria-label="Search properties" /></div><label className="property-sort"><span>Sort by</span><select aria-label="Sort properties" value={sortBy} onChange={(event) => setSortBy(event.target.value)}>{hasPreferences && <option value="bestMatch">Best Match</option>}<option value="lowestRent">Lowest Rent</option><option value="highestRent">Highest Rent</option><option value="newest">Newest</option></select></label></div>
      <div className="property-filters__grid">
        <label><span>City</span><input name="city" value={filters.city} onChange={updateFilter} placeholder="Any city" /></label>
        <label><span>Maximum rent</span><input type="number" min="0" name="maxRent" value={filters.maxRent} onChange={updateFilter} placeholder="Any price" /></label>
        <label><span>Bedrooms</span><select name="minBedrooms" value={filters.minBedrooms} onChange={updateFilter}><option value="">Any</option><option value="1">1+</option><option value="2">2+</option><option value="3">3+</option><option value="4">4+</option></select></label>
        <label><span>Bathrooms</span><select name="minBathrooms" value={filters.minBathrooms} onChange={updateFilter}><option value="">Any</option><option value="1">1+</option><option value="2">2+</option><option value="3">3+</option></select></label>
        <label><span>Amenity</span><input name="amenity" value={filters.amenity} onChange={updateFilter} placeholder="Parking, Security…" /></label>
      </div>
      {hasFilters && <button type="button" className="property-button property-button--quiet" onClick={() => setFilters(initialFilters)}>Clear filters</button>}
    </section>

    {propertyState.status === 'loading' && <section className="property-state"><div className="property-spinner" /><h2>Loading properties</h2><p>Finding the latest available rental properties.</p></section>}
    {propertyState.status === 'error' && <section className="property-state property-state--error" role="alert"><h2>We couldn't load the properties</h2><p>{propertyState.message}</p></section>}
    {propertyState.status === 'ready' && visibleProperties.length === 0 && <section className="property-state"><h2>{hasPreferences ? 'No available properties match your current preferences.' : 'No matching properties'}</h2><p>{hasFilters ? 'Try changing your filters.' : 'Check back as new available properties are listed.'}</p><div className="property-state__actions">{hasFilters && <button type="button" className="property-button property-button--outline" onClick={() => setFilters(initialFilters)}>Clear filters</button>}{hasPreferences && <button type="button" className="property-button property-button--primary" onClick={openPreferences}>Adjust preferences</button>}</div></section>}
    {propertyState.status === 'ready' && visibleProperties.length > 0 && <section className="property-grid" aria-label="Available properties">{visibleProperties.map((property) => {
      const match = hasPreferences && matchState.status === 'ready' ? matchByPropertyId.get(property.id) : null
      const reasonsOpen = expandedReasons.has(property.id)
      return <article className="property-card" key={property.id}>
        <Link className="property-card__image" to={`/properties/${property.id}`} aria-label={`View ${property.title}`}>
          {coverImages[property.id] ? <img src={coverImages[property.id]} alt="" /> : <div className="property-card__placeholder"><Icon name="home" size={34} /><span>No property photo</span></div>}
          <span className="property-card__status">Available</span>
          {match && <span className="property-card__match" aria-label={`${match.matchScore} percent match`}>{match.matchScore}% Match</span>}
        </Link>
        <div className="property-card__body">
          <div className="property-card__location"><Icon name="location" size={16} />{property.city}</div>
          <h2>{property.title}</h2><p className="property-card__address">{property.address}</p>
          <div className="property-card__features"><span><strong>{property.bedrooms}</strong> Bedrooms</span><span><strong>{property.bathrooms}</strong> Bathrooms</span></div>
          {property.amenities?.length > 0 && <div className="property-card__amenities">{property.amenities.slice(0, 3).map((amenity) => <span key={amenity}>{amenity}</span>)}{property.amenities.length > 3 && <span>+{property.amenities.length - 3}</span>}</div>}
          {match?.matchReasons?.length > 0 && <div className="property-card__reasons"><button type="button" aria-expanded={reasonsOpen} onClick={() => toggleReasons(property.id)}>Why this matches <span aria-hidden="true">{reasonsOpen ? '−' : '+'}</span></button>{reasonsOpen && <ul>{match.matchReasons.map((reason) => <li key={reason}><span className={isPositiveReason(reason) ? 'is-positive' : 'is-neutral'} aria-hidden="true">{isPositiveReason(reason) ? '✓' : '•'}</span>{reason}</li>)}</ul>}</div>}
          <div className="property-card__footer"><div className="property-card__price"><strong>Rs. {money.format(Number(property.monthlyRent))}</strong><span>/ month</span></div><Link to={`/properties/${property.id}`} className="property-button property-button--primary">View Property</Link></div>
        </div>
      </article>
    })}</section>}

    {editingPreferences && <MatchPreferencesDialog preferences={preferenceState.data} onClose={closePreferences} onSave={savePreferences} onReset={resetPreferences} />}
  </main>
}
