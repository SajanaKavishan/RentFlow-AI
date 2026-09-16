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
  const cards = (entries) => <div className="shared-dashboard-grid">{entries.map((item) => <Link key={`${item.label}-${item.path}`} className="shared-dashboard-link" to={item.path}><AppCard className="shared-module-card"><div className="shared-module-card__top"><span className="shared-module-card__icon"><Icon name={item.available ? 'arrow' : 'info'} size={20} /></span><StatusBadge tone={item.available ? 'success' : 'warning'}>{item.available ? 'Available' : 'Not available yet'}</StatusBadge></div><h3>{item.label}</h3><p>{item.note || (item.available ? 'Open this workspace' : 'Integration pending')}</p><span className="shared-module-card__arrow"><Icon name="arrow" size={18} /></span></AppCard></Link>)}</div>
  return <main className="shared-page"><PageHeader eyebrow={`${user.role} workspace`} title={`Welcome, ${user.fullName}`}><p>Explore what’s available in your workspace. New modules are clearly marked while they’re being integrated.</p></PageHeader>
    {available.length > 0 && <section className="shared-dashboard-section" aria-label="Available modules"><h2>Ready for you</h2><p>Continue with the tools available to your account.</p>{cards(available)}</section>}
    {pending.length > 0 && <section className="shared-dashboard-section" aria-label="Upcoming modules"><h2>Coming to your workspace</h2><p>These modules aren’t available on the web yet.</p>{cards(pending)}</section>}
  </main>
}
