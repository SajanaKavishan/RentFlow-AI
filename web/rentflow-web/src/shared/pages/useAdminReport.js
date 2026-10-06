import { useEffect, useState } from 'react'
import { getAdminReport } from './adminReportingApi.js'

export default function useAdminReport(kind, identityKey) {
  const [attempt, setAttempt] = useState(0)
  const [state, setState] = useState(null)
  const key = `${identityKey}:${kind}:${attempt}`
  useEffect(() => {
    const controller = new AbortController()
    getAdminReport(kind, controller.signal).then((data) => {
      if (!controller.signal.aborted) setState({ key, status: 'ready', data })
    }).catch(() => {
      if (!controller.signal.aborted) setState({ key, status: 'error', data: null })
    })
    return () => controller.abort()
  }, [key, kind])
  return { ...(state?.key === key ? state : { status: 'loading', data: null }), retry: () => setAttempt((value) => value + 1) }
}
