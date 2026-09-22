import { useAuth } from '../../features/auth/useAuth.js'
import { AppCard, PageHeader } from '../ui/States.jsx'
import { initialsForName } from '../ui/userDisplay.js'

export default function ProfilePage() {
  const { user, logout } = useAuth()
  return <main className="shared-page shared-page--profile"><PageHeader eyebrow="Your account" title="Profile"><p>Your current account details. Editing is not available.</p></PageHeader>
    <AppCard className="shared-profile-card"><div className="shared-profile-card__heading"><span className="shared-profile-avatar" aria-hidden="true">{initialsForName(user.fullName)}</span><div><h2>{user.fullName}</h2><p>{user.role} account</p></div></div><dl className="shared-profile-list"><div><dt>Full name</dt><dd>{user.fullName}</dd></div><div><dt>Email</dt><dd>{user.email}</dd></div><div><dt>Phone number</dt><dd>{user.phoneNumber}</dd></div><div><dt>Role</dt><dd>{user.role}</dd></div></dl><div className="shared-profile-card__footer"><button className="shared-button shared-button--outline shared-button--danger" type="button" onClick={logout}>Logout</button></div></AppCard>
  </main>
}
