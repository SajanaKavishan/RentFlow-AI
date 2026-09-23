import { useAuth } from '../../features/auth/useAuth.js'
import { USER_ROLES } from '../../features/auth/authModel.js'
import { AppCard, PageHeader } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import { initialsForName } from '../ui/userDisplay.js'
import TenantApplicationDocuments from './TenantApplicationDocuments.jsx'
import './profile.css'

function UnavailableAction({ icon, title, explanation }) {
  return <button className="profile-action profile-action--unavailable" type="button" disabled>
    <span className="profile-action__icon"><Icon name={icon} size={20} /></span>
    <span className="profile-action__copy"><strong>{title}</strong><small>{explanation}</small></span>
    <span className="profile-action__status">Unavailable</span>
  </button>
}

export default function ProfilePage() {
  const { user, logout } = useAuth()

  return <main className="shared-page profile-page">
    <PageHeader eyebrow="Your account" title="Profile">
      <p>View your account details and the actions available in the web app.</p>
    </PageHeader>

    <AppCard className="profile-identity">
      <span className="profile-identity__avatar" aria-hidden="true">{initialsForName(user.fullName)}</span>
      <div className="profile-identity__copy">
        <h2>{user.fullName}</h2>
        <p>{user.email}</p>
      </div>
    </AppCard>

    <div className="profile-layout">
      <section className="profile-section profile-section--account" aria-labelledby="profile-account-title">
        <h2 id="profile-account-title">Account</h2>
        <AppCard className="profile-section__card">
          <dl className="profile-details">
            <div><dt>Full name</dt><dd>{user.fullName}</dd></div>
            <div><dt>Email address</dt><dd>{user.email}</dd></div>
            <div><dt>Phone number</dt><dd>{user.phoneNumber?.trim() || 'Not provided'}</dd></div>
          </dl>
          <div className="profile-actions">
            {user.role === USER_ROLES.TENANT && <TenantApplicationDocuments key={user.id} />}
            <UnavailableAction icon="user" title="Edit profile" explanation="Account editing is not available in the web app." />
            <UnavailableAction icon="document" title="Change password" explanation="Password changes are not available in the web app." />
            <button className="profile-action profile-action--logout" type="button" onClick={logout}>
              <span className="profile-action__icon"><Icon name="logout" size={20} /></span>
              <span className="profile-action__copy"><strong>Sign out</strong><small>End this session on this device.</small></span>
            </button>
          </div>
        </AppCard>
      </section>

      <section className="profile-section profile-section--preferences" aria-labelledby="profile-preferences-title">
        <h2 id="profile-preferences-title">Preferences</h2>
        <AppCard className="profile-section__card profile-actions">
          <UnavailableAction icon="info" title="Notifications" explanation="Notification preferences are not available yet." />
          <UnavailableAction icon="building" title="Language" explanation="Language settings are not available yet." />
        </AppCard>
      </section>

      <section className="profile-section profile-section--support" aria-labelledby="profile-support-title">
        <h2 id="profile-support-title">Support</h2>
        <AppCard className="profile-section__card profile-actions">
          <UnavailableAction icon="info" title="Contact support" explanation="Web support is not connected yet." />
        </AppCard>
      </section>
    </div>
  </main>
}
