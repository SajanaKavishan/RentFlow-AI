import { useEffect, useState } from 'react'

function parseCounts(rows, countField) {
  if (!Array.isArray(rows) || rows.some((row) => !row
    || typeof row.propertyId !== 'string' || !row.propertyId.trim()
    || !Number.isSafeInteger(row[countField]) || row[countField] < 0)
    || new Set(rows.map((row) => row.propertyId.toLowerCase())).size !== rows.length) {
    throw new TypeError('Invalid property count summary')
  }
  return new Map(rows.map((row) => [row.propertyId.toLowerCase(), row[countField]]))
}

export default function usePropertyCountSummary(loadSummary, countField, refreshKey = 0) {
  const [attempt, setAttempt] = useState(0)
  const [result, setResult] = useState(null)
  const counts = result?.attempt === attempt && result.refreshKey === refreshKey
    ? result : { status: 'loading' }
  useEffect(() => {
    let active = true
    loadSummary().then((rows) => {
      const values = parseCounts(rows, countField)
      if (active) setResult({ attempt, refreshKey, status: 'ready', values })
    }).catch(() => {
      if (active) setResult({ attempt, refreshKey, status: 'error' })
    })
    return () => { active = false }
  }, [attempt, countField, loadSummary, refreshKey])
  return { ...counts, retry: () => setAttempt((value) => value + 1) }
}
