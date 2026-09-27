const GOOGLE_MAPS_EMBED_BASE_URL = 'https://www.google.com/maps/embed/v1/place'
const GOOGLE_MAPS_SEARCH_BASE_URL = 'https://www.google.com/maps/search/'

export function getPropertyLocation(address, city) {
  return [address, city]
    .filter((value) => typeof value === 'string' && value.trim())
    .map((value) => value.trim())
    .join(', ')
}

export function getCoordinateLocation(latitude, longitude) {
  if (latitude === null || latitude === undefined || latitude === ''
    || longitude === null || longitude === undefined || longitude === '') return ''

  const normalizedLatitude = Number(latitude)
  const normalizedLongitude = Number(longitude)

  if (!Number.isFinite(normalizedLatitude) || normalizedLatitude < -90 || normalizedLatitude > 90
    || !Number.isFinite(normalizedLongitude) || normalizedLongitude < -180 || normalizedLongitude > 180) {
    return ''
  }

  return `${normalizedLatitude},${normalizedLongitude}`
}

export function getPropertyMapQuery({ address, city, latitude, longitude }) {
  return getCoordinateLocation(latitude, longitude) || getPropertyLocation(address, city)
}

export function getGoogleMapsEmbedUrl(apiKey, location) {
  const normalizedKey = typeof apiKey === 'string' ? apiKey.trim() : ''
  const normalizedLocation = typeof location === 'string' ? location.trim() : ''

  if (!normalizedKey || !normalizedLocation) return ''

  const params = new URLSearchParams({
    key: normalizedKey,
    q: normalizedLocation,
  })

  return `${GOOGLE_MAPS_EMBED_BASE_URL}?${params.toString()}`
}

export function getGoogleMapsSearchUrl(location, googlePlaceId = '') {
  const normalizedLocation = typeof location === 'string' ? location.trim() : ''
  if (!normalizedLocation) return ''

  const params = new URLSearchParams({
    api: '1',
    query: normalizedLocation,
  })

  const normalizedPlaceId = typeof googlePlaceId === 'string' ? googlePlaceId.trim() : ''
  if (normalizedPlaceId) params.set('query_place_id', normalizedPlaceId)

  return `${GOOGLE_MAPS_SEARCH_BASE_URL}?${params.toString()}`
}
