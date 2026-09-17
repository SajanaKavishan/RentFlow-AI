import { RENTAL_APPLICATION_STATUS } from '../services/rentalApplicationApiService.js'

const STATUS_DETAILS = {
  [RENTAL_APPLICATION_STATUS.DRAFT]: { label: 'Draft', tone: 'draft' },
  [RENTAL_APPLICATION_STATUS.SUBMITTED]: {
    label: 'Submitted',
    tone: 'submitted',
  },
  [RENTAL_APPLICATION_STATUS.UNDER_REVIEW]: {
    label: 'Under review',
    tone: 'review',
  },
  [RENTAL_APPLICATION_STATUS.CHANGES_REQUESTED]: {
    label: 'Changes requested',
    tone: 'changes',
  },
  [RENTAL_APPLICATION_STATUS.APPROVED]: {
    label: 'Approved',
    tone: 'approved',
  },
  [RENTAL_APPLICATION_STATUS.REJECTED]: {
    label: 'Rejected',
    tone: 'rejected',
  },
  [RENTAL_APPLICATION_STATUS.WITHDRAWN]: {
    label: 'Withdrawn',
    tone: 'withdrawn',
  },
}

function RentalApplicationStatusBadge({ status }) {
  const details = STATUS_DETAILS[status] || {
    label: 'Unknown',
    tone: 'neutral',
  }

  return (
    <span
      className={`application-status application-status--${details.tone}`}
      aria-label={`Application status: ${details.label}`}
    >
      <span className="application-status__dot" aria-hidden="true" />
      {details.label}
    </span>
  )
}

export default RentalApplicationStatusBadge
