import { useEffect, useRef, useState } from 'react'
import Icon from '../../../shared/ui/Icons.jsx'
import { getGoogleMapsEmbedUrl, getPropertyMapQuery } from '../propertyMap.js'
import { loadGoogleLocationTools, loadGooglePlaces } from '../googleMapsLoader.js'
import { cityFromAddressComponents, locationFromGeocoderResults } from '../propertyLocation.js'

const DEFAULT_MAP_CENTER = { lat: 6.927079, lng: 79.861244 }
const SOURCE_LABELS = { google: 'Google place', current: 'Current location', map: 'Map pin', manual: 'Manual address' }

function coordinateValue(location, axis) {
  const value = location?.[axis]
  const coordinate = typeof value === 'function' ? value.call(location) : value
  return Number.isFinite(coordinate) ? coordinate : null
}

function hasCoordinates(location) {
  return Number.isFinite(location?.latitude) && Number.isFinite(location?.longitude)
}

function MethodActions({ onUseCurrentLocation, onPickOnMap, onUseManual }) {
  return (
    <div className="property-location-methods" aria-label="Other location methods">
      <button type="button" className="property-location-method" onClick={onUseCurrentLocation}><Icon name="pin" size={17} /> Use my current location</button>
      <button type="button" className="property-location-method" onClick={onPickOnMap}><Icon name="map" size={17} /> Pick on map</button>
      <button type="button" className="property-location-link" onClick={onUseManual}>Enter address manually</button>
    </div>
  )
}

function GooglePlaceSearch({ apiKey, onSelect, ...actions }) {
  const mountRef = useRef(null)
  const onSelectRef = useRef(onSelect)
  const [status, setStatus] = useState('loading')
  const [message, setMessage] = useState('')
  const [candidate, setCandidate] = useState(null)

  useEffect(() => { onSelectRef.current = onSelect }, [onSelect])

  useEffect(() => {
    let active = true
    let autocomplete
    let handleSelect
    const mount = mountRef.current

    loadGooglePlaces(apiKey).then(({ PlaceAutocompleteElement }) => {
      if (!active) return
      autocomplete = new PlaceAutocompleteElement()
      autocomplete.placeholder = 'Search address, building or place...'
      autocomplete.setAttribute('aria-label', 'Search address, building or place')
      autocomplete.className = 'property-google-autocomplete'
      handleSelect = async ({ placePrediction }) => {
        setStatus('selecting')
        setMessage('')
        setCandidate(null)
        try {
          const place = placePrediction.toPlace()
          await place.fetchFields({ fields: ['id', 'formattedAddress', 'location', 'addressComponents'] })
          const address = place.formattedAddress?.trim() || ''
          const city = cityFromAddressComponents(place.addressComponents)
          const latitude = coordinateValue(place.location, 'lat')
          const longitude = coordinateValue(place.location, 'lng')
          if (!address || latitude === null || longitude === null) throw new Error('Google did not return a complete location for this place.')
          const location = { address, city, latitude, longitude, googlePlaceId: place.id?.trim() || null }
          if (!city) {
            setCandidate(location)
            setStatus('needs-city')
            setMessage('Google found this place but did not return a city. Enter the city to confirm it.')
            return
          }
          onSelectRef.current(location, 'google')
          if (active) setStatus('ready')
        } catch (error) {
          if (!active) return
          setStatus('error')
          setMessage(error instanceof Error ? error.message : 'This place could not be selected.')
        }
      }
      autocomplete.addEventListener('gmp-select', handleSelect)
      mount?.replaceChildren(autocomplete)
      setStatus('ready')
    }).catch(() => {
      if (!active) return
      setStatus('unavailable')
      setMessage('Google location search is unavailable right now. Choose another location method.')
    })

    return () => {
      active = false
      if (autocomplete && handleSelect) autocomplete.removeEventListener('gmp-select', handleSelect)
      mount?.replaceChildren()
    }
  }, [apiKey])

  return (
    <div className="property-location-search">
      <label>Search address, building or place</label>
      <div ref={mountRef} className="property-location-search__control" aria-busy={status === 'loading' || status === 'selecting'} />
      {status === 'loading' && <p className="property-location-search__status" role="status">Loading Google location search...</p>}
      {status === 'selecting' && <p className="property-location-search__status" role="status">Confirming selected location...</p>}
      {message && <p className={status === 'needs-city' ? 'property-location-search__status' : 'property-location-search__error'} role={status === 'needs-city' ? 'status' : 'alert'}>{message}</p>}
      {candidate && <><LocationFields draft={candidate} onChange={setCandidate} /><button type="button" className="property-button property-button--primary" disabled={!candidate.city.trim()} onClick={() => onSelect(candidate, 'google')}>Confirm Google place</button></>}
      <MethodActions {...actions} />
    </div>
  )
}

