import { useEffect, useState } from 'react'
import { getLandlordLeases } from '../../features/leaseAgreements/services/leaseAgreementApiService.js'

export default function useDashboardLeases(propertyIds) {
  const scopeKey = propertyIds === null ? null : propertyIds.map((id) => id.toLowerCase()).sort().join(',')
  const [attempt, setAttempt] = useState(0)
  const [state, setState] = useState(null)
  useEffect(() => {
    if (!scopeKey) return undefined
    let active = true
    getLandlordLeases().then((leases) => {
      if (!Array.isArray(leases) || leases.some((lease) => !lease ||
        typeof lease.id !== 'string' || !lease.id.trim() || typeof lease.propertyId !== 'string' ||
        ![0, 1, 2, 3].includes(lease.status) || !/^\d{4}-\d{2}-\d{2}$/.test(lease.endDate) ||
        !Number.isFinite(Date.parse(`${lease.endDate}T00:00:00Z`))) ||
        new Set(leases.map((lease) => lease.id.toLowerCase())).size !== leases.length) {
        throw new Error('Invalid lease summary')
      }
      const ids = new Set(scopeKey.split(','))
      if (active) setState({ scopeKey, attempt, status: 'ready', data: leases.filter((lease) => ids.has(lease.propertyId.toLowerCase())) })
    }).catch(() => {
      if (active) setState({ scopeKey, attempt, status: 'error', data: [] })
    })
    return () => { active = false }
  }, [scopeKey, attempt])
  const current = scopeKey === '' ? { status: 'ready', data: [] }
    : state?.scopeKey === scopeKey && state?.attempt === attempt ? state : { status: 'loading', data: [] }
  return { ...current, retry: () => setAttempt((value) => value + 1) }
}

export function renewalDays(lease, now = new Date()) {
  const parts = new Intl.DateTimeFormat('en', {
    timeZone: 'Asia/Colombo', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(now)
  const date = Object.fromEntries(parts.map(({ type, value }) => [type, value]))
  const today = Date.parse(`${date.year}-${date.month}-${date.day}T00:00:00Z`)
  return Math.round((Date.parse(`${lease.endDate}T00:00:00Z`) - today) / 86400000)
}
