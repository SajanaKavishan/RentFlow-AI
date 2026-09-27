let googleMapsPromise

export async function loadGooglePlaces(apiKey) {
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

  return window.google.maps.importLibrary('places')
}
