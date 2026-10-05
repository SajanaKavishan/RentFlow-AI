import { Navigate, Route, Routes } from 'react-router-dom'
import './App.css'

import ProtectedRoute from './features/auth/components/ProtectedRoute.jsx'
import LoginPage from './features/auth/pages/LoginPage.jsx'
import ForgotPasswordPage from './features/auth/pages/ForgotPasswordPage.jsx'
import ResetPasswordPage from './features/auth/pages/ResetPasswordPage.jsx'
import RegisterPage from './features/auth/pages/RegisterPage.jsx'
import { USER_ROLES } from './features/auth/authModel.js'
import PasswordSetupPage from './features/staffProvisioning/PasswordSetupPage.jsx'

import RentalApplicationsPage from './features/rentalApplications/pages/RentalApplicationsPage.jsx'
import ApplicationValidationReportPage from './features/rentalApplications/pages/ApplicationValidationReportPage.jsx'
import MyApplicationsPage from './features/rentalApplications/pages/MyApplicationsPage.jsx'
import ViewingRequestsPage from './features/viewings/pages/ViewingRequestsPage.jsx'
import MyViewingsPage from './features/viewings/pages/MyViewingsPage.jsx'
import LandlordMaintenancePage from './features/maintenance/pages/LandlordMaintenancePage.jsx'
import NotificationsPage from './features/notifications/NotificationsPage.jsx'
import NotificationResourcePage from './features/notifications/NotificationResourcePage.jsx'
import PropertiesPage from './features/properties/pages/PropertiesPage.jsx'
import PropertyDetailsPage from './features/properties/pages/PropertyDetailsPage.jsx'
import PublicLandlordProfilePage from './features/properties/pages/PublicLandlordProfilePage.jsx'
import LandlordReviewsPage from './features/properties/pages/LandlordReviewsPage.jsx'
import PropertyMatchingRedirect from './features/properties/pages/PropertyMatchingRedirect.jsx'
import ManagePropertiesPage from './features/properties/pages/ManagePropertiesPage.jsx'
import PropertyFormPage from './features/properties/pages/PropertyFormPage.jsx'
import ViewingAvailabilityPage from './features/properties/pages/ViewingAvailabilityPage.jsx'
import OwnedPropertiesProvider from './shared/property/OwnedPropertiesProvider.jsx'
import PricingAnalysisPage from './features/pricingAnalysis/pages/PricingAnalysisPage.jsx'
import RentalOffersPage from './features/rentalOffers/pages/RentalOffersPage.jsx'
import LeaseAgreementsPage from './features/leaseAgreements/pages/LeaseAgreementsPage.jsx'
import RentSchedulesPage from './features/rentSchedules/pages/RentSchedulesPage.jsx'
import PaymentsPage from './features/payments/pages/PaymentsPage.jsx'
import TenantLeasePaymentsPage from './features/tenantLeasePayments/pages/TenantLeasePaymentsPage.jsx'
import LandingPage from './features/landing/pages/LandingPage.jsx'
import GetStartedPage from './features/landing/pages/GetStartedPage.jsx'
import PlatformOverviewPage from './features/landing/pages/PlatformOverviewPage.jsx'
import HowItWorksPage from './features/landing/pages/HowItWorksPage.jsx'
import SmartAssistancePage from './features/landing/pages/SmartAssistancePage.jsx'

import AppShell from './shared/layout/AppShell.jsx'
import DashboardPage from './shared/pages/DashboardPage.jsx'
import TechnicianAssignedWorkPage from './shared/pages/TechnicianAssignedWorkPage.jsx'
import TechnicianWorkHistoryPage from './shared/pages/TechnicianWorkHistoryPage.jsx'
import AdminUsersPage from './shared/pages/AdminUsersPage.jsx'
import AdminSystemOverviewPage from './shared/pages/AdminSystemOverviewPage.jsx'
import AdminSupportRequestsPage from './shared/pages/AdminSupportRequestsPage.jsx'
import ProfilePage from './shared/pages/ProfilePage.jsx'
import { NotFoundState, UnauthorizedState, UnavailableState } from './shared/ui/States.jsx'

