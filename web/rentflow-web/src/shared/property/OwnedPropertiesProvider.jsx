import { useCallback, useEffect, useMemo, useState } from 'react'
import { Outlet } from 'react-router-dom'
import { getMyProperties } from '../../features/properties/services/propertyApiService.js'
import { useAuth } from '../../features/auth/useAuth.js'
import OwnedPropertiesContext from './OwnedPropertiesContext.js'

function validOwnedProperties(value) {
  if (!Array.isArray(value) || value.some((property) =>
    !property || typeof property.id !== 'string' || !property.id.trim()
    || typeof property.title !== 'string'
    || typeof property.address !== 'string'
    || typeof property.city !== 'string'
    || typeof property.isAvailable !== 'boolean'
  )) throw new TypeError('Invalid owned property response')

  const ids = value.map((property) => property.id.toLowerCase())
  if (new Set(ids).size !== ids.length) throw new TypeError('Duplicate owned property response')
  return value
}

export default function OwnedPropertiesProvider({ children }) {
  const { user } = useAuth()
  const [attempt, setAttempt] = useState(0)
  const [result, setResult] = useState(null)

  useEffect(() => {
    let active = true
    getMyProperties()
      .then((properties) => {
        if (active) setResult({ userId: user.id, attempt, status: 'ready', properties: validOwnedProperties(properties), error: '' })
      })
      .catch((error) => {
        if (active) setResult({
          userId: user.id,
          attempt,
          status: 'error',
          properties: [],
          error: error instanceof Error ? error.message : 'Unable to load your properties.',
        })
      })
    return () => { active = false }
  }, [attempt, user.id])

  const retry = useCallback(() => setAttempt((value) => value + 1), [])
  const value = useMemo(() => {
    const current = result?.userId === user.id && result.attempt === attempt
      ? result
      : { status: 'loading', properties: [], error: '' }
    return { ...current, retry }
  }, [attempt, result, retry, user.id])

  return <OwnedPropertiesContext.Provider value={value}>
    {children ?? <Outlet />}
  </OwnedPropertiesContext.Provider>
}
