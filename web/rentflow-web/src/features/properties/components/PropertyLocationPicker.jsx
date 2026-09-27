import { useEffect, useRef, useState } from 'react'
import Icon from '../../../shared/ui/Icons.jsx'
import { getGoogleMapsEmbedUrl, getPropertyMapQuery } from '../propertyMap.js'
import { loadGooglePlaces } from '../googleMapsLoader.js'
import { cityFromAddressComponents } from '../propertyLocation.js'

function coordinateValue(location, axis) {
  const value = location?.[axis]
  const coordinate = typeof value === 'function' ? value.call(location) : value
  return Number.isFinite(coordinate) ? coordinate : null
}

function GooglePlaceSearch({ apiKey, onSelect, onUseManual }) {
  const mountRef = useRef(null)
  const onSelectRef = useRef(onSelect)
  const [status, setStatus] = useState('loading')
  const [message, setMessage] = useState('')

  useEffect(() => {
    onSelectRef.current = onSelect
  }, [onSelect])

  useEffect(() => {
    let active = true
    let autocomplete
    let handleSelect
    const mount = mountRef.current

    loadGooglePlaces(apiKey)
      .then(({ PlaceAutocompleteElement }) => {
        if (!active) return
        autocomplete = new PlaceAutocompleteElement()
        autocomplete.placeholder = 'Search address, building or place...'
        autocomplete.setAttribute('aria-label', 'Search address, building or place')
        autocomplete.className = 'property-google-autocomplete'
        handleSelect = async ({ placePrediction }) => {
          setStatus('selecting')
          setMessage('')
          try {
            const place = placePrediction.toPlace()
            await place.fetchFields({
              fields: ['id', 'formattedAddress', 'location', 'addressComponents'],
            })
            const address = place.formattedAddress?.trim() || ''
            const city = cityFromAddressComponents(place.addressComponents)
            const latitude = coordinateValue(place.location, 'lat')
            const longitude = coordinateValue(place.location, 'lng')

            if (!address || !city || latitude === null || longitude === null) {
              throw new Error('Google did not return a complete address and city for this place.')
            }

            onSelectRef.current({
              address,
              city,
              latitude,
              longitude,
              googlePlaceId: place.id?.trim() || null,
            })
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
      })
      .catch(() => {
        if (!active) return
        setStatus('unavailable')
        setMessage('Google location search is unavailable right now. Enter the address manually to continue.')
      })

    return () => {
      active = false
      if (autocomplete && handleSelect) autocomplete.removeEventListener('gmp-select', handleSelect)
      mount?.replaceChildren()
    }
  }, [apiKey])

  return (
    <div className="property-location-search">
      <label id="property-location-search-label">Search address, building or place</label>
      <div
        ref={mountRef}
        className="property-location-search__control"
        aria-busy={status === 'loading' || status === 'selecting'}
      />
      {status === 'loading' && <p className="property-location-search__status" role="status">Loading Google location search...</p>}
      {status === 'selecting' && <p className="property-location-search__status" role="status">Confirming selected location...</p>}
      {message && <p className="property-location-search__error" role="alert">{message}</p>}
      <button type="button" className="property-location-link" onClick={onUseManual}>
        Enter address manually
      </button>
    </div>
  )
}

function LocationSummary({ form, hasCoordinates, apiKey, onChangeLocation, onUseManual }) {
  const mapQuery = getPropertyMapQuery(form)
  const embedUrl = hasCoordinates ? getGoogleMapsEmbedUrl(apiKey, mapQuery) : ''

  return (
    <div className="property-selected-location">
      {embedUrl && (
        <div className="property-selected-location__map">
          <iframe
            title={`Map preview for ${form.address}`}
            src={embedUrl}
            loading="lazy"
            referrerPolicy="no-referrer-when-downgrade"
            allowFullScreen
          />
        </div>
      )}
      {hasCoordinates && !embedUrl && (
        <div className="property-location-search__fallback" role="status">
          <strong>Map preview unavailable</strong>
          <p>The saved address and exact coordinates will remain unchanged.</p>
        </div>
      )}
      <div className="property-selected-location__details">
        <span className="property-selected-location__icon" aria-hidden="true"><Icon name="pin" size={19} /></span>
        <div>
          <strong>{hasCoordinates ? 'Selected location' : 'Current property location'}</strong>
          <p>{form.address}</p>
          <span>{form.city}</span>
          {!hasCoordinates && <small>Legacy address — exact coordinates have not been saved.</small>}
        </div>
      </div>
      <div className="property-selected-location__actions">
        {apiKey && <button type="button" className="property-location-link" onClick={onChangeLocation}>Change location</button>}
        <button type="button" className="property-location-link" onClick={onUseManual}>Enter address manually</button>
      </div>
    </div>
  )
}

export default function PropertyLocationPicker({
  form,
  mode,
  errors,
  onFieldChange,
  onLocationSelected,
  onChangeLocation,
  onUseManual,
  onSearchWithGoogle,
}) {
  const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY?.trim() || ''
  const hasCoordinates = Number.isFinite(form.latitude) && Number.isFinite(form.longitude)

  return (
    <section className="property-location-picker" aria-labelledby="property-location-picker-title">
      <div className="property-location-picker__heading">
        <div>
          <h3 id="property-location-picker-title">Property location</h3>
          <p>Choose an authoritative Google place or use the manual fallback.</p>
        </div>
        <Icon name="pin" size={20} />
      </div>

      {mode === 'search' && apiKey && (
        <GooglePlaceSearch apiKey={apiKey} onSelect={onLocationSelected} onUseManual={onUseManual} />
      )}

      {mode === 'search' && !apiKey && (
        <div className="property-location-search__fallback" role="status">
          <strong>Google location search is not configured</strong>
          <p>Enter the property address manually to continue.</p>
          <button type="button" className="property-location-link" onClick={onUseManual}>Enter address manually</button>
        </div>
      )}

      {(mode === 'confirmed' || mode === 'legacy') && (
        <LocationSummary
          form={form}
          hasCoordinates={hasCoordinates}
          apiKey={apiKey}
          onChangeLocation={onChangeLocation}
          onUseManual={onUseManual}
        />
      )}

      {mode === 'manual' && (
        <div className="property-manual-location">
          {!apiKey && (
            <div className="property-location-search__fallback property-manual-location__notice" role="status">
              <strong>Google location search is unavailable</strong>
              <p>Enter the address and city manually. No coordinates will be created.</p>
            </div>
          )}
          <div className="property-form-field property-form-field--wide">
            <label htmlFor="address">Address</label>
            <input
              id="address"
              name="address"
              value={form.address}
              onChange={onFieldChange}
              placeholder="Enter the property address"
              aria-invalid={Boolean(errors.address)}
              aria-describedby={errors.address ? 'address-error' : undefined}
            />
            {errors.address && <small className="property-field-error" id="address-error">{errors.address}</small>}
          </div>
          <div className="property-form-field">
            <label htmlFor="city">City</label>
            <input
              id="city"
              name="city"
              value={form.city}
              onChange={onFieldChange}
              placeholder="e.g. Colombo"
              aria-invalid={Boolean(errors.city)}
              aria-describedby={errors.city ? 'city-error' : undefined}
            />
            {errors.city && <small className="property-field-error" id="city-error">{errors.city}</small>}
          </div>
          {apiKey && (
            <button type="button" className="property-location-link property-manual-location__search" onClick={onSearchWithGoogle}>
              Search with Google
            </button>
          )}
        </div>
      )}

      {errors.location && <p className="property-location-picker__error" role="alert">{errors.location}</p>}
    </section>
  )
}
