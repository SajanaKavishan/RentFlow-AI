import { useCallback, useEffect, useState } from 'react'
import { getMaintenanceRequestById, getTechnicianMaintenanceRequests } from '../../features/maintenance/services/maintenanceApiService.js'

export default function useTechnicianWork(userId) {
  const [result, setResult] = useState({ status: 'loading', requests: [], error: '' })
  const [revision, setRevision] = useState(0)
  const retry = useCallback(() => setRevision((value) => value + 1), [])
  useEffect(() => {
    let active = true
    async function load() {
      try {
        if (!userId) throw new Error('Your technician account could not be identified.')
        const queue = await getTechnicianMaintenanceRequests(userId)
        // The list DTO omits completion dates. Read the existing authorized detail endpoint.
        const requests = await Promise.all(queue.map(async (item) => {
          if (item.status !== 'Completed' || item.completedAt) return item
          try { return { ...item, ...await getMaintenanceRequestById(item.id) } }
          catch { return item }
        }))
        if (active) setResult({ status: 'ready', requests, error: '' })
      } catch (error) {
        if (active) setResult({ status: 'error', requests: [], error: error.message || 'Unable to load your work.' })
      }
    }
    void load()
    return () => { active = false }
  }, [userId, revision])
  return { ...result, retry }
}
