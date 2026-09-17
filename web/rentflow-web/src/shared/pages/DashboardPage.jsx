import { Link } from 'react-router-dom'
import { useAuth } from '../../features/auth/useAuth.js'
import { navigationForRole } from '../navigation/roleNavigation.js'
import { AppCard, PageHeader, StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'

export default function DashboardPage() {
  const { user } = useAuth()
  const items = navigationForRole(user.role).filter((item) => item.path !== '/dashboard' && item.path !== '/profile')
  const available = items.filter((item) => item.available)
  const pending = items.filter((item) => !item.available)
  const cards = (entries) => <div className="shared-dashboard-grid">{entries.map((item) => <Link key={item.id} className="shared-dashboard-link" to={item.path}><AppCard className="shared-module-card"><div className="shared-module-card__top"><span className="shared-module-card__icon"><Icon name={item.available ? 'arrow' : 'info'} size={20} /></span><StatusBadge tone={item.available ? 'success' : 'warning'}>{item.available ? 'Available' : 'Integration pending'}</StatusBadge></div><h3>{item.label}</h3><p>{item.note || (item.available ? 'Open this workspace' : item.description)}</p><span className="shared-module-card__arrow"><Icon name="arrow" size={18} /></span></AppCard></Link>)}</div>
  return <main className="shared-page"><PageHeader eyebrow={`${user.role} workspace`} title={`Welcome, ${user.fullName}`}><p>Use the actions available for your role. Modules awaiting another product area are clearly marked.</p></PageHeader>
    {available.length > 0 && <section className="shared-dashboard-section" aria-label="Available modules"><h2>Ready for you</h2><p>Continue with the tools available to your account.</p>{cards(available)}</section>}
    {pending.length > 0 && <section className="shared-dashboard-section" aria-label="Upcoming modules"><h2>Integration pending</h2><p>These entry points are ready for their owning modules to be connected.</p>{cards(pending)}</section>}
  </main>
}
