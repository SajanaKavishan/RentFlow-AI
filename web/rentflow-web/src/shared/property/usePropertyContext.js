import { useLocation, useParams } from 'react-router-dom'

const PROPERTY_ID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function validPropertyId(value) {
  if (typeof value !== 'string') return null

  const propertyId = value.trim()
  return PROPERTY_ID_PATTERN.test(propertyId) ? propertyId : null
}

export function propertyIdFromLocation(location, routePropertyId) {
  const scopedRouteId = /^\/properties\/([^/]+)\/(?:viewing-requests|ai-review|rental-applications(?:\/[^/]+\/validation)?)\/?$/.exec(location.pathname)?.[1]
  const queryPropertyId = new URLSearchParams(location.search).get('propertyId')
  return [routePropertyId, scopedRouteId, queryPropertyId, location.state?.propertyId]
    .map(validPropertyId)
    .find(Boolean) ?? null
}

export default function usePropertyContext() {
  const { propertyId: routePropertyId } = useParams()
  const location = useLocation()
  return { propertyId: propertyIdFromLocation(location, routePropertyId) }
}
