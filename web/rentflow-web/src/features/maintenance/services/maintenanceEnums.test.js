import { describe, expect, it } from 'vitest'
import {
  MAINTENANCE_CATEGORY,
  MAINTENANCE_COORDINATION_APPROVAL_STATUS,
  MAINTENANCE_COORDINATION_STEP_STATUS,
  MAINTENANCE_COORDINATION_WORKFLOW_STATUS,
  MAINTENANCE_PRIORITY,
  MAINTENANCE_STATUS,
  encodeMaintenanceRequest,
  maintenanceEnumLabel,
  normalizeMaintenanceCoordinationWorkflow,
  normalizeMaintenanceRequest,
} from './maintenanceEnums.js'

describe('maintenance enum API boundary', () => {
  it('decodes backend numeric status, category, and priority values', () => {
    expect(normalizeMaintenanceRequest({
      status: 8,
      category: 0,
      priority: 3,
    })).toMatchObject({
      status: 'InProgress',
      category: 'Plumbing',
      priority: 'Emergency',
    })
  })

  it('encodes tenant request enum names using the backend numeric values', () => {
    expect(encodeMaintenanceRequest({
      category: 'Electrical',
      priority: 'High',
    })).toEqual({ category: 1, priority: 2 })
  })

  it('preserves new category values and API-confirmed access/reference fields', () => {
    expect(encodeMaintenanceRequest({ category: 'Hvac', priority: 'Normal', preferredAccessWindow: 'Morning' }))
      .toEqual({ category: 7, priority: 1, preferredAccessWindow: 'Morning' })
    expect(normalizeMaintenanceRequest({ category: 8, referenceCode: 'MR-0123456789ABCDEF', preferredAccessWindow: 'Evening' }))
      .toMatchObject({ category: 'LocksDoors', referenceCode: 'MR-0123456789ABCDEF', preferredAccessWindow: 'Evening' })
    expect(MAINTENANCE_CATEGORY.byName.Security).toBe(4)
    expect(MAINTENANCE_CATEGORY.byName.Other).toBe(6)
  })

  it('keeps enum labels centralized and rejects invalid request enum names', () => {
    expect(maintenanceEnumLabel(5, MAINTENANCE_STATUS)).toBe('Awaiting Landlord Approval')
    expect(maintenanceEnumLabel(6, MAINTENANCE_CATEGORY)).toBe('Other')
    expect(maintenanceEnumLabel(3, MAINTENANCE_PRIORITY)).toBe('Emergency')
    expect(() => encodeMaintenanceRequest({ category: 'Heating', priority: 'High' })).toThrow(/Invalid maintenance category/)
  })

  it('normalizes numeric maintenance coordination workflow enums', () => {
    expect(normalizeMaintenanceCoordinationWorkflow({
      status: 2,
      approvalStatus: 1,
      steps: [{ status: 3 }],
    })).toEqual({
      status: 'AwaitingHumanReview',
      approvalStatus: 'Pending',
      steps: [{ status: 'Failed' }],
    })
    expect(maintenanceEnumLabel(2, MAINTENANCE_COORDINATION_WORKFLOW_STATUS)).toBe('Awaiting Human Review')
    expect(maintenanceEnumLabel(1, MAINTENANCE_COORDINATION_APPROVAL_STATUS)).toBe('Pending')
    expect(maintenanceEnumLabel(3, MAINTENANCE_COORDINATION_STEP_STATUS)).toBe('Failed')
  })
})
