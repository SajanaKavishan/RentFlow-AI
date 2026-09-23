import { Link } from 'react-router-dom'
import { StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import './admin-system-overview.css'

export default function AdminSystemOverviewPage() {
  return <main className="shared-page admin-system-page">
    <header className="admin-system-page__header">
      <div>
        <p className="admin-system-page__eyebrow">Administration workspace</p>
        <h1>AI &amp; System Overview</h1>
        <p>Review the integration status of authorized AI activity and system reporting for RentFlow AI.</p>
      </div>
      <div className="admin-system-page__header-actions" aria-label="AI and System Overview navigation">
        <Link className="shared-button shared-button--outline" to="/dashboard"><Icon name="home" size={18} />Back to dashboard</Link>
        <Link className="shared-button" to="/notifications" aria-label="Open notification inbox"><Icon name="bell" size={18} />Notifications</Link>
      </div>
    </header>

    <div className="admin-system-page__layout">
      <section className="shared-card admin-system-workspace" aria-labelledby="admin-system-monitoring-title">
        <div className="admin-system-workspace__heading">
          <div><p className="admin-system-page__eyebrow">AI and system reporting</p><h2 id="admin-system-monitoring-title">Overview workspace</h2></div>
          <span className="admin-system-workspace__scope"><Icon name="devices" size={17} />Admin-only workspace</span>
        </div>

        <div className="admin-system-integration" role="status">
          <span className="admin-system-page__icon"><Icon name="devices" size={30} /></span>
          <StatusBadge tone="warning">Integration pending</StatusBadge>
          <h3>Aggregate Admin reporting required</h3>
          <p>The backend does not currently expose an Admin-authorized aggregate for system-wide AI activity, validation history, reporting or service status.</p>
          <p>Existing validation APIs require a known rental application or workflow ID, so they are not used to construct an unscoped overview.</p>
          <p>No scores, outcomes, usage metrics, health statuses, charts, activity records or totals are shown without that contract.</p>
        </div>
      </section>

      <aside className="admin-system-page__side" aria-label="AI and system integration details">
        <section className="shared-card admin-system-requirements" aria-labelledby="admin-system-requirements-title">
          <div className="admin-system-requirements__heading"><span className="admin-system-page__icon admin-system-page__icon--small"><Icon name="info" size={21} /></span><div><p className="admin-system-page__eyebrow">Required integration</p><h2 id="admin-system-requirements-title">Before reporting can appear</h2></div></div>
          <ul>
            <li><strong>Admin aggregate endpoint</strong><span>An explicitly Admin-authorized collection or summary contract with defined scope.</span></li>
            <li><strong>Reporting fields</strong><span>Product-owned definitions for permitted AI activity, validation history and reporting data.</span></li>
            <li><strong>Service status contract</strong><span>An authoritative source and status definitions before any system-health presentation is introduced.</span></li>
          </ul>
          <p className="admin-system-requirements__note"><code>/api/rental-applications/&#123;applicationId&#125;/validation-runs</code> and <code>/api/application-validation-workflows/&#123;workflowId&#125;</code> are record-scoped workflows, not Admin overview sources.</p>
        </section>

        <section className="shared-card admin-system-tools" aria-labelledby="admin-system-tools-title">
          <div><p className="admin-system-page__eyebrow">Shared tools</p><h2 id="admin-system-tools-title">Account access</h2></div>
          <Link to="/notifications" aria-label="Open notifications from AI and System Overview"><span className="admin-system-page__icon admin-system-page__icon--small"><Icon name="bell" size={20} /></span><span><strong>Notifications</strong><small>Review updates for your account</small></span><Icon name="arrow" size={17} /></Link>
          <Link to="/profile"><span className="admin-system-page__icon admin-system-page__icon--small"><Icon name="user" size={20} /></span><span><strong>Profile</strong><small>View account details and sign out</small></span><Icon name="arrow" size={17} /></Link>
        </section>
      </aside>
    </div>
  </main>
}