function LocationFields({ draft, onChange, explanation }) {
  return (
    <div className="property-coordinate-address">
      {explanation && <p className="property-coordinate-address__notice">{explanation}</p>}
      <div className="property-form-field property-form-field--wide">
        <label htmlFor="coordinate-address">Address</label>
        <input id="coordinate-address" value={draft.address} onChange={(event) => onChange({ ...draft, address: event.target.value })} placeholder="Enter the property address" />
      </div>
      <div className="property-form-field">
        <label htmlFor="coordinate-city">City</label>
        <input id="coordinate-city" value={draft.city} onChange={(event) => onChange({ ...draft, city: event.target.value })} placeholder="e.g. Colombo" />
      </div>
    </div>
  )
}

async function reverseGeocode(apiKey, latitude, longitude) {
  const { Geocoder } = await loadGoogleLocationTools(apiKey)
  const { results = [] } = await new Geocoder().geocode({ location: { lat: latitude, lng: longitude } })
  return locationFromGeocoderResults(results, latitude, longitude)
}

function CurrentLocationPicker({ apiKey, onConfirm, onSearch, onPickOnMap, onUseManual }) {
  const [status, setStatus] = useState('idle')
  const [message, setMessage] = useState('')
  const [draft, setDraft] = useState(null)

  function locate() {
    setMessage('')
    setDraft(null)
    if (!navigator.geolocation) {
      setStatus('error')
      setMessage('Current location is not supported by this browser. Choose another location method.')
      return
    }
    setStatus('locating')
    navigator.geolocation.getCurrentPosition(async ({ coords }) => {
      const { latitude, longitude } = coords
      setDraft({ address: '', city: '', latitude, longitude, googlePlaceId: null })
      setStatus('geocoding')
      try {
        const resolved = await reverseGeocode(apiKey, latitude, longitude)
        setDraft(resolved)
        setStatus('ready')
        if (!resolved.address || !resolved.city) {
          setMessage('Exact location selected. Google could not find a complete street address. Add or confirm the address details below.')
        }
      } catch {
        setStatus('ready')
        setMessage('Exact location selected. Google could not find a complete street address. Add or confirm the address details below.')
      }
    }, (error) => {
      setStatus('error')
      const messages = {
        1: 'Location permission was denied. Allow access in your browser or choose another method.',
        2: 'Your current position is unavailable. Try again or choose another method.',
        3: 'Finding your current position timed out. Try again or choose another method.',
      }
      setMessage(messages[error?.code] || 'Your current position could not be found. Choose another method.')
    }, { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 })
  }

  const canConfirm = hasCoordinates(draft) && draft.address.trim() && draft.city.trim()
  return (
    <div className="property-location-workflow">
      <div className="property-location-workflow__heading">
        <div><strong>Use my current location</strong><p>Your browser will ask for permission only when you click the button.</p></div>
        <button type="button" className="property-button property-button--secondary" onClick={locate} disabled={status === 'locating' || status === 'geocoding'}>{status === 'locating' ? 'Locating...' : status === 'geocoding' ? 'Finding address...' : 'Find my location'}</button>
      </div>
      {(status === 'locating' || status === 'geocoding') && <p role="status" className="property-location-search__status">Please wait while we locate and verify this position.</p>}
      {message && <p role={status === 'error' ? 'alert' : 'status'} className={status === 'error' ? 'property-location-search__error' : 'property-location-search__status'}>{message}</p>}
      {draft && <><LocationFields draft={draft} onChange={setDraft} /><div className="property-coordinate-meta"><span>Latitude: {draft.latitude.toFixed(6)}</span><span>Longitude: {draft.longitude.toFixed(6)}</span></div><button type="button" className="property-button property-button--primary" disabled={!canConfirm} onClick={() => onConfirm(draft, 'current')}>Confirm current location</button></>}
      <div className="property-location-workflow__links">
        {apiKey && <button type="button" className="property-location-link" onClick={onSearch}>Search with Google</button>}
        <button type="button" className="property-location-link" onClick={onPickOnMap}>Pick on map</button>
        <button type="button" className="property-location-link" onClick={onUseManual}>Enter address manually</button>
      </div>
    </div>
  )
}

