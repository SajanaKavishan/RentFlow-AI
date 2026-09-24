import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { ApiError } from '../../core/api/apiClient.js'
import {
  ADMIN_USER_DISTRIBUTION_ROLES,
  getAdminUserRoleTotals,
  getAdminUserTotal,
} from '../../features/adminUsers/adminUsersApi.js'
import { useNotificationCount } from '../../features/notifications/NotificationCountContext.js'
import { StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import './role-dashboard.css'

const summaryCards = [
  { title: 'Properties', icon: 'building', dependency: 'Admin property aggregate required' },
  { title: 'Active Applications', icon: 'document', dependency: 'Admin application aggregate required' },
  { title: 'Monthly Volume', icon: 'trend', dependency: 'Admin payment aggregate required' },
]

function totalUsersError(error) {
  if (error instanceof ApiError && error.statusCode === 401) {
    return 'Your Admin session is no longer valid. Sign in again to view the user total.'
  }
  if (error instanceof ApiError && error.statusCode === 403) {
    return 'Your account is not authorized to view the user total.'
  }
  if (error instanceof ApiError) return error.message
  return 'The user total could not be loaded.'
}

function TotalUsersCard({ state, retry }) {
  const isAuthorizationError = state.error instanceof ApiError
    && [401, 403].includes(state.error.statusCode)

  return <section className="shared-card admin-summary-card" aria-labelledby="admin-summary-total-users" aria-busy={state.status === 'loading'}>
    <div className="admin-summary-card__heading">
      <span className="admin-overview__icon admin-overview__icon--summary"><Icon name="user" size={20} /></span>
      <h2 id="admin-summary-total-users">Total Users</h2>
    </div>
    {state.status === 'ready' && <>
      <strong className="admin-summary-card__value">{new Intl.NumberFormat('en-US').format(state.totalCount)}</strong>
      <p>Users in the authorized directory</p>
    </>}
    {state.status === 'loading' && <p className="admin-summary-card__state" role="status">Loading total users&hellip;</p>}
    {state.status === 'error' && <div className="admin-summary-card__state admin-summary-card__state--error" role="alert">
      <p>{totalUsersError(state.error)}</p>
      {!isAuthorizationError && <button className="shared-button shared-button--outline" type="button" onClick={retry}>Retry total users</button>}
    </div>}
  </section>
}

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

const roleLabels = Object.freeze({
  Tenant: 'Tenant',
  Landlord: 'Landlord',
  MaintenanceTechnician: 'Technicians',
  Admin: 'Admin',
})

function UserDistributionPanel({ state, totalUsers, retry }) {
  const error = state.status === 'error' ? state.error : totalUsers.error
  const isAuthorizationError = error instanceof ApiError && [401, 403].includes(error.statusCode)
  const isLoading = state.status === 'loading' || totalUsers.status === 'loading'
  const isReady = state.status === 'ready' && totalUsers.status === 'ready'

  return <section className="shared-card admin-overview-panel admin-user-distribution" aria-labelledby="admin-user-distribution-title" aria-busy={isLoading}>
    <div className="admin-overview-panel__heading">
      <span className="admin-overview__icon"><Icon name="user" size={21} /></span>
      <div><p className="role-dashboard__eyebrow">Directory</p><h2 id="admin-user-distribution-title">User Distribution</h2></div>
      {isReady && <StatusBadge tone="success">Live directory</StatusBadge>}
    </div>
    <p className="admin-overview-panel__description">Counts include active and inactive accounts.</p>
    {isLoading && <p className="admin-user-distribution__state" role="status">Loading user distribution&hellip;</p>}
    {!isLoading && !isReady && <div className="admin-user-distribution__state admin-user-distribution__state--error" role="alert">
      <p>{totalUsers.status === 'error' ? totalUsersError(totalUsers.error) : totalUsersError(state.error)}</p>
      {!isAuthorizationError && <button className="shared-button shared-button--outline" type="button" onClick={retry}>Retry user distribution</button>}
    </div>}
    {isReady && <dl className="admin-user-distribution__list">
      {ADMIN_USER_DISTRIBUTION_ROLES.map((role) => {
        const count = state.totals[role]
        const proportion = totalUsers.totalCount === 0
          ? 0
          : Math.min((count / totalUsers.totalCount) * 100, 100)
        return <div className="admin-user-distribution__row" key={role} role="group" aria-label={`${roleLabels[role]} users`}>
          <div className="admin-user-distribution__label"><dt>{roleLabels[role]}</dt><dd>{new Intl.NumberFormat('en-US').format(count)}</dd></div>
          <div className="admin-user-distribution__bar" role="progressbar" aria-label={`${roleLabels[role]} proportion`} aria-valuemin="0" aria-valuemax={totalUsers.totalCount} aria-valuenow={count}>
            <span style={{ width: `${proportion}%` }} />
          </div>
        </div>
      })}
    </dl>}
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

export default function AdminDashboard({ user }) {
  const notificationState = useNotificationCount()
  const currentDay = useCurrentDay()
  const identityKey = user?.id ?? ''
  const [totalUsersRequest, setTotalUsersRequest] = useState(0)
  const totalUsersRequestKey = `${identityKey}:${totalUsersRequest}`
  const [totalUsersState, setTotalUsersState] = useState({ requestKey: '', status: 'loading', totalCount: null, error: null })
  const totalUsers = totalUsersState.requestKey === totalUsersRequestKey
    ? totalUsersState
    : { status: 'loading', totalCount: null, error: null }
  const [distributionRequest, setDistributionRequest] = useState(0)
  const distributionRequestKey = `${identityKey}:${distributionRequest}`
  const [distributionState, setDistributionState] = useState({ requestKey: '', status: 'loading', totals: null, error: null })
  const distribution = distributionState.requestKey === distributionRequestKey
    ? distributionState
    : { status: 'loading', totals: null, error: null }

  useEffect(() => {
    const controller = new AbortController()
    getAdminUserTotal({ signal: controller.signal }).then((totalCount) => {
      if (!controller.signal.aborted) setTotalUsersState({ requestKey: totalUsersRequestKey, status: 'ready', totalCount, error: null })
    }).catch((error) => {
      if (!controller.signal.aborted) setTotalUsersState({ requestKey: totalUsersRequestKey, status: 'error', totalCount: null, error })
    })
    return () => controller.abort()
  }, [totalUsersRequestKey])

  useEffect(() => {
    const controller = new AbortController()
    getAdminUserRoleTotals({ signal: controller.signal }).then((totals) => {
      if (!controller.signal.aborted) setDistributionState({ requestKey: distributionRequestKey, status: 'ready', totals, error: null })
    }).catch((error) => {
      if (!controller.signal.aborted) setDistributionState({ requestKey: distributionRequestKey, status: 'error', totals: null, error })
    })
    return () => controller.abort()
  }, [distributionRequestKey])

  const retryTotalUsers = () => {
    setTotalUsersRequest((request) => request + 1)
  }

  const retryDistribution = () => {
    if (totalUsers.status === 'error') retryTotalUsers()
    setDistributionRequest((request) => request + 1)
  }

  return <main className="shared-page role-dashboard admin-dashboard">
    <header className="admin-overview__header">
      <div>
        <p className="admin-overview__context">Platform Administration</p>
        <h1>System Overview</h1>
        <p className="admin-overview__as-of">Overview status as of {currentDay}.</p>
      </div>
    </header>

    <section className="admin-overview__summary" aria-label="System summary">
      <TotalUsersCard state={totalUsers} retry={retryTotalUsers} />
      {summaryCards.map((card) => <SummaryCard key={card.title} {...card} />)}
    </section>

    <div className="admin-overview__workspace">
      <div className="admin-overview__main">
        <IntegrationPanel id="admin-platform-activity-title" title="Platform Activity" icon="trend"
          description="Recent platform-wide activity is not shown because no authorized Admin activity feed is available."
          dependency="Admin activity-feed contract" />
        <UserDistributionPanel state={distribution} totalUsers={totalUsers} retry={retryDistribution} />
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
              <span><strong>Manage Users</strong><small>User directory and Technician creation are available.</small></span>
              <Icon name="arrow" size={17} />
            </Link>
            <Link to="/notifications" aria-label="Open notifications from Quick Access">
              <span className="admin-overview__icon admin-overview__icon--small admin-overview__icon--notification"><Icon name="bell" size={19} /></span>
              <span><strong>Notifications</strong><small>{notificationSummary(notificationState)}</small></span>
              <Icon name="arrow" size={17} />
            </Link>
            <Link to="/profile" aria-label="Profile">
              <span className="admin-overview__icon admin-overview__icon--small"><Icon name="user" size={19} /></span>
              <span><strong>Profile</strong><small>View and edit your account details.</small></span>
              <Icon name="arrow" size={17} />
            </Link>
            <Link to="/modules/ai-system-overview" aria-label="AI / System Overview">
              <span className="admin-overview__icon admin-overview__icon--small"><Icon name="devices" size={19} /></span>
              <span><strong>AI Workflow Monitor</strong><small>Open the current integration dependency.</small></span>
              <Icon name="arrow" size={17} />
            </Link>
          </nav>
        </section>
      </aside>
    </div>
  </main>
}
