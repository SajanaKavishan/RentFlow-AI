import { USER_ROLES } from '../../features/auth/authModel.js'

const ALL = Object.values(USER_ROLES)
const T = USER_ROLES.TENANT
const L = USER_ROLES.LANDLORD
const M = USER_ROLES.MAINTENANCE_TECHNICIAN
const A = USER_ROLES.ADMIN

// Availability is explicit: only shipped routes are marked available.
export const NAV_ITEMS = Object.freeze([
  { label: 'Dashboard', path: '/', roles: ALL, available: true },
  { label: 'Properties', path: '/modules/properties', roles: [T, L], available: false },
  { label: 'Viewings', path: '/modules/viewings', roles: [T], available: false },
  { label: 'My Applications', path: '/modules/my-applications', roles: [T], available: false },
  { label: 'Lease / Payments', path: '/modules/lease-payments', roles: [T], available: false },
  { label: 'Maintenance Requests', path: '/modules/maintenance-requests', roles: [T], available: false },
  { label: 'Viewing Requests', path: '/viewing-requests', roles: [L], available: true },
  { label: 'Rental Applications', path: '/rental-applications', roles: [L], available: true },
  { label: 'Pricing / Lease', path: '/modules/pricing-lease', roles: [L], available: false },
  { label: 'Payments', path: '/modules/payments', roles: [L], available: false },
  { label: 'Maintenance', path: '/modules/maintenance', roles: [L], available: false },
  { label: 'AI Review / Validation', path: '/rental-applications', roles: [L], available: true, note: 'Inside Rental Applications' },
  { label: 'Assigned Maintenance', path: '/modules/assigned-maintenance', roles: [M], available: false },
  { label: 'Users', path: '/modules/users', roles: [A], available: false },
  { label: 'Properties Overview', path: '/modules/properties-overview', roles: [A], available: false },
  { label: 'Applications Overview', path: '/modules/applications-overview', roles: [A], available: false },
  { label: 'Payments Overview', path: '/modules/payments-overview', roles: [A], available: false },
  { label: 'Maintenance Overview', path: '/modules/maintenance-overview', roles: [A], available: false },
  { label: 'AI Workflow Monitoring', path: '/modules/ai-monitoring', roles: [A], available: false },
  { label: 'Profile', path: '/profile', roles: ALL, available: true },
])

export function navigationForRole(role) { return NAV_ITEMS.filter((item) => item.roles.includes(role)) }
export function navigationItemForPath(role, path) { return navigationForRole(role).find((item) => item.path === path) }
