import { Link, useParams } from 'react-router-dom'
import { useAuth } from '../../features/auth/useAuth.js'
import { navigationItemForPath } from '../navigation/roleNavigation.js'
import Icon from './Icons.jsx'
import './shared-ui.css'

export function PageHeader({ eyebrow, title, children }) { return <header className="shared-page-header"><p>{eyebrow}</p><h1>{title}</h1>{children && <div className="shared-page-header__intro">{children}</div>}</header> }
export function AppCard({ children, className = '' }) { return <section className={`shared-card ${className}`.trim()}>{children}</section> }
export function StatusBadge({ tone = 'neutral', children }) { return <span className={`shared-status shared-status--${tone}`}>{children}</span> }
export function LoadingState({ title = 'Loading' }) { return <main className="shared-state" role="status"><span className="shared-spinner" aria-hidden="true" /><h1>{title}</h1><p>Please wait a moment.</p></main> }
export function EmptyState({ title = 'Nothing here yet', message }) { return <main className="shared-state"><span className="shared-state__icon"><Icon name="search" size={26} /></span><h1>{title}</h1>{message && <p>{message}</p>}</main> }
export function ErrorState({ title = 'Something went wrong', message, onRetry }) { return <main className="shared-state" role="alert"><span className="shared-state__icon shared-state__icon--danger"><Icon name="alert" size={26} /></span><h1>{title}</h1>{message && <p>{message}</p>}{onRetry && <button className="shared-button" type="button" onClick={onRetry}>Try again</button>}</main> }
export function UnauthorizedState() { return <main className="shared-state"><span className="shared-state__icon"><Icon name="alert" size={26} /></span><h1>Not accessible</h1><p>Your account does not have access to this area.</p><Link className="shared-button" to="/">Return to dashboard</Link></main> }
export function NotFoundState() { return <main className="shared-state"><span className="shared-state__icon"><Icon name="search" size={26} /></span><h1>Page not found</h1><p>The address you requested does not exist.</p><Link className="shared-button" to="/">Return to dashboard</Link></main> }
export function UnavailableState() {
  const { module } = useParams()
  const { user } = useAuth()
  const item = navigationItemForPath(user.role, `/modules/${module}`)
  if (!item || item.available) return <NotFoundState />
  return <main className="shared-state"><span className="shared-state__icon"><Icon name="info" size={26} /></span><StatusBadge tone="warning">Not available yet</StatusBadge><h1>{item.label}</h1><p>This module has not been integrated into RentFlow yet. No workflow is available here.</p><Link className="shared-button" to="/">Return to dashboard</Link></main>
}
