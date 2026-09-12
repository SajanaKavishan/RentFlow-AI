import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { useAuth } from '../useAuth.js'

export default function ProtectedRoute({ allowedRoles }) {
  const { isAuthenticated, user } = useAuth()
  const location = useLocation()
  if (!isAuthenticated) return <Navigate to="/login" replace state={{ from: location }} />
  if (allowedRoles && !allowedRoles.includes(user.role)) return <Navigate to="/unauthorized" replace />
  return <Outlet />
}
