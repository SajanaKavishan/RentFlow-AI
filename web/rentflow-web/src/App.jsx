import { Navigate, Route, Routes } from 'react-router-dom'
import './App.css'
import ProtectedRoute from './features/auth/components/ProtectedRoute.jsx'
import LoginPage from './features/auth/pages/LoginPage.jsx'
import RegisterPage from './features/auth/pages/RegisterPage.jsx'
import { USER_ROLES } from './features/auth/authModel.js'
import RentalApplicationsPage from './features/rentalApplications/pages/RentalApplicationsPage.jsx'
import MyApplicationsPage from './features/rentalApplications/pages/MyApplicationsPage.jsx'
import ViewingRequestsPage from './features/viewings/pages/ViewingRequestsPage.jsx'
import MyViewingsPage from './features/viewings/pages/MyViewingsPage.jsx'
import AppShell from './shared/layout/AppShell.jsx'
import DashboardPage from './shared/pages/DashboardPage.jsx'
import TechnicianAssignedWorkPage from './shared/pages/TechnicianAssignedWorkPage.jsx'
import AdminUsersPage from './shared/pages/AdminUsersPage.jsx'
import AdminSystemOverviewPage from './shared/pages/AdminSystemOverviewPage.jsx'
import ProfilePage from './shared/pages/ProfilePage.jsx'
import NotificationsPage from './features/notifications/NotificationsPage.jsx'
import NotificationResourcePage from './features/notifications/NotificationResourcePage.jsx'
import { NotFoundState, UnauthorizedState, UnavailableState } from './shared/ui/States.jsx'
import LandingPage from './features/landing/pages/LandingPage.jsx'

export default function App() {
  return <Routes>
    <Route path="/" element={<LandingPage />} />
    <Route path="/login" element={<LoginPage />} />
    <Route path="/register" element={<RegisterPage />} />
    <Route element={<ProtectedRoute />}>
      <Route element={<AppShell />}>
        <Route path="/dashboard" element={<DashboardPage />} />
        <Route path="/profile" element={<ProfilePage />} />
        <Route path="/notifications" element={<NotificationsPage />} />
        <Route element={<ProtectedRoute allowedRoles={[USER_ROLES.TENANT, USER_ROLES.LANDLORD]} />}>
          <Route path="/notifications/rental-application/:id" element={<NotificationResourcePage resourceType="RentalApplication" />} />
        </Route>
        <Route element={<ProtectedRoute allowedRoles={[USER_ROLES.LANDLORD]} />}>
          <Route path="/notifications/viewing-request/:id" element={<NotificationResourcePage resourceType="ViewingRequest" />} />
        </Route>
        <Route path="/unauthorized" element={<UnauthorizedState />} />
        <Route element={<ProtectedRoute allowedRoles={[USER_ROLES.TENANT]} />}>
          <Route path="/modules/my-viewings" element={<MyViewingsPage />} />
          <Route path="/modules/my-applications" element={<MyApplicationsPage />} />
        </Route>
        <Route element={<ProtectedRoute allowedRoles={[USER_ROLES.MAINTENANCE_TECHNICIAN]} />}>
          <Route path="/modules/assigned-work" element={<TechnicianAssignedWorkPage />} />
        </Route>
        <Route element={<ProtectedRoute allowedRoles={[USER_ROLES.ADMIN]} />}>
          <Route path="/modules/users" element={<AdminUsersPage />} />
          <Route path="/modules/ai-system-overview" element={<AdminSystemOverviewPage />} />
        </Route>
        <Route element={<ProtectedRoute allowedRoles={[USER_ROLES.LANDLORD]} />}>
          <Route path="/viewing-requests" element={<ViewingRequestsPage />} />
          <Route
            path="/properties/:propertyId/viewing-requests"
            element={<ViewingRequestsPage />}
          />
          <Route path="/rental-applications" element={<RentalApplicationsPage />} />
          <Route
            path="/properties/:propertyId/rental-applications"
            element={<RentalApplicationsPage />}
          />
          <Route path="/ai-review" element={<RentalApplicationsPage />} />
          <Route
            path="/properties/:propertyId/ai-review"
            element={<RentalApplicationsPage />}
          />
        </Route>
        <Route path="/modules/:module" element={<UnavailableState />} />
        <Route path="*" element={<NotFoundState />} />
      </Route>
    </Route>
    <Route path="*" element={<Navigate to="/login" replace />} />
  </Routes>
}
