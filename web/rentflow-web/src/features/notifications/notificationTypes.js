export const SUPPORTED_NOTIFICATION_TYPES = Object.freeze([
  { value: 'viewing.created', label: 'Viewing request created' },
  { value: 'viewing.approved', label: 'Viewing approved' },
  { value: 'viewing.rejected', label: 'Viewing rejected' },
  { value: 'rental_application.submitted', label: 'Application submitted' },
  { value: 'rental_application.resubmitted', label: 'Application resubmitted' },
  { value: 'rental_application.approved', label: 'Application approved' },
  { value: 'rental_application.rejected', label: 'Application rejected' },
  { value: 'rental_application.changes_requested', label: 'Application changes requested' },
])

const labels = new Map(SUPPORTED_NOTIFICATION_TYPES.map((type) => [type.value, type.label]))

export function notificationTypeLabel(eventType) {
  return labels.get(eventType) || 'Account update'
}

