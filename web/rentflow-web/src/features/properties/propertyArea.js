export const PROPERTY_AREA_UNITS = [
  { value: 'sqft', label: 'sq ft' },
  { value: 'sqm', label: 'sq m' },
  { value: 'perch', label: 'perches' },
  { value: 'acre', label: 'acres' },
]

export const PROPERTY_AREA_TYPES = [
  { value: 'FloorArea', label: 'Floor area' },
  { value: 'LandArea', label: 'Land area' },
]

export function getPropertyAreaUnits(areaType) {
  return areaType === 'FloorArea'
    ? PROPERTY_AREA_UNITS.filter((item) => item.value === 'sqft' || item.value === 'sqm')
    : PROPERTY_AREA_UNITS
}

export function formatPropertyArea(area, areaUnit, areaType = null) {
  const numericArea = Number(area)
  if (!Number.isFinite(numericArea) || numericArea <= 0) return 'Not specified'

  const unit = PROPERTY_AREA_UNITS.find((item) => item.value === areaUnit)
  const areaLabel = numericArea.toLocaleString(undefined, { maximumFractionDigits: 2 })
  const type = PROPERTY_AREA_TYPES.find((item) => item.value === areaType)
  const unitLabel = unit?.label || areaUnit || 'unit not specified'
  return `${type?.label || 'Size'}: ${areaLabel} ${unitLabel}`
}