const INCOMPLETE_ADDRESS_MESSAGE = 'Exact location selected. Google could not find a complete address. Enter or confirm the address details below.'
const GEOCODER_ERROR_MESSAGES = {
  REQUEST_DENIED: 'Location lookup is unavailable. Check the Google Geocoding API configuration.',
  OVER_QUERY_LIMIT: 'Location lookup has reached its request limit. Enter the address details below or try again later.',
  UNKNOWN_ERROR: 'Location lookup failed temporarily. Enter the address details below or try again.',
  ERROR: 'Location lookup failed temporarily. Enter the address details below or try again.',
}

function geocoderErrorStatus(error) {
  const detail = [
    typeof error === 'string' ? error : '',
    error?.code,
    error?.status,
    error?.message,
  ].filter(Boolean).join(' ').toUpperCase()
  return ['REQUEST_DENIED', 'OVER_QUERY_LIMIT', 'ZERO_RESULTS', 'UNKNOWN_ERROR', 'ERROR']
    .find((status) => detail.includes(status)) || 'ERROR'
}

function InteractiveMap({ apiKey, initialPosition, onDraftChange, onLookupPendingChange }) {
  const mountRef = useRef(null)
  const onDraftChangeRef = useRef(onDraftChange)
  const onLookupPendingChangeRef = useRef(onLookupPendingChange)
  const [status, setStatus] = useState('loading')
  const [message, setMessage] = useState('')
  const [messageIsError, setMessageIsError] = useState(false)
  useEffect(() => { onDraftChangeRef.current = onDraftChange }, [onDraftChange])
  useEffect(() => { onLookupPendingChangeRef.current = onLookupPendingChange }, [onLookupPendingChange])

  useEffect(() => {
    let active = true
    let marker
    let mapClickListener
    let dragEndListener
    let selectionVersion = 0

    loadGoogleLocationTools(apiKey).then(({ Map, AdvancedMarkerElement, Geocoder, Place }) => {
      if (!active || !mountRef.current) return
      const initialCoordinates = hasCoordinates(initialPosition) ? { lat: initialPosition.latitude, lng: initialPosition.longitude } : null
      const mapId = import.meta.env.VITE_GOOGLE_MAPS_MAP_ID?.trim() || 'DEMO_MAP_ID'
      const map = new Map(mountRef.current, { center: initialCoordinates || DEFAULT_MAP_CENTER, zoom: initialCoordinates ? 17 : 7, mapId, mapTypeControl: false, streetViewControl: false, fullscreenControl: true, clickableIcons: true })
      const geocoder = new Geocoder()

      const selectPosition = async (latitude, longitude, placeId = null) => {
        const currentSelection = ++selectionVersion
        if (!marker) {
          marker = new AdvancedMarkerElement({ map, position: { lat: latitude, lng: longitude }, title: 'Selected property location. Drag to adjust the pin.', gmpDraggable: true })
          dragEndListener = () => {
            const lat = coordinateValue(marker.position, 'lat')
            const lng = coordinateValue(marker.position, 'lng')
            if (lat !== null && lng !== null) void selectPosition(lat, lng)
          }
          marker.addEventListener('gmp-dragend', dragEndListener)
        } else marker.position = { lat: latitude, lng: longitude }
        map.panTo({ lat: latitude, lng: longitude })
        setStatus(placeId ? 'place-details' : 'geocoding')
        setMessage('')
        setMessageIsError(false)
        onLookupPendingChangeRef.current(true)
        onDraftChangeRef.current({ address: '', city: '', latitude, longitude, googlePlaceId: placeId })
        try {
          let resolved
          if (placeId) {
            const place = new Place({ id: placeId })
            await place.fetchFields({
              fields: ['id', 'location', 'formattedAddress', 'addressComponents'],
            })
            const placeLatitude = coordinateValue(place.location, 'lat')
            const placeLongitude = coordinateValue(place.location, 'lng')
            resolved = {
              address: place.formattedAddress?.trim() || '',
              city: cityFromAddressComponents(place.addressComponents),
              latitude: placeLatitude ?? latitude,
              longitude: placeLongitude ?? longitude,
              googlePlaceId: place.id?.trim() || placeId,
            }
          } else {
            const { results = [] } = await geocoder.geocode({
              location: { lat: latitude, lng: longitude },
              fulfillOnZeroResults: true,
            })
            resolved = locationFromGeocoderResults(results, latitude, longitude)
          }

          if (active && currentSelection === selectionVersion) {
            marker.position = { lat: resolved.latitude, lng: resolved.longitude }
            map.panTo(marker.position)
            onDraftChangeRef.current(resolved)
            if (!resolved.address || !resolved.city) {
              setMessage(INCOMPLETE_ADDRESS_MESSAGE)
            }
          }
        } catch (error) {
          if (active && currentSelection === selectionVersion) {
            const errorStatus = geocoderErrorStatus(error)
            setMessage(placeId
              ? 'Place details are unavailable. Confirm the address details below or choose another location method.'
              : errorStatus === 'ZERO_RESULTS'
                ? INCOMPLETE_ADDRESS_MESSAGE
                : GEOCODER_ERROR_MESSAGES[errorStatus])
            setMessageIsError(errorStatus !== 'ZERO_RESULTS')
          }
        } finally {
          if (active && currentSelection === selectionVersion) {
            setStatus('ready')
            onLookupPendingChangeRef.current(false)
          }
        }
      }

      if (initialCoordinates) {
        void selectPosition(
          initialCoordinates.lat,
          initialCoordinates.lng,
          initialPosition.googlePlaceId?.trim() || null,
        )
      }
      mapClickListener = map.addListener('click', (event) => {
        const latitude = coordinateValue(event.latLng, 'lat')
        const longitude = coordinateValue(event.latLng, 'lng')
        const placeId = event.placeId?.trim() || null
        if (placeId) event.stop?.()
        if (latitude !== null && longitude !== null) void selectPosition(latitude, longitude, placeId)
      })
      setStatus(initialCoordinates ? 'geocoding' : 'ready')
    }).catch(() => {
      if (!active) return
      setStatus('error')
      setMessageIsError(true)
      setMessage('The interactive map is unavailable. Search with Google or enter the address manually.')
    })

    return () => {
      active = false
      mapClickListener?.remove?.()
      if (marker && dragEndListener) marker.removeEventListener('gmp-dragend', dragEndListener)
      if (marker) marker.map = null
    }
  }, [apiKey, initialPosition])

  return <><div ref={mountRef} className="property-interactive-map" role="application" aria-label="Interactive property location map. Click the map or drag the marker to choose a position." />{status === 'loading' && <p className="property-location-search__status" role="status">Loading interactive map...</p>}{status === 'geocoding' && <p className="property-location-search__status" role="status">Finding the address for this pin...</p>}{status === 'place-details' && <p className="property-location-search__status" role="status">Loading place details...</p>}{message && <p className={messageIsError ? 'property-location-search__error' : 'property-location-search__status'} role={messageIsError ? 'alert' : 'status'}>{message}</p>}</>
}

