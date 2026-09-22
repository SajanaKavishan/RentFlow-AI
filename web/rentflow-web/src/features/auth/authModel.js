export const USER_ROLES = Object.freeze({
  TENANT: 'Tenant',
  LANDLORD: 'Landlord',
  MAINTENANCE_TECHNICIAN: 'MaintenanceTechnician',
  ADMIN: 'Admin',
})
export const PUBLIC_REGISTRATION_ROLES = Object.freeze([
  USER_ROLES.TENANT,
  USER_ROLES.LANDLORD,
])
const supportedRoles = new Set(Object.values(USER_ROLES))
const authenticatedHomes = Object.freeze(Object.fromEntries(
  Object.values(USER_ROLES).map((role) => [role, '/dashboard']),
))

export function authenticatedHomePathForRole(role) {
  return authenticatedHomes[role] || '/dashboard'
}

export function parseCurrentUser(value) {
  if (!value || typeof value.id !== 'string' || typeof value.fullName !== 'string' ||
      typeof value.email !== 'string' || typeof value.phoneNumber !== 'string' ||
      !supportedRoles.has(value.role)) {
    throw new TypeError('The server returned an unsupported user profile.')
  }
  return { id: value.id, fullName: value.fullName, email: value.email,
    phoneNumber: value.phoneNumber, role: value.role }
}
