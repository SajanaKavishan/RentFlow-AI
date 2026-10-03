import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import Icon from '../../../shared/ui/Icons.jsx'
import MatchPreferenceSummary from '../components/MatchPreferenceSummary.jsx'
import MatchPreferencesDialog from '../components/MatchPreferencesDialog.jsx'
import PropertyListingCard from '../components/PropertyListingCard.jsx'
import {
  addPropertyFavorite,
  getMatchPreferences,
  getProperties,
  getPropertyFavorites,
  getPropertyImages,
  getPropertyImageUrl,
  getSavedPropertyMatches,
  removePropertyFavorite,
  resetMatchPreferences,
  saveMatchPreferences,
} from '../services/propertyApiService.js'
import '../properties.css'

const initialFilters = { search: '', city: '', maxRent: '', minBedrooms: '', minBathrooms: '', amenity: '' }
const isPositiveReason = (reason) => !/^(above|does not|matches 0\b)/i.test(reason)

export default function PropertiesPage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const [properties, setProperties] = useState([])
  const [propertyImages, setPropertyImages] = useState({})
  const [favoriteState, setFavoriteState] = useState({ status: 'loading', propertyIds: [], message: '' })
  const [favoritePending, setFavoritePending] = useState(() => new Set())
  const [propertyState, setPropertyState] = useState({ status: 'loading', message: '' })
  const [preferenceState, setPreferenceState] = useState({ status: 'loading', data: null, message: '' })
  const [matchState, setMatchState] = useState({ status: 'idle', data: null, message: '' })
  const [filters, setFilters] = useState(initialFilters)
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [sortBy, setSortBy] = useState('newest')
  const [editingPreferences, setEditingPreferences] = useState(searchParams.get('preferences') === 'edit')
  const [expandedReasons, setExpandedReasons] = useState(() => new Set())
  const preferenceActionRef = useRef(null)

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

  const loadFavorites = useCallback(async () => {
    setFavoriteState({ status: 'loading', propertyIds: [], message: '' })
    try {
      const result = await getPropertyFavorites()
      setFavoriteState({ status: 'ready', propertyIds: result.propertyIds || [], message: '' })
    } catch (error) {
      setFavoriteState({ status: 'error', propertyIds: [], message: error.message || "We couldn't load your liked properties." })
    }
  }, [])

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
            if (!images?.length) return [property.id, []]
            const resolvedImages = await Promise.all(images.map(async (image) => {
              const result = await getPropertyImageUrl(property.id, image.id)
              return result?.url || null
            }))
            return [property.id, resolvedImages.filter(Boolean)]
          } catch {
            return [property.id, []]
          }
        }))
        if (active) setPropertyImages(Object.fromEntries(imageEntries))
      } catch (error) {
        if (active) setPropertyState({ status: 'error', message: error.message || 'Unable to load properties.' })
      }
    }
    loadProperties()
    Promise.resolve().then(loadPreferences)
    Promise.resolve().then(loadFavorites)
    return () => { active = false }
  }, [loadFavorites, loadPreferences])

  const openPreferences = () => {
    setEditingPreferences(true)
    setSearchParams({ preferences: 'edit' }, { replace: true })
  }
  const closePreferences = () => {
    setEditingPreferences(false)
    setSearchParams({}, { replace: true })
    window.requestAnimationFrame(() => preferenceActionRef.current?.focus())
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
  const favoriteIds = useMemo(() => new Set(favoriteState.propertyIds), [favoriteState.propertyIds])
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
    const sortable = sortBy === 'liked'
      ? filtered.filter((property) => favoriteIds.has(property.id))
      : filtered
    return [...sortable].sort((a, b) => {
      if (sortBy === 'liked') return Date.parse(b.createdAt || 0) - Date.parse(a.createdAt || 0)
      if (sortBy === 'bestMatch') return (matchByPropertyId.get(b.id)?.matchScore ?? -1) - (matchByPropertyId.get(a.id)?.matchScore ?? -1) || Number(a.monthlyRent) - Number(b.monthlyRent)
      if (sortBy === 'lowestRent') return Number(a.monthlyRent) - Number(b.monthlyRent)
      if (sortBy === 'highestRent') return Number(b.monthlyRent) - Number(a.monthlyRent)
      return Date.parse(b.createdAt || 0) - Date.parse(a.createdAt || 0)
    })
  }, [favoriteIds, filters, matchByPropertyId, properties, sortBy])

  const hasFilters = Object.values(filters).some(Boolean)
  const activeFilterCount = Object.entries(filters).filter(([name, value]) => name !== 'search' && Boolean(value)).length
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
  const toggleFavorite = async (propertyId) => {
    if (favoriteState.status !== 'ready' || favoritePending.has(propertyId)) return
    const currentlyLiked = favoriteIds.has(propertyId)
    setFavoritePending((current) => new Set(current).add(propertyId))
    try {
      if (currentlyLiked) await removePropertyFavorite(propertyId)
      else await addPropertyFavorite(propertyId)
      setFavoriteState((current) => ({
        ...current,
        message: '',
        propertyIds: currentlyLiked
          ? current.propertyIds.filter((id) => id !== propertyId)
          : [propertyId, ...current.propertyIds],
      }))
    } catch (error) {
      setFavoriteState((current) => ({ ...current, message: error.message || "We couldn't update your liked properties." }))
    } finally {
      setFavoritePending((current) => {
        const next = new Set(current)
        next.delete(propertyId)
        return next
      })
    }
  }

  return <main className="properties-page" aria-busy={propertyState.status === 'loading' || preferenceState.status === 'loading'}>
    <header className="properties-page__header">
      <div><span className="properties-page__eyebrow">Property marketplace</span><h1>Find a home that fits</h1><p className="properties-page__description">Browse real available rentals and use your saved preferences to see the strongest matches first.</p>{propertyState.status === 'ready' && <p className="properties-page__count">{visibleProperties.length} {visibleProperties.length === 1 ? 'property' : 'properties'} available</p>}</div>
    </header>

    {preferenceState.status === 'loading' && <section className="match-preference-loading" role="status"><span className="property-spinner" aria-hidden="true" />Loading your match preferences…</section>}
    {preferenceState.status === 'error' && <section className="match-preference-error" role="alert"><div><strong>We couldn't load your match preferences.</strong><p>{preferenceState.message}</p></div><button type="button" className="property-button property-button--outline" onClick={loadPreferences}>Retry</button></section>}
    {preferenceState.status === 'ready' && !hasPreferences && <section className="match-onboarding" aria-labelledby="match-onboarding-title"><span className="match-onboarding__icon"><Icon name="sparkles" size={25} /></span><div><h2 id="match-onboarding-title">Get personalized matches</h2><p>Tell us what you're looking for and RentFlow AI will rank suitable properties for you.</p></div><button ref={preferenceActionRef} type="button" className="property-button property-button--primary" onClick={openPreferences}>Set match preferences</button></section>}
    {hasPreferences && <MatchPreferenceSummary preferences={preferenceState.data} onEdit={openPreferences} actionRef={preferenceActionRef} />}
    {hasPreferences && matchState.status === 'loading' && <div className="match-inline-state" role="status"><span className="property-spinner" aria-hidden="true" />Finding properties that match your preferences…</div>}
    {hasPreferences && matchState.status === 'error' && <section className="match-preference-error" role="alert"><div><strong>We couldn't calculate your matches.</strong><p>{matchState.message}</p></div><button type="button" className="property-button property-button--outline" onClick={loadMatches}>Retry</button></section>}
    {hasPreferences && matchState.status === 'ready' && matchState.data?.explanationAvailable === false && matchState.data.matches?.length > 0 && <p className="match-advisory-note"><Icon name="info" size={17} />AI explanation is temporarily unavailable. Match scores are based on your saved preferences.</p>}
    {favoriteState.status === 'error' && <section className="match-preference-error" role="alert"><div><strong>We couldn't load your liked properties.</strong><p>{favoriteState.message}</p></div><button type="button" className="property-button property-button--outline" onClick={loadFavorites}>Retry</button></section>}
    {favoriteState.status === 'ready' && favoriteState.message && <section className="match-preference-error" role="alert"><div><strong>Liked properties could not be updated.</strong><p>{favoriteState.message}</p></div><button type="button" className="property-button property-button--outline" onClick={() => setFavoriteState((current) => ({ ...current, message: '' }))}>Dismiss</button></section>}

    <section className={`property-filters${filtersOpen ? ' is-open' : ''}`} aria-label="Property search and filters">
      <div className="property-filters__top">
        <div className="property-filters__search"><Icon name="search" size={19} /><input type="search" name="search" value={filters.search} onChange={updateFilter} placeholder="Search by location, property name…" aria-label="Search properties" /></div>
        <button type="button" className={`property-filter-toggle${activeFilterCount > 0 ? ' has-active-filters' : ''}`} aria-expanded={filtersOpen} aria-controls="property-filter-options" onClick={() => setFiltersOpen((open) => !open)}><Icon name="filters" size={19} /><span>Filters</span>{activeFilterCount > 0 && <strong aria-label={`${activeFilterCount} active filters`}>{activeFilterCount}</strong>}</button>
        <label className="property-sort"><span className="sr-only">Sort by</span><select aria-label="Sort properties" value={sortBy} onChange={(event) => setSortBy(event.target.value)}>{hasPreferences && <option value="bestMatch">Best Match</option>}<option value="liked">Liked</option><option value="lowestRent">Lowest Rent</option><option value="highestRent">Highest Rent</option><option value="newest">Newest</option></select></label>
      </div>
      {filtersOpen && <div id="property-filter-options" className="property-filter-options">
        <div className="property-filters__grid">
          <label><span>City</span><input name="city" value={filters.city} onChange={updateFilter} placeholder="Any city" /></label>
          <label><span>Maximum rent</span><input type="number" min="0" name="maxRent" value={filters.maxRent} onChange={updateFilter} placeholder="Any price" /></label>
          <label><span>Bedrooms</span><select name="minBedrooms" value={filters.minBedrooms} onChange={updateFilter}><option value="">Any</option><option value="1">1+</option><option value="2">2+</option><option value="3">3+</option><option value="4">4+</option></select></label>
          <label><span>Bathrooms</span><select name="minBathrooms" value={filters.minBathrooms} onChange={updateFilter}><option value="">Any</option><option value="1">1+</option><option value="2">2+</option><option value="3">3+</option></select></label>
          <label><span>Amenity</span><input name="amenity" value={filters.amenity} onChange={updateFilter} placeholder="Parking, Security…" /></label>
        </div>
        <div className="property-filter-options__footer"><span>{activeFilterCount > 0 ? `${activeFilterCount} ${activeFilterCount === 1 ? 'filter' : 'filters'} applied` : 'Choose filters to narrow the available properties.'}</span>{hasFilters && <button type="button" className="property-button property-button--quiet" onClick={() => setFilters(initialFilters)}>Clear filters</button>}</div>
      </div>}
    </section>

    {propertyState.status === 'loading' && <section className="property-state"><div className="property-spinner" /><h2>Loading properties</h2><p>Finding the latest available rental properties.</p></section>}
    {propertyState.status === 'error' && <section className="property-state property-state--error" role="alert"><h2>We couldn't load the properties</h2><p>{propertyState.message}</p></section>}
    {propertyState.status === 'ready' && visibleProperties.length === 0 && <section className="property-state"><h2>{sortBy === 'liked' ? 'No liked properties yet.' : hasPreferences ? 'No available properties match your current preferences.' : 'No matching properties'}</h2><p>{sortBy === 'liked' ? 'Use the heart button on a property card to add it here.' : hasFilters ? 'Try changing your filters.' : 'Check back as new available properties are listed.'}</p><div className="property-state__actions">{hasFilters && <button type="button" className="property-button property-button--outline" onClick={() => setFilters(initialFilters)}>Clear filters</button>}{hasPreferences && sortBy !== 'liked' && <button type="button" className="property-button property-button--primary" onClick={openPreferences}>Adjust preferences</button>}</div></section>}
    {propertyState.status === 'ready' && visibleProperties.length > 0 && <section className="property-grid" aria-label="Available properties">{visibleProperties.map((property) => {
      const match = hasPreferences && matchState.status === 'ready' ? matchByPropertyId.get(property.id) : null
      const reasonsOpen = expandedReasons.has(property.id)
      return <PropertyListingCard key={property.id} property={property}
        images={propertyImages[property.id] || []} match={match}
        liked={favoriteIds.has(property.id)}
        favoritePending={favoritePending.has(property.id) || favoriteState.status !== 'ready'}
        onToggleFavorite={toggleFavorite}>
          {match?.matchReasons?.length > 0 && <div className="property-card__reasons"><button type="button" aria-expanded={reasonsOpen} onClick={() => toggleReasons(property.id)}>Why this matches <span aria-hidden="true">{reasonsOpen ? '−' : '+'}</span></button>{reasonsOpen && <ul>{match.matchReasons.map((reason) => <li key={reason}><span className={isPositiveReason(reason) ? 'is-positive' : 'is-neutral'} aria-hidden="true">{isPositiveReason(reason) ? '✓' : '•'}</span>{reason}</li>)}</ul>}</div>}
      </PropertyListingCard>
    })}</section>}

    {editingPreferences && <MatchPreferencesDialog preferences={preferenceState.data} onClose={closePreferences} onSave={savePreferences} onReset={resetPreferences} />}
  </main>
}
