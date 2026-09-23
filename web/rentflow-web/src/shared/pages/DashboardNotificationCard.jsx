import { Link } from 'react-router-dom'
import { useNotificationCount } from '../../features/notifications/NotificationCountContext.js'
import Icon from '../ui/Icons.jsx'

export default function DashboardNotificationCard({ id, className = '' }) {
  const notificationState = useNotificationCount()
  const unreadCount = notificationState?.unreadCount
  const countStatus = notificationState?.countStatus || 'unavailable'
  const ready = countStatus === 'ready'

  return <section className={`shared-card role-dashboard-notifications ${className}`.trim()} aria-labelledby={id}>
    <span className="role-dashboard__icon role-dashboard__icon--notifications"><Icon name="bell" size={22} /></span>
    <div className="role-dashboard-notifications__copy">
      <p className="role-dashboard__eyebrow">Notifications</p>
      <h2 id={id}>{ready
        ? unreadCount === 0 ? 'You are up to date' : `${unreadCount} unread ${unreadCount === 1 ? 'notification' : 'notifications'}`
        : countStatus === 'loading' ? 'Checking your updates' : 'Notification count unavailable'}</h2>
      <p>{ready
        ? unreadCount === 0 ? 'There are no unread updates for your account.' : 'Open your inbox to review the latest account updates.'
        : countStatus === 'loading' ? 'Loading the unread count for your authenticated account.' : 'Open the inbox to review notifications directly.'}</p>
    </div>
    <Link className="shared-button shared-button--outline" to="/notifications">Open notifications <Icon name="arrow" size={17} /></Link>
  </section>
}
