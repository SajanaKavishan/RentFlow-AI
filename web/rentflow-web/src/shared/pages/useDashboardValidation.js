import { useEffect, useState } from 'react'
import { getApplicationValidationRuns } from '../../features/rentalApplications/services/applicationValidationApiService.js'
import { RENTAL_APPLICATION_STATUS } from '../../features/rentalApplications/services/rentalApplicationApiService.js'

export function isReviewable(application) {
  return [RENTAL_APPLICATION_STATUS.SUBMITTED, RENTAL_APPLICATION_STATUS.UNDER_REVIEW].includes(application.status)
}

const EMPTY = []
export const WORKFLOW_STATUS = Object.freeze({
  PENDING: 0,
  RUNNING: 1,
  AWAITING_HUMAN_REVIEW: 2,
  COMPLETED: 3,
  FAILED: 4,
})
const ATTENTION_STATUSES = [WORKFLOW_STATUS.AWAITING_HUMAN_REVIEW, WORKFLOW_STATUS.FAILED]

// Only inspect applications returned by the authorized property endpoint. The
// validation endpoint checks application ownership again. Limit request concurrency.
export default function useDashboardValidation(applications) {
  const data = applications.status === 'ready' ? applications.data : EMPTY
  const [result, setResult] = useState(null)
  useEffect(() => {
    const queue = data.filter(isReviewable)
    if (!queue.length) return undefined
    let active = true
    let index = 0
    let unavailable = false
    const attention = []
    async function worker() {
      while (active && index < queue.length) {
        const application = queue[index++]
        try {
          const runs = await getApplicationValidationRuns(application.id)
          if (!Array.isArray(runs) || runs.some((run) => !run || typeof run.id !== 'string' || !run.id.trim() ||
            typeof run.applicationId !== 'string' || run.applicationId.toLowerCase() !== application.id.toLowerCase() ||
            !Object.values(WORKFLOW_STATUS).includes(run.status))) {
            throw new Error('Invalid workflow summary')
          }
          // API returns newest first, matching the existing AI Review screen.
          const latest = runs[0]
          if (latest && ATTENTION_STATUSES.includes(latest.status)) attention.push({ applicationId: application.id, status: latest.status })
        } catch {
          unavailable = true
        }
      }
    }
    Promise.all(Array.from({ length: Math.min(4, queue.length) }, worker)).then(() => {
      if (active) setResult({ data, attention, unavailable })
    })
    return () => { active = false }
  }, [data])

  if (applications.status !== 'ready') return { status: applications.status, attention: [] }
  if (!data.some(isReviewable)) return { status: 'ready', attention: [] }
  if (result?.data !== data) return { status: 'loading', attention: [] }
  return { status: result.unavailable ? 'partial' : 'ready', attention: result.attention }
}
