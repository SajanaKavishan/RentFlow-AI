import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { useAuth } from '../useAuth.js'

export default function ProtectedRoute({ allowedRoles }) {
  const { isAuthenticated, isLoading, user } = useAuth()
  const location = useLocation()
  if (isLoading) return <div className="auth-restoring" role="status"><span className="shared-spinner" aria-hidden="true" />Restoring your session&hellip;</div>
  if (!isAuthenticated) return <Navigate to="/login" replace state={{ from: location }} />
  if (allowedRoles && !allowedRoles.includes(user.role)) return <Navigate to="/unauthorized" replace />
  return <Outlet />
}
