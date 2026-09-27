import { Link, useParams } from 'react-router-dom'
import { USER_ROLES } from '../../features/auth/authModel.js'
import { useAuth } from '../../features/auth/useAuth.js'
import TenantMaintenancePage from '../../features/maintenance/pages/TenantMaintenancePage.jsx'
import LandlordMaintenancePage from '../../features/maintenance/pages/LandlordMaintenancePage.jsx'
import { navigationItemForPath } from '../navigation/roleNavigation.js'
import Icon from './Icons.jsx'
import './shared-ui.css'

export function PageHeader({ eyebrow, title, children }) { return <header className="shared-page-header">{eyebrow && <p>{eyebrow}</p>}<h1>{title}</h1>{children && <div className="shared-page-header__intro">{children}</div>}</header> }
export function AppCard({ children, className = '' }) { return <section className={`shared-card ${className}`.trim()}>{children}</section> }
export function StatusBadge({ tone = 'neutral', children }) { return <span className={`shared-status shared-status--${tone}`}>{children}</span> }
export function LoadingState({ title = 'Loading' }) { return <main className="shared-state" role="status"><span className="shared-spinner" aria-hidden="true" /><h1>{title}</h1><p>Please wait a moment.</p></main> }
export function EmptyState({ title = 'Nothing here yet', message }) { return <main className="shared-state"><span className="shared-state__icon"><Icon name="search" size={26} /></span><h1>{title}</h1>{message && <p>{message}</p>}</main> }
export function ErrorState({ title = 'Something went wrong', message, onRetry }) { return <main className="shared-state" role="alert"><span className="shared-state__icon shared-state__icon--danger"><Icon name="alert" size={26} /></span><h1>{title}</h1>{message && <p>{message}</p>}{onRetry && <button className="shared-button" type="button" onClick={onRetry}>Try again</button>}</main> }
export function UnauthorizedState() { return <main className="shared-state"><span className="shared-state__icon"><Icon name="alert" size={26} /></span><h1>Not accessible</h1><p>Your account does not have access to this area.</p><Link className="shared-button" to="/dashboard">Return to dashboard</Link></main> }
export function NotFoundState() { return <main className="shared-state"><span className="shared-state__icon"><Icon name="search" size={26} /></span><h1>Page not found</h1><p>The address you requested does not exist.</p><Link className="shared-button" to="/dashboard">Return to dashboard</Link></main> }
export function ModuleUnavailableState({ title, explanation, owner, status = 'Integration pending' }) {
  return <main className="shared-state"><span className="shared-state__icon"><Icon name="info" size={26} /></span><StatusBadge tone="warning">{status}</StatusBadge><h1>{title}</h1><p>{explanation}</p>{owner && <p className="shared-state__owner">Owning area: {owner}</p>}<Link className="shared-button" to="/dashboard">Return to dashboard</Link></main>
}
export function UnavailableState() {
  const { module } = useParams()
  const { user } = useAuth()
  if (module === 'maintenance' && user.role === USER_ROLES.TENANT) {
    return <TenantMaintenancePage />
  }
  if (module === 'maintenance' && user.role === USER_ROLES.LANDLORD) {
    return <LandlordMaintenancePage />
  }
  const item = navigationItemForPath(user.role, `/modules/${module}`)
  if (!item || item.available) return <NotFoundState />
  return <ModuleUnavailableState title={item.label} explanation={item.description} owner={item.owner} />
}
