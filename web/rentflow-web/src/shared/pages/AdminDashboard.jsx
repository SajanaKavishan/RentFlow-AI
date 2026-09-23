import { Link } from 'react-router-dom'
import { StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import DashboardNotificationCard from './DashboardNotificationCard.jsx'
import './role-dashboard.css'

function ManagementPanel({ id, title, description, dependency, path, icon,
  status = 'Integration pending', tone = 'warning', linkLabel = 'View integration status' }) {
  return <section className="shared-card admin-management-card" aria-labelledby={id}>
    <div className="admin-management-card__top"><span className="role-dashboard__icon"><Icon name={icon} size={23} /></span><StatusBadge tone={tone}>{status}</StatusBadge></div>
    <h3 id={id}>{title}</h3>
    <p>{description}</p>
    <div className="admin-management-card__dependency"><strong>Required integration</strong><span>{dependency}</span></div>
    <Link className="role-dashboard__text-link" to={path}>{linkLabel} <Icon name="arrow" size={17} /></Link>
  </section>
}

export default function AdminDashboard({ user }) {
  return <main className="shared-page role-dashboard admin-dashboard">
    <header className="role-dashboard__header admin-dashboard__header">
      <div>
        <p className="role-dashboard__eyebrow">Administration workspace</p>
        <h1>Welcome, {user.fullName.trim() || 'there'}</h1>
        <p>Create pending Technician access and monitor available entry points. Complete administrative data remains unavailable until its owning API contracts are connected.</p>
      </div>
      <Link className="shared-button" to="/notifications"><Icon name="bell" size={18} />Review notifications</Link>
    </header>

    <div className="admin-dashboard__layout">
      <section className="admin-management" aria-labelledby="admin-management-title">
        <div className="role-dashboard__section-title">
          <div><p className="role-dashboard__eyebrow">Management</p><h2 id="admin-management-title">Administrative workspaces</h2></div>
          <p>No user, AI or system totals are available from the current web APIs.</p>
        </div>
        <div className="admin-management__grid">
          <ManagementPanel id="admin-users-title" title="Users" icon="user" path="/modules/users"
            description="Create pending Maintenance Technician access in the Administration module. User directory and account-management data remain unavailable."
            dependency="Complete user-directory and account-management APIs"
            status="Technician setup available" tone="success" linkLabel="Add Technician" />
          <ManagementPanel id="admin-system-title" title="AI / System Overview" icon="devices" path="/modules/ai-system-overview"
            description="System-wide AI health and activity are not available from an aggregate data source in the web app."
            dependency="System-overview API contract and owning module" />
        </div>
      </section>

      <aside className="admin-dashboard__shared" aria-label="Admin shared tools">
        <DashboardNotificationCard id="admin-notifications-title" />
        <section className="shared-card admin-available" aria-labelledby="admin-available-title">
          <div><p className="role-dashboard__eyebrow">Available now</p><h2 id="admin-available-title">Shared account tools</h2></div>
          <Link to="/notifications" aria-label="Open notification inbox from shared tools"><span className="role-dashboard__icon role-dashboard__icon--small"><Icon name="bell" size={19} /></span><span><strong>Notifications</strong><small>Review updates for this account</small></span><Icon name="arrow" size={17} /></Link>
          <Link to="/profile"><span className="role-dashboard__icon role-dashboard__icon--small"><Icon name="user" size={19} /></span><span><strong>Profile</strong><small>View account details and sign out</small></span><Icon name="arrow" size={17} /></Link>
        </section>
      </aside>
    </div>
  </main>
}
