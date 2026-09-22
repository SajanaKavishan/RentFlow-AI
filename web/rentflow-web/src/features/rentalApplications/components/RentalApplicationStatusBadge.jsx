import { APPLICATION_STATUS_DETAILS } from './applicationStatus.js'

function RentalApplicationStatusBadge({ status }) {
  const details = APPLICATION_STATUS_DETAILS[status] || {
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
