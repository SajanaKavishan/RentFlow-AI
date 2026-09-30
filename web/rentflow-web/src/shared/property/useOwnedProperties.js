import { useContext } from 'react'
import OwnedPropertiesContext from './OwnedPropertiesContext.js'

export function useOwnedProperties() {
  return useContext(OwnedPropertiesContext)
}

export function useOwnedPropertySelection(propertyId) {
  const collection = useOwnedProperties()

  // Directly rendered feature tests and isolated consumers can still rely on
  // the server-side ownership guards. Production landlord routes provide the
  // collection context and verify selection before loading scoped resources.
  if (!collection) {
    return {
      collection: null,
      property: null,
      status: propertyId ? 'selected' : 'selection-required',
    }
  }

  if (collection.status !== 'ready') {
    return { collection, property: null, status: collection.status }
  }

  if (collection.properties.length === 0) {
    return { collection, property: null, status: 'empty' }
  }

  if (!propertyId) {
    return { collection, property: null, status: 'selection-required' }
  }

  const property = collection.properties.find((item) =>
    item.id.toLowerCase() === propertyId.toLowerCase()) ?? null

  return {
    collection,
    property,
    status: property ? 'selected' : 'unauthorized',
  }
}
