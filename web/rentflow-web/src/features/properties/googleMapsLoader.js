let googleMapsPromise

async function loadGoogleMaps(apiKey) {
  const normalizedKey = typeof apiKey === 'string' ? apiKey.trim() : ''
  if (!normalizedKey) throw new Error('Google Maps is not configured.')

  if (!window.google?.maps?.importLibrary) {
    googleMapsPromise ??= new Promise((resolve, reject) => {
      const callbackName = '__rentflowGoogleMapsReady'
      const script = document.createElement('script')
      const params = new URLSearchParams({
        key: normalizedKey,
        loading: 'async',
        v: 'weekly',
        callback: callbackName,
      })

      window[callbackName] = () => {
        delete window[callbackName]
        resolve(window.google?.maps)
      }
      script.src = `https://maps.googleapis.com/maps/api/js?${params.toString()}`
      script.async = true
      script.dataset.rentflowGoogleMaps = 'true'
      script.onerror = () => {
        delete window[callbackName]
        googleMapsPromise = undefined
        reject(new Error('Google Maps could not be loaded.'))
      }
      document.head.append(script)
    })

    await googleMapsPromise
  }

  return window.google.maps
}

export async function loadGooglePlaces(apiKey) {
  const maps = await loadGoogleMaps(apiKey)
  return maps.importLibrary('places')
}

export async function loadGoogleLocationTools(apiKey) {
  const maps = await loadGoogleMaps(apiKey)
  const [{ Map }, { AdvancedMarkerElement }, { Geocoder }, { Place }] = await Promise.all([
    maps.importLibrary('maps'),
    maps.importLibrary('marker'),
    maps.importLibrary('geocoding'),
    maps.importLibrary('places'),
  ])

  return { Map, AdvancedMarkerElement, Geocoder, Place }
}
