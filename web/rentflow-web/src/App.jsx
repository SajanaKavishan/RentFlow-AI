import { Link, Navigate, Route, Routes } from 'react-router-dom'
import './App.css'
import { useAuth } from './features/auth/useAuth.js'
import ProtectedRoute from './features/auth/components/ProtectedRoute.jsx'
import LoginPage from './features/auth/pages/LoginPage.jsx'
import RegisterPage from './features/auth/pages/RegisterPage.jsx'
import { USER_ROLES } from './features/auth/authModel.js'
import RentalApplicationsPage from './features/rentalApplications/pages/RentalApplicationsPage.jsx'
import ViewingRequestsPage from './features/viewings/pages/ViewingRequestsPage.jsx'

function Navigation() {
  const { isAuthenticated, logout, user } = useAuth()
  return <nav className="app-nav" aria-label="Primary navigation">
    <Link className="app-brand" to="/"><span aria-hidden="true">R</span>RentFlow</Link>
    <div className="app-nav__current">
      {isAuthenticated ? <>
        {user.role === USER_ROLES.LANDLORD && <div className="app-nav__links">
          <Link to="/viewing-requests">Viewing requests</Link>
          <Link to="/rental-applications">Rental applications</Link>
        </div>}
        <span className="app-user" title={user.email}>{user.fullName} · {user.role}</span>
        <button className="app-nav__button" type="button" onClick={logout}>Logout</button>
      </> : <div className="app-nav__links"><Link to="/login">Login</Link><Link to="/register">Register</Link></div>}
    </div>
  </nav>
}

function HomePage() {
  const { user } = useAuth()
  if (user.role === USER_ROLES.LANDLORD) return <Navigate to="/viewing-requests" replace />
  return <main className="role-landing"><h1>Welcome, {user.fullName}</h1>
    <p>{user.role === USER_ROLES.TENANT
      ? 'Tenant workflows are available in the RentFlow mobile app.'
      : 'Your account is signed in. No web workflows are assigned to this role yet.'}</p>
  </main>
}

function UnauthorizedPage() {
  return <main className="role-landing"><h1>Not accessible</h1>
    <p>Your account does not have access to this area.</p><Link to="/">Return home</Link></main>
}

export default function App() {
  const { isLoading } = useAuth()
  if (isLoading) return <main className="auth-restoring" aria-live="polite">
    <span className="loading-spinner" aria-hidden="true" /><p>Restoring your session…</p>
  </main>
  return <div className="app-shell"><Navigation /><Routes>
    <Route path="/login" element={<LoginPage />} />
    <Route path="/register" element={<RegisterPage />} />
    <Route element={<ProtectedRoute />}>
      <Route path="/" element={<HomePage />} />
      <Route path="/unauthorized" element={<UnauthorizedPage />} />
    </Route>
    <Route element={<ProtectedRoute allowedRoles={[USER_ROLES.LANDLORD]} />}>
      <Route path="/viewing-requests" element={<ViewingRequestsPage />} />
      <Route path="/rental-applications" element={<RentalApplicationsPage />} />
    </Route>
    <Route path="*" element={<Navigate to="/" replace />} />
  </Routes></div>
}