export default function App() {
  return <Routes>
    <Route path="/" element={<LandingPage />} />
    <Route path="/platform" element={<PlatformOverviewPage />} />
    <Route path="/get-started" element={<GetStartedPage />} />
    <Route path="/how-it-works" element={<HowItWorksPage />} />
    <Route path="/smart-assistance" element={<SmartAssistancePage />} />
    <Route path="/login" element={<LoginPage />} />
    <Route path="/forgot-password" element={<ForgotPasswordPage />} />
    <Route path="/reset-password" element={<ResetPasswordPage />} />
    <Route path="/register" element={<RegisterPage />} />
    <Route path="/setup-password" element={<PasswordSetupPage />} />
    <Route element={<ProtectedRoute />}>
      <Route element={<AppShell />}>
        <Route path="/dashboard" element={<DashboardPage />} />
        <Route path="/profile" element={<ProfilePage />} />
        <Route path="/notifications" element={<NotificationsPage />} />
        <Route path="/unauthorized" element={<UnauthorizedState />} />
        <Route path="/properties/:propertyId" element={<PropertyDetailsPage />} />
        <Route element={<ProtectedRoute allowedRoles={[USER_ROLES.LANDLORD, USER_ROLES.ADMIN]} />}>
          <Route path="/properties/:propertyId/viewing-availability" element={<ViewingAvailabilityPage />} />
        </Route>

        <Route element={<ProtectedRoute allowedRoles={[USER_ROLES.TENANT, USER_ROLES.LANDLORD]} />}>
          <Route path="/notifications/rental-application/:id" element={<NotificationResourcePage resourceType="RentalApplication" />} />
        </Route>
        <Route element={<ProtectedRoute allowedRoles={[USER_ROLES.LANDLORD]} />}>
          <Route path="/modules/pricing-lease" element={<PricingAnalysisPage />} />
          <Route path="/modules/pricing-lease/offers" element={<RentalOffersPage />} />
          <Route path="/modules/pricing-lease/leases" element={<LeaseAgreementsPage />} />
          <Route path="/modules/pricing-lease/schedules" element={<RentSchedulesPage />} />
          <Route path="/modules/payments" element={<PaymentsPage />} />
          <Route path="/modules/reviews" element={<LandlordReviewsPage />} />
          <Route path="/notifications/viewing-request/:id" element={<NotificationResourcePage resourceType="ViewingRequest" />} />
        </Route>

        <Route element={<ProtectedRoute allowedRoles={[USER_ROLES.TENANT]} />}>
          <Route path="/properties/:propertyId/landlord" element={<PublicLandlordProfilePage />} />
          <Route path="/modules/lease-payments" element={<TenantLeasePaymentsPage />} />
          <Route path="/modules/my-viewings" element={<MyViewingsPage />} />
          <Route path="/modules/my-applications" element={<MyApplicationsPage />} />
          <Route path="/modules/properties" element={<PropertiesPage />} />
          <Route path="/modules/property-matching" element={<PropertyMatchingRedirect />} />
        </Route>

        <Route element={<ProtectedRoute allowedRoles={[USER_ROLES.MAINTENANCE_TECHNICIAN]} />}>
          <Route path="/modules/assigned-work" element={<TechnicianAssignedWorkPage />} />
          <Route path="/modules/work-history" element={<TechnicianWorkHistoryPage />} />
        </Route>

        <Route element={<ProtectedRoute allowedRoles={[USER_ROLES.ADMIN]} />}>
          <Route path="/modules/users" element={<AdminUsersPage />} />
          <Route path="/modules/support-requests" element={<AdminSupportRequestsPage />} />
          <Route path="/modules/ai-system-overview" element={<AdminSystemOverviewPage />} />
        </Route>
        <Route element={<ProtectedRoute allowedRoles={[USER_ROLES.LANDLORD]} />}>
          <Route path="/modules/manage-properties" element={<ManagePropertiesPage />} />
          <Route path="/properties/new" element={<PropertyFormPage />} />
          <Route path="/properties/:propertyId/edit" element={<PropertyFormPage />} />
          <Route path="/modules/maintenance/landlord" element={<LandlordMaintenancePage />} />
          <Route path="/properties/:propertyId/maintenance" element={<LandlordMaintenancePage />} />
        </Route>
        <Route element={<ProtectedRoute allowedRoles={[USER_ROLES.LANDLORD, USER_ROLES.ADMIN]} />}>
          <Route element={<OwnedPropertiesProvider />}>
            <Route path="/viewing-requests" element={<ViewingRequestsPage />} />
            <Route path="/properties/:propertyId/viewing-requests" element={<ViewingRequestsPage />} />
            <Route path="/rental-applications" element={<RentalApplicationsPage />} />
            <Route path="/properties/:propertyId/rental-applications" element={<RentalApplicationsPage />} />
            <Route path="/properties/:propertyId/rental-applications/:applicationId/validation" element={<ApplicationValidationReportPage />} />
            <Route path="/rental-applications/:applicationId/validation" element={<ApplicationValidationReportPage />} />
            <Route path="/ai-review" element={<RentalApplicationsPage />} />
            <Route path="/properties/:propertyId/ai-review" element={<RentalApplicationsPage />} />
          </Route>
        </Route>

        <Route path="/modules/:module" element={<UnavailableState />} />
        <Route path="*" element={<NotFoundState />} />
      </Route>
    </Route>
    <Route path="*" element={<Navigate to="/login" replace />} />
  </Routes>
}
