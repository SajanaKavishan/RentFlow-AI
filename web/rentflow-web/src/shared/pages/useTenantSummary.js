import { useEffect, useState } from 'react'

// Each summary can succeed or retry independently. Ignore responses after a
// route/session change; DashboardPage keys the tenant view by authenticated ID.
export default function useTenantSummary(load) {
  const [attempt, setAttempt] = useState(0)
  const [state, setState] = useState({ status: 'loading', data: [] })

  useEffect(() => {
    let active = true
    async function fetchSummary() {
      try {
        const data = await load()
        if (!Array.isArray(data) || data.some((item) => !item || typeof item !== 'object' || Array.isArray(item))) {
          throw new Error('The service returned an invalid summary. Please try again.')
        }
        if (active) setState({ status: 'ready', data, loadedAt: Date.now() })
      } catch (error) {
        if (active) setState({ status: 'error', data: [], message: error.message })
      }
    }
    fetchSummary()
    return () => { active = false }
  }, [load, attempt])

  return {
    ...state,
    retry() {
      setState({ status: 'loading', data: [] })
      setAttempt((value) => value + 1)
    },
  }
}
