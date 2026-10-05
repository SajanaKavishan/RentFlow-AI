import { useEffect, useState } from 'react'
import { getLandlordPayments } from '../../features/payments/services/paymentApiService.js'

export default function useLandlordRevenue(propertyIds) {
  const scopeKey = propertyIds === null ? null : propertyIds.map((id) => id.toLowerCase()).sort().join(',')
  const [attempt, setAttempt] = useState(0)
  const [state, setState] = useState(null)

  useEffect(() => {
    if (!scopeKey) return undefined
    let active = true
    getLandlordPayments().then((payments) => {
      if (!Array.isArray(payments) || payments.some((payment) =>
        !payment || typeof payment.id !== 'string' || !payment.id.trim() ||
        typeof payment.propertyId !== 'string' || !payment.propertyId.trim() ||
        ![0, 1, 2].includes(payment.status) ||
        typeof payment.amount !== 'number' || !Number.isFinite(payment.amount) || payment.amount < 0 ||
        (payment.status === 1 && !Number.isFinite(Date.parse(payment.paidAt)))) ||
        new Set(payments.map((payment) => payment.id.toLowerCase())).size !== payments.length) {
        throw new Error('Invalid payment summary')
      }
      const ids = new Set(scopeKey.split(','))
      const data = payments.filter((payment) => ids.has(payment.propertyId.toLowerCase()))
      if (active) setState({ scopeKey, attempt, status: 'ready', data })
    }).catch(() => {
      if (active) setState({ scopeKey, attempt, status: 'error', data: [] })
    })
    return () => { active = false }
  }, [scopeKey, attempt])

  const current = scopeKey === '' ? { status: 'ready', data: [] }
    : state?.scopeKey === scopeKey && state?.attempt === attempt ? state
      : { status: 'loading', data: [] }
  return { ...current, retry: () => setAttempt((value) => value + 1) }
}

export function monthlyRevenue(payments, now = new Date()) {
  const month = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Colombo', year: 'numeric', month: '2-digit',
  })
  return payments.filter((payment) => payment.status === 1 &&
    month.format(new Date(payment.paidAt)) === month.format(now))
    .reduce((total, payment) => total + payment.amount, 0)
}