function MapLocationPicker({ apiKey, form, onConfirm, onSearch, onUseCurrentLocation, onUseManual }) {
  const [draft, setDraft] = useState(null)
  const [lookupPending, setLookupPending] = useState(false)
  const initialPosition = hasCoordinates(form) ? form : null
  const canConfirm = hasCoordinates(draft) && !lookupPending
  return (
    <div className="property-location-workflow">
      <div className="property-location-workflow__heading"><div><strong>Pick on map</strong><p>Click the map to place a marker, or drag the marker to fine-tune the position.</p></div></div>
      {apiKey ? <InteractiveMap apiKey={apiKey} initialPosition={initialPosition} onDraftChange={setDraft} onLookupPendingChange={setLookupPending} /> : <div className="property-location-search__fallback" role="alert"><strong>Interactive map unavailable</strong><p>Configure the Google Maps browser key or choose manual entry.</p></div>}
      {draft && <><LocationFields draft={draft} onChange={setDraft} /><div className="property-coordinate-meta"><span>Latitude: {draft.latitude.toFixed(6)}</span><span>Longitude: {draft.longitude.toFixed(6)}</span></div><button type="button" className="property-button property-button--primary" disabled={!canConfirm} onClick={() => onConfirm(draft, 'map')}>{lookupPending ? 'Looking up location...' : 'Use this pin'}</button></>}
      <div className="property-location-workflow__links">
        {apiKey && <button type="button" className="property-location-link" onClick={onSearch}>Search with Google</button>}
        <button type="button" className="property-location-link" onClick={onUseCurrentLocation}>Use my current location</button>
        <button type="button" className="property-location-link" onClick={onUseManual}>Enter address manually</button>
      </div>
    </div>
  )
}

