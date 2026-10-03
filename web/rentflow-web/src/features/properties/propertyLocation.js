const CITY_COMPONENT_TYPES = [
  'locality',
  'postal_town',
  'administrative_area_level_2',
  'administrative_area_level_3',
  'sublocality_level_1',
  'sublocality',
]

export function cityFromAddressComponents(components = []) {
  for (const type of CITY_COMPONENT_TYPES) {
    const component = components.find((item) => Array.isArray(item?.types) && item.types.includes(type))
    const city = (component?.longText || component?.long_name || '').trim()
    if (city) return city
  }
  return ''
}

export function locationFromGeocoderResult(result, latitude, longitude) {
  return locationFromGeocoderResults(result ? [result] : [], latitude, longitude)
}

export function locationFromGeocoderResults(results = [], latitude, longitude) {
  const validResults = Array.isArray(results)
    ? results.filter((result) => result && typeof result === 'object')
    : []
  const addressResult = validResults.find((result) => result.formatted_address?.trim())
  const addressComponents = validResults.flatMap((result) => (
    Array.isArray(result.address_components) ? result.address_components : []
  ))
  const placeResult = addressResult || validResults.find((result) => result.place_id?.trim())

  return {
    address: addressResult?.formatted_address?.trim() || '',
    city: cityFromAddressComponents(addressComponents),
    latitude,
    longitude,
    googlePlaceId: placeResult?.place_id?.trim() || null,
  }
}
