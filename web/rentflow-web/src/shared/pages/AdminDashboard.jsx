import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { useNotificationCount } from '../../features/notifications/NotificationCountContext.js'
import { StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import './role-dashboard.css'

const summaryCards = [
  { title: 'Total Users', icon: 'user', dependency: 'Admin user aggregate required' },
  { title: 'Properties', icon: 'building', dependency: 'Admin property aggregate required' },
  { title: 'Active Applications', icon: 'document', dependency: 'Admin application aggregate required' },
  { title: 'Monthly Volume', icon: 'trend', dependency: 'Admin payment aggregate required' },
]

function SummaryCard({ title, icon, dependency }) {
  const id = `admin-summary-${title.toLowerCase().replaceAll(' ', '-')}`

  return <section className="shared-card admin-summary-card" aria-labelledby={id}>
    <div className="admin-summary-card__heading">
      <span className="admin-overview__icon admin-overview__icon--summary"><Icon name={icon} size={20} /></span>
      <h2 id={id}>{title}</h2>
    </div>
    <StatusBadge tone="warning">Integration pending</StatusBadge>
    <p>{dependency}</p>
  </section>
}

function IntegrationPanel({ id, title, icon, description, dependency, path, linkLabel }) {
  return <section className="shared-card admin-overview-panel" aria-labelledby={id}>
    <div className="admin-overview-panel__heading">
      <span className="admin-overview__icon"><Icon name={icon} size={21} /></span>
      <div><p className="role-dashboard__eyebrow">Reporting</p><h2 id={id}>{title}</h2></div>
      <StatusBadge tone="warning">Integration pending</StatusBadge>
    </div>
    <p className="admin-overview-panel__description">{description}</p>
    <div className="admin-overview-panel__dependency">
      <Icon name="info" size={17} />
      <span><strong>Required integration</strong>{dependency}</span>
    </div>
    {path && <Link className="role-dashboard__text-link" to={path}>{linkLabel} <Icon name="arrow" size={17} /></Link>}
  </section>
}

function notificationSummary(notificationState) {
  if (notificationState?.countStatus === 'loading') return 'Checking unread count'
  if (notificationState?.countStatus !== 'ready') return 'Unread count unavailable — open the inbox directly'
  if (notificationState.unreadCount === 0) return 'No unread notifications'
  return `${notificationState.unreadCount} unread ${notificationState.unreadCount === 1 ? 'notification' : 'notifications'}`
}

function useCurrentDay() {
  const [currentDay, setCurrentDay] = useState(() => new Date())

  useEffect(() => {
    let timer
    const scheduleNextDay = () => {
      const now = new Date()
      const nextDay = new Date(now)
      nextDay.setHours(24, 0, 0, 0)
      timer = window.setTimeout(() => {
        setCurrentDay(new Date())
        scheduleNextDay()
      }, nextDay.getTime() - now.getTime())
    }

    scheduleNextDay()
    return () => window.clearTimeout(timer)
  }, [])

  return new Intl.DateTimeFormat('en-US', {
    month: 'long', day: 'numeric', year: 'numeric',
  }).format(currentDay)
}

export default function AdminDashboard() {
  const notificationState = useNotificationCount()
  const currentDay = useCurrentDay()

  return <main className="shared-page role-dashboard admin-dashboard">
    <header className="admin-overview__header">
      <div>
        <p className="admin-overview__context">Platform Administration</p>
        <h1>System Overview</h1>
        <p className="admin-overview__as-of">Overview status as of {currentDay}.</p>
      </div>
      <Link className="shared-button" to="/modules/users?action=add-technician"><Icon name="user" size={18} />Add Technician</Link>
    </header>

    <section className="admin-overview__summary" aria-label="System summary">
      {summaryCards.map((card) => <SummaryCard key={card.title} {...card} />)}
    </section>

    <div className="admin-overview__workspace">
      <div className="admin-overview__main">
        <IntegrationPanel id="admin-platform-activity-title" title="Platform Activity" icon="trend"
          description="Recent platform-wide activity is not shown because no authorized Admin activity feed is available."
          dependency="Admin activity-feed contract" />
        <IntegrationPanel id="admin-user-distribution-title" title="User Distribution" icon="user"
          description="Role totals and distribution bars are withheld until the backend supplies an authorized aggregate."
          dependency="Admin user-distribution aggregate" />
        <IntegrationPanel id="admin-ai-workflows-title" title="AI Workflows" icon="devices"
          description="System-wide AI usage and outcomes are not available from the existing record-scoped workflow APIs."
          dependency="Admin AI reporting aggregate" path="/modules/ai-system-overview" linkLabel="View integration details" />
      </div>

      <aside className="admin-overview__rail" aria-label="System status and quick access">
        <IntegrationPanel id="admin-system-health-title" title="System Health" icon="refresh"
          description="No health result is displayed without an authoritative service-status contract."
          dependency="Admin service-health contract" />

        <section className="shared-card admin-quick-access" aria-labelledby="admin-quick-access-title">
          <div className="admin-quick-access__heading">
            <p className="role-dashboard__eyebrow">Available now</p>
            <h2 id="admin-quick-access-title">Quick Access</h2>
          </div>
          <nav aria-label="Admin quick access">
            <Link to="/modules/users?action=add-technician" aria-label="Manage Users / Add Technician">
              <span className="admin-overview__icon admin-overview__icon--small"><Icon name="user" size={19} /></span>
              <span><strong>Manage Users / Add Technician</strong><small>Technician creation is available; the full directory is pending.</small></span>
              <Icon name="arrow" size={17} />
            </Link>
            <Link to="/notifications" aria-label="Open notifications from Quick Access">
              <span className="admin-overview__icon admin-overview__icon--small admin-overview__icon--notification"><Icon name="bell" size={19} /></span>
              <span><strong>Notifications</strong><small>{notificationSummary(notificationState)}</small></span>
              <Icon name="arrow" size={17} />
            </Link>
            <Link to="/profile" aria-label="Profile">
              <span className="admin-overview__icon admin-overview__icon--small"><Icon name="user" size={19} /></span>
              <span><strong>Profile</strong><small>View account details and sign out.</small></span>
              <Icon name="arrow" size={17} />
            </Link>
            <Link to="/modules/ai-system-overview" aria-label="AI / System Overview">
              <span className="admin-overview__icon admin-overview__icon--small"><Icon name="devices" size={19} /></span>
              <span><strong>AI / System Overview</strong><small>Open the current integration dependency.</small></span>
              <Icon name="arrow" size={17} />
            </Link>
          </nav>
        </section>
      </aside>
    </div>
  </main>
}
