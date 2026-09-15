import { Navigate, Route, Routes } from 'react-router-dom'
import './App.css'
import { useAuth } from './features/auth/useAuth.js'
import ProtectedRoute from './features/auth/components/ProtectedRoute.jsx'
import LoginPage from './features/auth/pages/LoginPage.jsx'
import RegisterPage from './features/auth/pages/RegisterPage.jsx'
import { USER_ROLES } from './features/auth/authModel.js'
import RentalApplicationsPage from './features/rentalApplications/pages/RentalApplicationsPage.jsx'
import ViewingRequestsPage from './features/viewings/pages/ViewingRequestsPage.jsx'
import AppShell from './shared/layout/AppShell.jsx'
import DashboardPage from './shared/pages/DashboardPage.jsx'
import ProfilePage from './shared/pages/ProfilePage.jsx'
import { NotFoundState, UnauthorizedState, UnavailableState } from './shared/ui/States.jsx'

export default function App() {
  const { isLoading } = useAuth()
  if (isLoading) return <div className="auth-restoring" role="status"><span className="shared-spinner" aria-hidden="true" />Restoring your session…</div>
  return <Routes>
    <Route path="/login" element={<LoginPage />} />
    <Route path="/register" element={<RegisterPage />} />
    <Route element={<ProtectedRoute />}>
      <Route element={<AppShell />}>
        <Route path="/" element={<DashboardPage />} />
        <Route path="/profile" element={<ProfilePage />} />
        <Route path="/unauthorized" element={<UnauthorizedState />} />
        <Route element={<ProtectedRoute allowedRoles={[USER_ROLES.LANDLORD]} />}>
          <Route path="/viewing-requests" element={<ViewingRequestsPage />} />
          <Route path="/rental-applications" element={<RentalApplicationsPage />} />
        </Route>
        <Route path="/modules/:module" element={<UnavailableState />} />
        <Route path="*" element={<NotFoundState />} />
      </Route>
    </Route>
    <Route path="*" element={<Navigate to="/login" replace />} />
  </Routes>
}
