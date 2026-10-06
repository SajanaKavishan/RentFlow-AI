import { useAuth } from '../../features/auth/useAuth.js'
import AdminReportingPanel from './AdminReportingPanels.jsx'
import './admin-system-overview.css'

export default function AdminSystemOverviewPage() {
  const { user } = useAuth()
  return <main className="shared-page admin-system-page">
    <header className="admin-system-page__header">
      <div className="admin-system-page__intro">
        <h1>AI / System Monitoring Platform</h1>
        <p>Recorded workflow runs and current service connectivity across RentFlow.</p>
      </div>
    </header>
    <div className="admin-system-page__sections">
      <AdminReportingPanel kind="workflows" identityKey={user?.id || ''} />
      <AdminReportingPanel kind="health" identityKey={user?.id || ''} />
    </div>
  </main>
}
