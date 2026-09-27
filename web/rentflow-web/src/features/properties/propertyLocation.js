const CITY_COMPONENT_TYPES = [
  'locality',
  'postal_town',
  'administrative_area_level_3',
  'sublocality_level_1',
  'sublocality',
]

export function cityFromAddressComponents(components = []) {
  for (const type of CITY_COMPONENT_TYPES) {
    const component = components.find((item) => Array.isArray(item?.types) && item.types.includes(type))
    const city = component?.longText?.trim()
    if (city) return city
  }
  return ''
}
