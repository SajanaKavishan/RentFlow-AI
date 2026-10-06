import { useCallback, useEffect, useRef, useState } from 'react'
import { apiRequest } from '../../core/api/apiClient.js'

export async function getLandlordActionSummary(signal) {
  const summary = await apiRequest('/api/landlord/actions/summary', { signal, cache: 'no-store', errorMessage: 'Landlord action counts could not be loaded.' })
  const count = (value) => Number.isInteger(value) && value >= 0
  if (!summary || !['maintenanceCount', 'leaseCount', 'paymentCount'].every((key) => count(summary[key])) ||
    !Array.isArray(summary.maintenanceByProperty) || summary.maintenanceByProperty.some((item) => typeof item?.propertyId !== 'string' || !item.propertyId.trim() || !count(item.count)) ||
    new Set(summary.maintenanceByProperty.map((item) => item.propertyId.toLowerCase())).size !== summary.maintenanceByProperty.length ||
    summary.maintenanceByProperty.reduce((total, item) => total + item.count, 0) !== summary.maintenanceCount) throw new Error('Invalid action summary')
  return summary
}

export default function useLandlordActionSummary(user, routeKey) {
  const [state, setState] = useState(null)
  const [attempt, setAttempt] = useState(0)
  const controller = useRef(null)
  const key = `${user.id}:${routeKey}:${attempt}`
  const refresh = useCallback(() => {
    controller.current?.abort()
    setAttempt((value) => value + 1)
  }, [])
  useEffect(() => {
    if (user.role !== 'Landlord') return undefined
    const request = new AbortController()
    controller.current = request
    getLandlordActionSummary(request.signal).then((data) => {
      if (!request.signal.aborted) setState({ key, status: 'ready', data })
    }).catch(() => { if (!request.signal.aborted) setState({ key, status: 'error', data: null }) })
    return () => request.abort()
  }, [key, user.role])
  return { ...(state?.key === key && user.role === 'Landlord' ? state : { status: 'loading', data: null }), refresh }
}
