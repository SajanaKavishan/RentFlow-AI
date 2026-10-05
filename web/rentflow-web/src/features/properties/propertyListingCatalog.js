export const AMENITY_CATALOG = [
  { key: 'wifi', label: 'Wi-Fi', icon: 'wifi' },
  { key: 'parking', label: 'Parking', icon: 'car' },
  { key: 'air-conditioning', label: 'Air conditioning', icon: 'wind' },
  { key: 'washer-dryer', label: 'Washer / dryer', icon: 'washer' },
  { key: 'gym', label: 'Gym', icon: 'dumbbell' },
  { key: 'swimming-pool', label: 'Swimming pool', icon: 'waves' },
  { key: 'balcony', label: 'Balcony', icon: 'balcony' },
  { key: 'elevator', label: 'Elevator', icon: 'elevator' },
  { key: 'furnished', label: 'Furnished', icon: 'sofa' },
  { key: 'garden', label: 'Garden', icon: 'leaf' },
  { key: 'security', label: 'Security', icon: 'shield' },
  { key: 'rooftop', label: 'Rooftop', icon: 'rooftop' },
]

export const UTILITY_CATALOG = [
  { key: 'water', label: 'Water' },
  { key: 'electricity', label: 'Electricity' },
  { key: 'internet', label: 'Internet' },
  { key: 'gas', label: 'Gas' },
  { key: 'waste-collection', label: 'Waste collection' },
]

const amenitiesByKey = new Map(AMENITY_CATALOG.map((item) => [item.key, item]))
const normalizeAmenity = (value) => String(value ?? '').toLowerCase().replace(/[^a-z0-9]/g, '')
const amenitiesByName = new Map(AMENITY_CATALOG.flatMap((item) => [
  [normalizeAmenity(item.key), item],
  [normalizeAmenity(item.label), item],
]))
for (const [alias, key] of Object.entries({
  wirelessinternet: 'wifi', internet: 'wifi', carparking: 'parking',
  aircon: 'air-conditioning', ac: 'air-conditioning', laundry: 'washer-dryer',
  washeranddryer: 'washer-dryer', pool: 'swimming-pool', lift: 'elevator',
  fullyfurnished: 'furnished',
})) {
  amenitiesByName.set(alias, amenitiesByKey.get(key))
}

export function getAmenityPresentation(amenity) {
  const canonicalKey = typeof amenity === 'object' ? amenity?.canonicalKey : null
  const name = typeof amenity === 'object' ? amenity?.name : amenity
  const catalogItem = amenitiesByKey.get(canonicalKey) || amenitiesByName.get(normalizeAmenity(name))
  return catalogItem || { key: canonicalKey || String(name), label: String(name), icon: 'amenity' }
}

export function getPropertyAmenityDetails(property) {
  if (Array.isArray(property?.amenityDetails) && property.amenityDetails.length > 0) {
    return property.amenityDetails.filter((item) => item?.name)
  }
  return (property?.amenities || []).map((name) => ({ canonicalKey: null, name }))
}
