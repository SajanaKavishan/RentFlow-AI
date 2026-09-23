import { RENTAL_APPLICATION_STATUS } from '../services/rentalApplicationApiService.js'

export const APPLICATION_STATUS_DETAILS = Object.freeze({
  [RENTAL_APPLICATION_STATUS.DRAFT]: { label: 'Draft', tone: 'draft' },
  [RENTAL_APPLICATION_STATUS.SUBMITTED]: { label: 'Submitted', tone: 'submitted' },
  [RENTAL_APPLICATION_STATUS.UNDER_REVIEW]: { label: 'Under review', tone: 'review' },
  [RENTAL_APPLICATION_STATUS.CHANGES_REQUESTED]: { label: 'Changes requested', tone: 'changes' },
  [RENTAL_APPLICATION_STATUS.APPROVED]: { label: 'Approved', tone: 'approved' },
  [RENTAL_APPLICATION_STATUS.REJECTED]: { label: 'Rejected', tone: 'rejected' },
  [RENTAL_APPLICATION_STATUS.WITHDRAWN]: { label: 'Withdrawn', tone: 'withdrawn' },
})
