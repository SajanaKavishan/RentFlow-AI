export const PROPERTY_AREA_UNITS = [
  { value: 'sqft', label: 'sq ft' },
  { value: 'sqm', label: 'sq m' },
  { value: 'perch', label: 'perches' },
  { value: 'acre', label: 'acres' },
]

export function formatPropertyArea(area, areaUnit) {
  const numericArea = Number(area)
  if (!Number.isFinite(numericArea) || numericArea <= 0) return 'Not specified'

  const unit = PROPERTY_AREA_UNITS.find((item) => item.value === areaUnit)
  const areaLabel = numericArea.toLocaleString(undefined, { maximumFractionDigits: 2 })
  return `${areaLabel} ${unit?.label || areaUnit || 'sq ft'}`
}
