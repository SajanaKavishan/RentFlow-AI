import { useEffect, useState } from 'react'
import { ApiError } from '../../core/api/apiClient.js'

export default function usePropertySummary(load, propertyId) {
  const [attempt, setAttempt] = useState(0)
  const [state, setState] = useState(null)

  useEffect(() => {
    if (!propertyId) return undefined
    let active = true

    async function fetchSummary() {
      try {
        const data = await load(propertyId)
        if (!Array.isArray(data) || data.some((item) =>
          !item || typeof item.id !== 'string' || !item.id.trim() || !Number.isInteger(item.status) ||
          typeof item.propertyId !== 'string' || item.propertyId.toLowerCase() !== propertyId.toLowerCase()) ||
          new Set(data.map((item) => item.id.toLowerCase())).size !== data.length) {
          throw new ApiError('The service returned an invalid summary. Please try again.')
        }
        if (active) setState({ propertyId, attempt, status: 'ready', data })
      } catch (error) {
        if (active) setState({
          propertyId, attempt, status: 'error', data: [],
          message: error instanceof ApiError ? error.message : 'Unable to load this summary. Please try again.',
        })
      }
    }

    fetchSummary()
    return () => { active = false }
  }, [load, propertyId, attempt])

  // Hide previous data immediately when the property changes, before effects run.
  // DashboardPage also remounts this dashboard when the authenticated user changes.
  const current = !propertyId
    ? { status: 'property-required', data: [] }
    : state?.propertyId === propertyId && state.attempt === attempt
      ? state
      : { status: 'loading', data: [] }

  return { ...current, retry: () => setAttempt((value) => value + 1) }
}
