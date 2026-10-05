import { useEffect, useState } from 'react'
import { getApplicationEligibility } from './services/rentalApplicationApiService.js'

export function useApplicationEligibility(propertyId, enabled = true, refreshVersion = 0) {
  const [loaded, setLoaded] = useState({ propertyId: null, data: null, error: '', loading: true })
  useEffect(() => {
    if (!enabled || !propertyId) return undefined
    let active = true
    let version = 0
    const refresh = async () => {
      const request = ++version
      setLoaded({ propertyId, data: null, error: '', loading: true })
      try {
        const data = await getApplicationEligibility(propertyId)
        if (active && request === version) setLoaded({ propertyId, data, error: '', loading: false })
      } catch {
        if (active && request === version) setLoaded({ propertyId, data: null, error: 'Unable to check application eligibility. Please try again.', loading: false })
      }
    }
    const onVisible = () => { if (document.visibilityState === 'visible') refresh() }
    refresh()
    window.addEventListener('focus', refresh)
    document.addEventListener('visibilitychange', onVisible)
    return () => { active = false; window.removeEventListener('focus', refresh); document.removeEventListener('visibilitychange', onVisible) }
  }, [propertyId, enabled, refreshVersion])
  return enabled && loaded.propertyId === propertyId ? loaded : { data: null, error: '', loading: true }
}