function LocationSummary({ form, source, apiKey, legacy, errors, onFieldChange, onChangeLocation, onPickOnMap, onUseCurrentLocation, onUseManual }) {
  const coordinatesAvailable = hasCoordinates(form)
  const needsAddressDetails = coordinatesAvailable && (!form.address.trim() || !form.city.trim())
  const embedUrl = coordinatesAvailable ? getGoogleMapsEmbedUrl(apiKey, getPropertyMapQuery(form)) : ''
  return (
    <div className="property-selected-location">
      {embedUrl && <div className="property-selected-location__map"><iframe title={`Map preview for ${form.address || 'selected property location'}`} src={embedUrl} loading="lazy" referrerPolicy="no-referrer-when-downgrade" allowFullScreen /></div>}
      {coordinatesAvailable && !embedUrl && <div className="property-location-search__fallback" role="status"><strong>Map preview unavailable</strong><p>The address and exact coordinates remain unchanged.</p></div>}
      <div className="property-selected-location__details"><span className="property-selected-location__icon" aria-hidden="true"><Icon name="pin" size={19} /></span><div><strong>{legacy ? 'Current property location' : 'Selected location'}</strong>{form.address && <p>{form.address}</p>}{form.city && <span>{form.city}</span>}{coordinatesAvailable && <div className="property-coordinate-meta"><span>Latitude: {form.latitude.toFixed(6)}</span><span>Longitude: {form.longitude.toFixed(6)}</span></div>}{!legacy && <small>Source: {SOURCE_LABELS[source] || SOURCE_LABELS.google}</small>}{legacy && <small>Legacy address — exact coordinates have not been saved.</small>}</div></div>
      {needsAddressDetails && (
        <div className="property-coordinate-address">
          <p className="property-coordinate-address__notice">The exact pin is confirmed. Complete the address and city before continuing.</p>
          <div className="property-form-field property-form-field--wide"><label htmlFor="address">Address</label><input id="address" name="address" value={form.address} onChange={onFieldChange} placeholder="Enter the property address" aria-invalid={Boolean(errors.address)} aria-describedby={errors.address ? 'address-error' : undefined} />{errors.address && <small className="property-field-error" id="address-error">{errors.address}</small>}</div>
          <div className="property-form-field"><label htmlFor="city">City</label><input id="city" name="city" value={form.city} onChange={onFieldChange} placeholder="e.g. Colombo" aria-invalid={Boolean(errors.city)} aria-describedby={errors.city ? 'city-error' : undefined} />{errors.city && <small className="property-field-error" id="city-error">{errors.city}</small>}</div>
        </div>
      )}
      <div className="property-selected-location__actions">
        {apiKey && <button type="button" className="property-location-link" onClick={onChangeLocation}>{legacy ? 'Search with Google' : 'Change location'}</button>}
        <button type="button" className="property-location-link" onClick={onUseCurrentLocation}>Use my current location</button>
        <button type="button" className="property-location-link" onClick={onPickOnMap}>{legacy ? 'Locate on map' : 'Adjust pin on map'}</button>
        <button type="button" className="property-location-link" onClick={onUseManual}>Enter address manually</button>
      </div>
    </div>
  )
}

