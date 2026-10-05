import { USER_ROLES } from '../../features/auth/authModel.js'

const ALL = Object.values(USER_ROLES)

const T = USER_ROLES.TENANT
const L = USER_ROLES.LANDLORD
const M = USER_ROLES.MAINTENANCE_TECHNICIAN
const A = USER_ROLES.ADMIN

// Availability is explicit: only shipped routes are marked available.
export const NAV_ITEMS = Object.freeze([
  {
    id: 'dashboard',
    label: 'Dashboard',
    path: '/dashboard',
    roles: ALL,
    available: true,
  },

  // =========================================================
  // PROPERTY & LISTING MANAGEMENT
  // =========================================================

  {
    id: 'properties',
    label: 'Properties',
    path: '/modules/properties',
    roles: [T],
    available: true,
    owner: 'Property management',
    description: 'Browse and search available rental properties.',
  },

  {
    id: 'manage-properties',
    label: 'Manage Properties',
    path: '/modules/manage-properties',
    roles: [L],
    available: true,
    owner: 'Property management',
    description: 'Create, edit and manage your rental properties.',
  },

  // =========================================================
  // TENANT
  // =========================================================

  {
    id: 'my-viewings',
    label: 'My Viewings',
    path: '/modules/my-viewings',
    roles: [T],
    available: true,
  },

  {
    id: 'my-applications',
    label: 'My Applications',
    path: '/modules/my-applications',
    roles: [T],
    available: true,
  },

  // =========================================================
  // LANDLORD
  // =========================================================

  {
    id: 'viewing-requests',
    label: 'Viewing Requests',
    path: '/viewing-requests',
    roles: [L],
    available: true,
  },

  {
    id: 'rental-applications',
    label: 'Rental Applications',
    path: '/rental-applications',
    roles: [L],
    available: true,
  },

  {
    id: 'ai-review',
    label: 'AI Review',
    path: '/ai-review',
    roles: [L],
    available: true,
    note: 'Application validation and document review',
  },
  {
    id: 'reviews',
    label: 'Reviews',
    path: '/modules/reviews',
    roles: [L],
    available: true,
  },

  // =========================================================
  // LEASE / PAYMENT / MAINTENANCE
  // =========================================================

  {
    id: 'lease-payments',
    label: 'Lease & Payments',
    path: '/modules/lease-payments',
    roles: [T],
    available: true,
    owner: 'Lease and payment management',
    description: 'Review your offers, leases, rent schedules and payments.',
  },

  {
    id: 'tenant-maintenance',
    label: 'Maintenance',
    path: '/modules/maintenance',
    roles: [T],
    available: true,
    owner: 'Maintenance',
    description: 'Create maintenance requests and track their progress.',
  },

  {
    id: 'pricing-lease',
    label: 'Pricing / Lease',
    path: '/modules/pricing-lease',
    roles: [L],
    available: true,
    owner: 'Pricing and lease management',
    description: 'Analyze rental prices for your properties.',
  },

  {
    id: 'payments',
    label: 'Payments',
    path: '/modules/payments',
    roles: [L],
    available: true,
    owner: 'Payments',
    description: 'Review and manage payments for your rentals.',
  },

  {
    id: 'maintenance',
    label: 'Maintenance',
    path: '/modules/maintenance/landlord',
    roles: [L],
    available: true,
    owner: 'Maintenance',
    description: 'Review and coordinate maintenance requests for a property.',
  },

  // =========================================================
  // TECHNICIAN
  // =========================================================

  {
    id: 'assigned-work',
    label: 'Assigned Work',
    path: '/modules/assigned-work',
    roles: [M],
    available: true,
    owner: 'Maintenance',
    description: 'Review assigned maintenance requests and update work status.',
  },

  // =========================================================
  // ADMIN
  // =========================================================

  {
    id: 'users',
    label: 'Users',
    path: '/modules/users',
    roles: [A],
    available: true,
    owner: 'Administration',
    description:
      'The Admin Users workspace is available while its authorized directory contract awaits integration.',
  },

  {
    id: 'support-requests',
    label: 'Support Requests',
    path: '/modules/support-requests',
    roles: [A],
    available: true,
    owner: 'Administration',
    description: 'Review and update authenticated user support requests.',
  },

  {
    id: 'ai-system-overview',
    label: 'AI / System Overview',
    path: '/modules/ai-system-overview',
    roles: [A],
    available: true,
    owner: 'Administration',
    description:
      'The Admin overview workspace is available while its aggregate reporting contract awaits integration.',
  },

  // =========================================================
  // SHARED
  // =========================================================

  {
    id: 'profile',
    label: 'Profile',
    path: '/profile',
    roles: ALL,
    available: true,
  },
])

export function navigationForRole(role) {
  return NAV_ITEMS.filter((item) => item.roles.includes(role))
}

export function navigationItemForPath(role, path) {
  return navigationForRole(role).find((item) => item.path === path)
}
