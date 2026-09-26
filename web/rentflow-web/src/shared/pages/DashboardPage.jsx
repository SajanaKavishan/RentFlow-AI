import { useAuth } from '../../features/auth/useAuth.js'
import { USER_ROLES } from '../../features/auth/authModel.js'
import TenantDashboard from './TenantDashboard.jsx'
import LandlordDashboard from './LandlordDashboard.jsx'
import TechnicianDashboard from './TechnicianDashboard.jsx'
import AdminDashboard from './AdminDashboard.jsx'
import OwnedPropertiesProvider from '../property/OwnedPropertiesProvider.jsx'

export default function DashboardPage() {
  const { user } = useAuth()
  if (user.role === USER_ROLES.TENANT) return <TenantDashboard key={user.id} user={user} />
  if (user.role === USER_ROLES.LANDLORD) return <OwnedPropertiesProvider key={user.id}><LandlordDashboard user={user} /></OwnedPropertiesProvider>
  if (user.role === USER_ROLES.MAINTENANCE_TECHNICIAN) return <TechnicianDashboard key={user.id} user={user} />
  if (user.role === USER_ROLES.ADMIN) return <AdminDashboard key={user.id} user={user} />
  return null
}
