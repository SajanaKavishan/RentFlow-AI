import { VIEWING_STATUS } from '../services/viewingApiService.js'

const STATUS_DETAILS = {
  [VIEWING_STATUS.PENDING]: { label: 'Pending', tone: 'pending' },
  [VIEWING_STATUS.APPROVED]: { label: 'Approved', tone: 'approved' },
  [VIEWING_STATUS.REJECTED]: { label: 'Rejected', tone: 'rejected' },
  [VIEWING_STATUS.CANCELLED]: { label: 'Cancelled', tone: 'cancelled' },
  [VIEWING_STATUS.COMPLETED]: { label: 'Completed', tone: 'completed' },
}

function ViewingStatusBadge({ status }) {
  const details = STATUS_DETAILS[status] ?? {
    label: 'Unknown',
    tone: 'unknown',
  }

  return (
    <span className={`viewing-status viewing-status--${details.tone}`}>
      {details.label}
    </span>
  )
}

export default ViewingStatusBadge
