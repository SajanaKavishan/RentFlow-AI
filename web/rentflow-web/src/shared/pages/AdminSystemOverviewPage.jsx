import { StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import './admin-system-overview.css'

function PendingBadge() {
  return <StatusBadge tone="warning"><span className="admin-system-section__badge-dot" aria-hidden="true" />Integration pending</StatusBadge>
}

export default function AdminSystemOverviewPage() {
  return <main className="shared-page admin-system-page">
    <header className="admin-system-page__header">
      <div className="admin-system-page__intro">
        <h1>AI / System Monitoring Platform</h1>
        <p>Monitor AI workflows and system reporting as authorized integrations become available.</p>
      </div>
    </header>

    <div className="admin-system-page__sections">
      <section className="shared-card admin-system-section" aria-labelledby="admin-ai-workflows-title">
        <header className="admin-system-section__header">
          <span className="admin-system-section__icon"><Icon name="trend" size={27} /></span>
          <div className="admin-system-section__copy">
            <p className="admin-system-page__eyebrow">Monitoring workspace</p>
            <h2 id="admin-ai-workflows-title">AI Workflows</h2>
            <p>System-wide workflow reporting requires an Admin-authorized aggregate API. Connect an approved source to review reportable workflow information here.</p>
          </div>
          <PendingBadge />
        </header>

        <div className="admin-system-section__pending" role="status">
          <span className="admin-system-section__pending-icon"><Icon name="document" size={22} /></span>
          <div>
            <h3>Aggregate workflow reporting</h3>
            <p>This area will remain intentionally unpopulated until an authorized aggregate reporting integration is available. No validation outcomes, workflow totals or activity records are shown without that source.</p>
          </div>
        </div>
      </section>

      <section className="shared-card admin-system-section" aria-labelledby="admin-system-health-title">
        <header className="admin-system-section__header">
          <span className="admin-system-section__icon"><Icon name="devices" size={27} /></span>
          <div className="admin-system-section__copy">
            <p className="admin-system-page__eyebrow">Platform reporting</p>
            <h2 id="admin-system-health-title">System Health</h2>
            <p>Authoritative service-health data requires a supported monitoring API. Connect an approved monitoring source to surface verified service reporting.</p>
          </div>
          <PendingBadge />
        </header>

        <div className="admin-system-section__pending" role="status">
          <span className="admin-system-section__pending-icon"><Icon name="refresh" size={22} /></span>
          <div>
            <h3>Health reporting pending</h3>
            <p>Verified service-health information will appear here only after an authorized monitoring integration is connected. No service statuses, uptime or latency measurements are inferred.</p>
          </div>
        </div>
      </section>
    </div>
  </main>
}
