const GOOGLE_MAPS_EMBED_BASE_URL = 'https://www.google.com/maps/embed/v1/place'
const GOOGLE_MAPS_SEARCH_BASE_URL = 'https://www.google.com/maps/search/'

export function getPropertyLocation(address, city) {
  return [address, city]
    .filter((value) => typeof value === 'string' && value.trim())
    .map((value) => value.trim())
    .join(', ')
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

export function getGoogleMapsSearchUrl(location) {
  const normalizedLocation = typeof location === 'string' ? location.trim() : ''
  if (!normalizedLocation) return ''

  const params = new URLSearchParams({
    api: '1',
    query: normalizedLocation,
  })

  return `${GOOGLE_MAPS_SEARCH_BASE_URL}?${params.toString()}`
}
