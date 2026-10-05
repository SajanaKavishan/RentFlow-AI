import { MAINTENANCE_CATEGORY, MAINTENANCE_PRIORITY } from './maintenanceEnums.js'

export const COORDINATION_CATEGORY_LABELS = Object.freeze({
  Plumbing: 'Plumbing', Electrical: 'Electrical', Appliance: 'Appliance',
  Structural: 'Structural', Security: 'Security', Pest: 'Pest', Other: 'Other',
  Hvac: 'HVAC / A/C', LocksDoors: 'Locks / Doors',
})

export const COORDINATION_NEXT_STEPS = Object.freeze({
  triage: { label: 'Review and triage the request', actor: 'Landlord / Admin' },
  'assign-technician': { label: 'Assign a maintenance technician', actor: 'Landlord / Admin' },
  'estimate-pending': { label: 'Request a repair estimate', actor: 'Landlord / Admin' },
  'submit-estimate': { label: 'Technician should submit an estimate', actor: 'Technician' },
  'submit-for-review': { label: 'Submit the estimate for landlord review', actor: 'Technician' },
  'review-estimate': { label: 'Review the submitted estimate', actor: 'Landlord / Admin' },
  'start-work': { label: 'Technician can start approved work', actor: 'Technician' },
  'complete-work': { label: 'Technician can complete the work when finished', actor: 'Technician' },
})

export const COORDINATION_FLAGS = Object.freeze({
  InsufficientInformation: { title: 'More information may be needed', tone: 'attention' },
  CategoryDescriptionMismatch: { title: 'Check the selected category', tone: 'attention' },
  EstimateExplanationMissing: { title: 'The estimate needs more detail', tone: 'attention' },
  EstimateScopeMismatch: { title: 'Check the scope of the estimate', tone: 'attention' },
  PhotoUnavailable: { title: 'Some photo evidence is unavailable', tone: 'neutral' },
  PhotoUnreadable: { title: 'Photo information is unclear', tone: 'neutral' },
  UrgencyNeedsHumanReview: { title: 'Urgency needs human review', tone: 'warning' },
})

const confidenceValues = new Set(['High', 'Medium', 'Low', 'Unknown'])

export function parsePhotoEvidence(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
    Object.keys(value).some((key) => !['suppliedPhotoCount', 'analyzedPhotoCount'].includes(key))) return null
  const { suppliedPhotoCount, analyzedPhotoCount } = value
  if (!Number.isInteger(suppliedPhotoCount) || suppliedPhotoCount < 1 || suppliedPhotoCount > 5 ||
    !Number.isInteger(analyzedPhotoCount) || analyzedPhotoCount < 0 || analyzedPhotoCount > suppliedPhotoCount) return null
  return { suppliedPhotoCount, analyzedPhotoCount }
}
const resultFields = new Set([
  'suggestedCategory', 'categoryConfidence', 'suggestedPriority', 'priorityConfidence',
  'recommendedTechnicianCategory', 'nextAction', 'validationFlags', 'rationale',
  'requiresHumanReview', 'agentVersion', 'decisionDetails',
])
const boundedText = (value, maximum) =>
  typeof value === 'string' && value.trim().length > 0 && value.length <= maximum
const objectValue = (value) => value !== null && typeof value === 'object' && !Array.isArray(value)
const nullableMember = (value, values) => value === null ||
  (typeof value === 'string' && Object.hasOwn(values, value))

// Old/malformed runs are safely unavailable; never display their raw payload or guess a conversion.
export function parseCoordinationResult(workflow, requestId) {
  if (!objectValue(workflow) || !boundedText(workflow.id, 200) ||
      workflow.maintenanceRequestId !== requestId || typeof workflow.finalResultJson !== 'string') return null
  try {
    const result = JSON.parse(workflow.finalResultJson)
    if (!objectValue(result) || Object.keys(result).some((key) => !resultFields.has(key)) ||
        !nullableMember(result.suggestedCategory, MAINTENANCE_CATEGORY.byName) ||
        !nullableMember(result.suggestedPriority, MAINTENANCE_PRIORITY.byName) ||
        !nullableMember(result.recommendedTechnicianCategory, MAINTENANCE_CATEGORY.byName) ||
        !confidenceValues.has(result.categoryConfidence) || !confidenceValues.has(result.priorityConfidence) ||
        !nullableMember(result.nextAction, COORDINATION_NEXT_STEPS) ||
        result.requiresHumanReview !== true || !boundedText(result.rationale, 3000) ||
        !boundedText(result.agentVersion, 100) ||
        !Array.isArray(result.validationFlags) || result.validationFlags.length > 50 ||
        result.validationFlags.some((flag) => !objectValue(flag) ||
          Object.keys(flag).some((key) => !['code', 'message'].includes(key)) ||
          typeof flag.code !== 'string' || !Object.hasOwn(COORDINATION_FLAGS, flag.code) || !boundedText(flag.message, 1000)) ||
        (result.suggestedCategory === null && !['Low', 'Unknown'].includes(result.categoryConfidence)) ||
        (result.suggestedPriority === null && !['Low', 'Unknown'].includes(result.priorityConfidence))) return null
    return result
  } catch {
    return null
  }
}
