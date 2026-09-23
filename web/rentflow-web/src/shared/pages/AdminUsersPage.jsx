import { Link } from 'react-router-dom'
import { StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import './admin-users.css'

export default function AdminUsersPage() {
  return <main className="shared-page admin-users-page">
    <header className="admin-users-page__header">
      <div>
        <p className="admin-users-page__eyebrow">Administration workspace</p>
        <h1>Users</h1>
        <p>Review the availability of authorized user administration for RentFlow AI.</p>
      </div>
      <div className="admin-users-page__header-actions" aria-label="Users page navigation">
        <Link className="shared-button shared-button--outline" to="/dashboard"><Icon name="home" size={18} />Back to dashboard</Link>
        <Link className="shared-button" to="/notifications" aria-label="Open notification inbox"><Icon name="bell" size={18} />Notifications</Link>
      </div>
    </header>

    <div className="admin-users-page__layout">
      <section className="shared-card admin-users-workspace" aria-labelledby="admin-user-directory-title">
        <div className="admin-users-workspace__heading">
          <div><p className="admin-users-page__eyebrow">User management</p><h2 id="admin-user-directory-title">User directory</h2></div>
          <span className="admin-users-workspace__scope"><Icon name="user" size={17} />Admin-only workspace</span>
        </div>

        <div className="admin-users-integration" role="status">
          <span className="admin-users-page__icon"><Icon name="user" size={30} /></span>
          <StatusBadge tone="warning">Integration pending</StatusBadge>
          <h3>Authorized user directory required</h3>
          <p>The backend does not currently expose an Admin-authorized endpoint for listing RentFlow users.</p>
          <p>No user records, role totals, account statuses or activity information are shown without that contract.</p>
        </div>
      </section>

      <aside className="admin-users-page__side" aria-label="User management integration details">
        <section className="shared-card admin-users-requirements" aria-labelledby="admin-users-requirements-title">
          <div className="admin-users-requirements__heading"><span className="admin-users-page__icon admin-users-page__icon--small"><Icon name="info" size={21} /></span><div><p className="admin-users-page__eyebrow">Required integration</p><h2 id="admin-users-requirements-title">Before users can appear</h2></div></div>
          <ul>
            <li><strong>Authorized directory endpoint</strong><span>An Admin-scoped collection API with an agreed response contract.</span></li>
            <li><strong>Access rules</strong><span>Product-owned rules for which user fields an Admin may review.</span></li>
            <li><strong>Management actions</strong><span>Separate API and product authorization before any account-changing control is introduced.</span></li>
          </ul>
          <p className="admin-users-requirements__note">The existing <code>/api/auth/me</code> endpoint identifies only the signed-in account and cannot supply a user directory.</p>
        </section>

        <section className="shared-card admin-users-tools" aria-labelledby="admin-users-tools-title">
          <div><p className="admin-users-page__eyebrow">Shared tools</p><h2 id="admin-users-tools-title">Account access</h2></div>
          <Link to="/notifications" aria-label="Open notifications from Users"><span className="admin-users-page__icon admin-users-page__icon--small"><Icon name="bell" size={20} /></span><span><strong>Notifications</strong><small>Review updates for your account</small></span><Icon name="arrow" size={17} /></Link>
          <Link to="/profile"><span className="admin-users-page__icon admin-users-page__icon--small"><Icon name="user" size={20} /></span><span><strong>Profile</strong><small>View account details and sign out</small></span><Icon name="arrow" size={17} /></Link>
        </section>
      </aside>
    </div>
  </main>
}