function ManualLocation({ form, errors, apiKey, onFieldChange, onSearch, onUseCurrentLocation, onPickOnMap }) {
  return (
    <div className="property-manual-location">
      <div className="property-location-search__fallback property-manual-location__notice" role="status"><strong>Manual address</strong><p>No hidden coordinates or Google Place ID will be saved in this mode.</p></div>
      <div className="property-form-field property-form-field--wide"><label htmlFor="address">Address</label><input id="address" name="address" value={form.address} onChange={onFieldChange} placeholder="Enter the property address" aria-invalid={Boolean(errors.address)} aria-describedby={errors.address ? 'address-error' : undefined} />{errors.address && <small className="property-field-error" id="address-error">{errors.address}</small>}</div>
      <div className="property-form-field"><label htmlFor="city">City</label><input id="city" name="city" value={form.city} onChange={onFieldChange} placeholder="e.g. Colombo" aria-invalid={Boolean(errors.city)} aria-describedby={errors.city ? 'city-error' : undefined} />{errors.city && <small className="property-field-error" id="city-error">{errors.city}</small>}</div>
      <div className="property-location-workflow__links property-manual-location__search">{apiKey && <button type="button" className="property-location-link" onClick={onSearch}>Search with Google</button>}<button type="button" className="property-location-link" onClick={onUseCurrentLocation}>Use my current location</button><button type="button" className="property-location-link" onClick={onPickOnMap}>Pick on map</button></div>
    </div>
  )
}

export default function PropertyLocationPicker({ form, mode, source, errors, onFieldChange, onLocationSelected, onChangeLocation, onUseManual, onSearchWithGoogle, onUseCurrentLocation, onPickOnMap }) {
  const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY?.trim() || ''
  return (
    <section className="property-location-picker" aria-labelledby="property-location-picker-title">
      <div className="property-location-picker__heading"><div><h3 id="property-location-picker-title">Property location</h3><p>Search, use your current position, choose a map point, or enter the address manually.</p></div><Icon name="pin" size={20} /></div>
      {mode === 'search' && apiKey && <GooglePlaceSearch apiKey={apiKey} onSelect={onLocationSelected} onUseCurrentLocation={onUseCurrentLocation} onPickOnMap={onPickOnMap} onUseManual={onUseManual} />}
      {mode === 'search' && !apiKey && <div className="property-location-search__fallback" role="status"><strong>Google location search is not configured</strong><p>Use your current position with manual address confirmation, or enter the address manually.</p><MethodActions onUseCurrentLocation={onUseCurrentLocation} onPickOnMap={onPickOnMap} onUseManual={onUseManual} /></div>}
      {mode === 'current' && <CurrentLocationPicker apiKey={apiKey} onConfirm={onLocationSelected} onSearch={onSearchWithGoogle} onPickOnMap={onPickOnMap} onUseManual={onUseManual} />}
      {mode === 'map' && <MapLocationPicker apiKey={apiKey} form={form} onConfirm={onLocationSelected} onSearch={onSearchWithGoogle} onUseCurrentLocation={onUseCurrentLocation} onUseManual={onUseManual} />}
      {(mode === 'confirmed' || mode === 'legacy') && <LocationSummary form={form} source={source} apiKey={apiKey} legacy={mode === 'legacy'} errors={errors} onFieldChange={onFieldChange} onChangeLocation={onChangeLocation} onPickOnMap={onPickOnMap} onUseCurrentLocation={onUseCurrentLocation} onUseManual={onUseManual} />}
      {mode === 'manual' && <ManualLocation form={form} errors={errors} apiKey={apiKey} onFieldChange={onFieldChange} onSearch={onSearchWithGoogle} onUseCurrentLocation={onUseCurrentLocation} onPickOnMap={onPickOnMap} />}
      {errors.location && <p className="property-location-picker__error" role="alert">{errors.location}</p>}
    </section>
  )
}
