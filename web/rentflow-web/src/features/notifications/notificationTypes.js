export const SUPPORTED_NOTIFICATION_TYPES = Object.freeze([
  { value: 'maintenance_request.submitted', label: 'Maintenance triage required' },
  { value: 'maintenance_request.triaged', label: 'Technician assignment required' },
  { value: 'maintenance_request.estimate_preparation', label: 'Estimate preparation required' },
  { value: 'maintenance_request.estimate_review', label: 'Repair estimate review' },
  { value: 'maintenance_request.coordination_review', label: 'Maintenance AI review' },
  { value: 'rental_offer.accepted', label: 'Lease creation required' },
  { value: 'lease.activation_required', label: 'Lease activation required' },
  { value: 'payment.manual_review', label: 'Manual payment review' },
  { value: 'viewing.created', label: 'Viewing request created' },
  { value: 'viewing.approved', label: 'Viewing approved' },
  { value: 'viewing.rejected', label: 'Viewing rejected' },
  { value: 'rental_application.submitted', label: 'Application submitted' },
  { value: 'rental_application.resubmitted', label: 'Application resubmitted' },
  { value: 'rental_application.approved', label: 'Application approved' },
  { value: 'rental_application.rejected', label: 'Application rejected' },
  { value: 'rental_application.changes_requested', label: 'Application changes requested' },
  { value: 'maintenance_technician.activated', label: 'Technician activation' },
  { value: 'maintenance_request.assigned', label: 'Maintenance assignment' },
])

const labels = new Map(SUPPORTED_NOTIFICATION_TYPES.map((type) => [type.value, type.label]))

export function notificationTypeLabel(eventType) {
  return labels.get(eventType) || 'Account update'
}
