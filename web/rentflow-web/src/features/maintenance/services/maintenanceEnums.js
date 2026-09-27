const defineEnum = (entries) => {
  const byName = Object.freeze(Object.fromEntries(entries))
  const byValue = Object.freeze(
    Object.fromEntries(entries.map(([name, value]) => [value, name])),
  )
  return Object.freeze({ byName, byValue })
}

export const MAINTENANCE_STATUS = defineEnum([
  ['Submitted', 0],
  ['Triaged', 1],
  ['Assigned', 2],
  ['EstimatePending', 3],
  ['EstimateSubmitted', 4],
  ['AwaitingLandlordApproval', 5],
  ['Approved', 6],
  ['Rejected', 7],
  ['InProgress', 8],
  ['Completed', 9],
  ['Cancelled', 10],
])

export const MAINTENANCE_CATEGORY = defineEnum([
  ['Plumbing', 0],
  ['Electrical', 1],
  ['Appliance', 2],
  ['Structural', 3],
  ['Security', 4],
  ['Pest', 5],
  ['Other', 6],
])

export const MAINTENANCE_PRIORITY = defineEnum([
  ['Low', 0],
  ['Normal', 1],
  ['High', 2],
  ['Emergency', 3],
])

export const MAINTENANCE_COORDINATION_WORKFLOW_STATUS = defineEnum([
  ['Pending', 0],
  ['Running', 1],
  ['AwaitingHumanReview', 2],
  ['Completed', 3],
  ['Failed', 4],
])

export const MAINTENANCE_COORDINATION_APPROVAL_STATUS = defineEnum([
  ['NotRequired', 0],
  ['Pending', 1],
  ['Approved', 2],
  ['Rejected', 3],
])

export const MAINTENANCE_COORDINATION_STEP_STATUS = defineEnum([
  ['Pending', 0],
  ['Running', 1],
  ['Completed', 2],
  ['Failed', 3],
  ['Skipped', 4],
])

function decodeEnum(value, definition) {
  if (typeof value === 'number') return definition.byValue[value] ?? value
  if (typeof value === 'string' && /^\d+$/.test(value)) {
    return definition.byValue[Number(value)] ?? value
  }
  return value
}

function encodeEnum(value, definition, fieldName) {
  if (typeof value === 'number') return value
  const numericValue = definition.byName[value]
  if (numericValue === undefined) {
    throw new TypeError(`Invalid maintenance ${fieldName}: ${value}`)
  }
  return numericValue
}

export function normalizeMaintenanceRequest(request) {
  if (!request || typeof request !== 'object') return request
  return {
    ...request,
    status: decodeEnum(request.status, MAINTENANCE_STATUS),
    category: decodeEnum(request.category, MAINTENANCE_CATEGORY),
    priority: decodeEnum(request.priority, MAINTENANCE_PRIORITY),
  }
}

export function normalizeMaintenanceCoordinationWorkflow(workflow) {
  if (!workflow || typeof workflow !== 'object') return workflow
  return {
    ...workflow,
    status: decodeEnum(workflow.status, MAINTENANCE_COORDINATION_WORKFLOW_STATUS),
    approvalStatus: decodeEnum(workflow.approvalStatus, MAINTENANCE_COORDINATION_APPROVAL_STATUS),
    steps: Array.isArray(workflow.steps)
      ? workflow.steps.map((step) => ({
          ...step,
          status: decodeEnum(step.status, MAINTENANCE_COORDINATION_STEP_STATUS),
        }))
      : workflow.steps,
  }
}

export function encodeMaintenanceRequest(payload) {
  return {
    ...payload,
    category: encodeEnum(payload.category, MAINTENANCE_CATEGORY, 'category'),
    priority: encodeEnum(payload.priority, MAINTENANCE_PRIORITY, 'priority'),
  }
}

export function maintenanceEnumLabel(value, definition) {
  const decoded = decodeEnum(value, definition)
  return typeof decoded === 'string' && decoded
    ? decoded.replace(/([a-z])([A-Z])/g, '$1 $2')
    : String(decoded ?? 'Unknown')
}
