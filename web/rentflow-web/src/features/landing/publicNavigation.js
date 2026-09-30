import { USER_ROLES } from '../auth/authModel.js'

export const PUBLIC_PATHS = Object.freeze({
  home: '/',
  platform: '/platform',
  getStarted: '/get-started',
  howItWorks: '/how-it-works',
  smartAssistance: '/smart-assistance',
  login: '/login',
})

const roleWorkspacePaths = Object.freeze({
  [USER_ROLES.TENANT]: '/modules/properties',
  [USER_ROLES.LANDLORD]: '/dashboard',
  [USER_ROLES.MAINTENANCE_TECHNICIAN]: '/modules/assigned-work',
  [USER_ROLES.ADMIN]: '/dashboard',
})

const roleHeroActions = Object.freeze({
  [USER_ROLES.TENANT]: [
    { label: 'Browse Properties', path: '/modules/properties', primary: true },
    { label: 'My Dashboard', path: '/dashboard' },
  ],
  [USER_ROLES.LANDLORD]: [
    { label: 'Manage Properties', path: '/modules/manage-properties', primary: true },
    { label: 'Dashboard', path: '/dashboard' },
  ],
  [USER_ROLES.MAINTENANCE_TECHNICIAN]: [
    { label: 'View Assigned Work', path: '/modules/assigned-work', primary: true },
    { label: 'Dashboard', path: '/dashboard' },
  ],
  [USER_ROLES.ADMIN]: [
    { label: 'Open Admin Dashboard', path: '/dashboard', primary: true },
  ],
})

export const PUBLIC_NAVIGATION_LINKS = Object.freeze([
  { label: 'Platform', path: PUBLIC_PATHS.platform },
  { label: 'How It Works', path: PUBLIC_PATHS.howItWorks },
  { label: 'Smart Assistance', path: PUBLIC_PATHS.smartAssistance },
])

export function explorePathForSession(isAuthenticated, role) {
  if (!isAuthenticated) return PUBLIC_PATHS.platform
  return roleWorkspacePaths[role] || '/dashboard'
}

export function heroActionsForSession(isAuthenticated, role) {
  if (!isAuthenticated) {
    return [
      { label: 'Get Started', path: PUBLIC_PATHS.getStarted, primary: true },
      { label: 'Explore the platform', path: explorePathForSession(false) },
    ]
  }

  return roleHeroActions[role] || [
    { label: 'Continue to Dashboard', path: '/dashboard', primary: true },
  ]
}

