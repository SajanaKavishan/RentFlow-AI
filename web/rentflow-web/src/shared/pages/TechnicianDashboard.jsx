import { Link } from 'react-router-dom'
import { StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import DashboardNotificationCard from './DashboardNotificationCard.jsx'
import './role-dashboard.css'

export default function TechnicianDashboard({ user }) {
  return <main className="shared-page role-dashboard technician-dashboard">
    <header className="role-dashboard__header">
      <div>
        <p className="role-dashboard__eyebrow">Technician workspace</p>
        <h1>Welcome, {user.fullName.trim() || 'there'}</h1>
        <p>Use your shared account tools now. Assigned maintenance work is connected to your authenticated technician queue.</p>
      </div>
      <div className="role-dashboard__header-actions" aria-label="Technician account actions">
        <Link className="shared-button" to="/notifications" aria-label="Open notification inbox"><Icon name="bell" size={18} />Notifications</Link>
        <Link className="shared-button shared-button--outline" to="/profile"><Icon name="user" size={18} />Profile</Link>
      </div>
    </header>

    <div className="technician-dashboard__workspace">
      <section className="shared-card technician-work" aria-labelledby="technician-work-title">
        <div className="role-dashboard__section-heading">
          <span className="role-dashboard__icon role-dashboard__icon--work"><Icon name="tools" size={25} /></span>
          <div><p className="role-dashboard__eyebrow">Maintenance workspace</p><h2 id="technician-work-title">Assigned Work</h2></div>
          <StatusBadge tone="success">Connected</StatusBadge>
        </div>
        <p className="technician-work__intro">Your authorized work queue is available through the live Maintenance API.</p>
        <div className="technician-work__dependency">
          <Icon name="info" size={20} />
          <div><strong>Assigned work ready</strong><p>Live maintenance tasks for your account are now available in the technician queue view.</p></div>
        </div>
        <Link className="shared-button shared-button--outline technician-work__status" to="/modules/assigned-work">View assigned work <Icon name="arrow" size={17} /></Link>
      </section>

      <aside className="technician-dashboard__side" aria-label="Technician shared tools">
        <DashboardNotificationCard id="technician-notifications-title" />
        <section className="shared-card role-dashboard-account" aria-labelledby="technician-account-title">
          <span className="role-dashboard__icon"><Icon name="user" size={22} /></span>
          <div><p className="role-dashboard__eyebrow">Account</p><h2 id="technician-account-title">Your profile</h2><p>Review the identity and contact details associated with this technician session.</p></div>
          <Link className="role-dashboard__text-link" to="/profile">View profile <Icon name="arrow" size={17} /></Link>
        </section>
      </aside>
    </div>

    <section className="technician-readiness" aria-labelledby="technician-readiness-title">
      <div className="role-dashboard__section-title"><div><p className="role-dashboard__eyebrow">Workspace readiness</p><h2 id="technician-readiness-title">What is available</h2></div><p>Only confirmed shared capabilities are shown as ready.</p></div>
      <div className="technician-readiness__list">
        <div><Icon name="bell" size={19} /><span><strong>Notifications</strong><small>Available for your authenticated account</small></span><StatusBadge tone="success">Available</StatusBadge></div>
        <div><Icon name="user" size={19} /><span><strong>Profile</strong><small>Account details and sign out</small></span><StatusBadge tone="success">Available</StatusBadge></div>
        <div><Icon name="tools" size={19} /><span><strong>Assigned Work</strong><small>Live maintenance queue for this technician</small></span><StatusBadge tone="success">Available</StatusBadge></div>
      </div>
    </section>
  </main>
}
