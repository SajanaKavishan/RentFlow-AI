import { useEffect, useState } from 'react'
import { ApiError } from '../../core/api/apiClient.js'

export default function usePropertySummary(load, propertyIds) {
  const [attempt, setAttempt] = useState(0)
  const [state, setState] = useState(null)
  const scopeKey = Array.isArray(propertyIds)
    ? propertyIds.map((propertyId) => propertyId.toLowerCase()).sort().join(',')
    : null

  useEffect(() => {
    if (scopeKey === null || scopeKey === '') return undefined
    let active = true

    async function fetchSummary() {
      try {
        const scopeIds = scopeKey.split(',')
        const allowedPropertyIds = new Set(scopeIds)
        const data = (await Promise.all(scopeIds.map((propertyId) => load(propertyId)))).flat()
        if (!Array.isArray(data) || data.some((item) =>
          !item || typeof item.id !== 'string' || !item.id.trim() || !Number.isInteger(item.status) ||
          typeof item.propertyId !== 'string' || !allowedPropertyIds.has(item.propertyId.toLowerCase())) ||
          new Set(data.map((item) => item.id.toLowerCase())).size !== data.length) {
          throw new ApiError('The service returned an invalid summary. Please try again.')
        }
        if (active) setState({ scopeKey, attempt, status: 'ready', data })
      } catch (error) {
        if (active) setState({
          scopeKey, attempt, status: 'error', data: [],
          message: error instanceof ApiError ? error.message : 'Unable to load this summary. Please try again.',
        })
      }
    }

    fetchSummary()
    return () => { active = false }
  }, [load, scopeKey, attempt])

  // Hide previous data immediately when the property changes, before effects run.
  // DashboardPage also remounts this dashboard when the authenticated user changes.
  const current = scopeKey === null
    ? { status: 'loading', data: [] }
    : scopeKey === ''
      ? { status: 'ready', data: [] }
      : state?.scopeKey === scopeKey && state.attempt === attempt
      ? state
      : { status: 'loading', data: [] }

  return { ...current, retry: () => setAttempt((value) => value + 1) }
}
