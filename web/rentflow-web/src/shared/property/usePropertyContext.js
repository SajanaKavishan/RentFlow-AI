import { useLocation, useParams } from 'react-router-dom'

const PROPERTY_ID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function validPropertyId(value) {
  if (typeof value !== 'string') return null

  const propertyId = value.trim()
  return PROPERTY_ID_PATTERN.test(propertyId) ? propertyId : null
}

export default function usePropertyContext() {
  const { propertyId: routePropertyId } = useParams()
  const location = useLocation()
  const queryPropertyId = new URLSearchParams(location.search).get('propertyId')
  const navigationPropertyId = location.state?.propertyId
  const propertyId = [routePropertyId, queryPropertyId, navigationPropertyId]
    .map(validPropertyId)
    .find(Boolean) ?? null

  return { propertyId }
}
