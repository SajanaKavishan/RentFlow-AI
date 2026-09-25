import { USER_ROLES } from '../../features/auth/authModel.js'

const ALL = Object.values(USER_ROLES)
const T = USER_ROLES.TENANT
const L = USER_ROLES.LANDLORD
const M = USER_ROLES.MAINTENANCE_TECHNICIAN
const A = USER_ROLES.ADMIN

// Availability is explicit: only shipped routes are marked available.
export const NAV_ITEMS = Object.freeze([
  { id: 'dashboard', label: 'Dashboard', path: '/dashboard', roles: ALL, available: true },
  {
    id: 'properties', label: 'Properties', path: '/modules/properties', roles: [T, L], available: false,
    owner: 'Property management',
    description: 'Property discovery and management will appear here after the property module is integrated.',
  },
  {
    id: 'my-viewings', label: 'My Viewings', path: '/modules/my-viewings', roles: [T], available: true,
  },
  {
    id: 'my-applications', label: 'My Applications', path: '/modules/my-applications', roles: [T], available: true,
  },
  { id: 'viewing-requests', label: 'Viewing Requests', path: '/viewing-requests', roles: [L], available: true },
  { id: 'rental-applications', label: 'Rental Applications', path: '/rental-applications', roles: [L], available: true },
  {
    id: 'ai-review', label: 'AI Review', path: '/ai-review', roles: [L], available: true,
    note: 'Application validation and document review',
  },
  {
    id: 'lease-payments', label: 'Lease & Payments', path: '/modules/lease-payments', roles: [T], available: false,
    owner: 'Lease and payment management',
    description: 'Your lease details and payment schedule will appear here when these features are available.',
  },
  {
    id: 'tenant-maintenance', label: 'Maintenance', path: '/modules/maintenance', roles: [T], available: false,
    owner: 'Maintenance',
    description: 'Maintenance requests and updates will appear here when this feature is available.',
  },
  {
    id: 'pricing-lease', label: 'Pricing / Lease', path: '/modules/pricing-lease', roles: [L], available: false,
    owner: 'Pricing and lease management',
    description: 'Pricing and lease tools will be connected when that module is merged.',
  },
  {
    id: 'payments', label: 'Payments', path: '/modules/payments', roles: [L], available: false,
    owner: 'Payments', description: 'Payment management will be connected when that module is merged.',
  },
  {
    id: 'maintenance', label: 'Maintenance', path: '/modules/maintenance', roles: [L], available: false,
    owner: 'Maintenance', description: 'Maintenance management will be connected when that module is merged.',
  },
  {
    id: 'assigned-work', label: 'Assigned Work', path: '/modules/assigned-work', roles: [M], available: true,
    owner: 'Maintenance',
    description: 'The Technician work area is available while its assigned-work collection awaits Maintenance integration.',
  },
  {
    id: 'users', label: 'Users', path: '/modules/users', roles: [A], available: true,
    owner: 'Administration',
    description: 'The Admin Users workspace is available while its authorized directory contract awaits integration.',
  },
  {
    id: 'support-requests', label: 'Support Requests', path: '/modules/support-requests', roles: [A], available: true,
    owner: 'Administration',
    description: 'Review and update authenticated user support requests.',
  },
  {
    id: 'ai-system-overview', label: 'AI / System Overview', path: '/modules/ai-system-overview', roles: [A], available: true,
    owner: 'Administration',
    description: 'The Admin overview workspace is available while its aggregate reporting contract awaits integration.',
  },
  { id: 'profile', label: 'Profile', path: '/profile', roles: ALL, available: true },
])

export function navigationForRole(role) { return NAV_ITEMS.filter((item) => item.roles.includes(role)) }
export function navigationItemForPath(role, path) { return navigationForRole(role).find((item) => item.path === path) }
