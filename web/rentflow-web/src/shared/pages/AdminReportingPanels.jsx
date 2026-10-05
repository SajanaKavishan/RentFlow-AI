import { Link } from 'react-router-dom'
import { useEffect, useId, useRef, useState } from 'react'
import { getAdminActivityPage } from './adminReportingApi.js'
import useAdminReport from './useAdminReport.js'
import { StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import './role-dashboard.css'

export function AdminReportState({ state }) {
  if (state.status === 'loading') return <p role="status">Loading Admin reporting…</p>
  if (state.status === 'error') return <div role="alert"><p>Admin reporting could not be loaded.</p><button className="shared-button shared-button--outline" type="button" onClick={state.retry}>Try again</button></div>
  return null
}

const panelDetails = {
  activity: ['Platform Activity', 'trend', 'Latest listings, applications, maintenance requests and completed payments.'],
  workflows: ['AI Workflows', 'devices', 'Recorded workflow runs across the platform, including retries.'],
  health: ['System Health', 'refresh', 'Live API, database and agent connectivity checks.'],
}
const dateTime = (value) => new Date(value).toLocaleString('en-GB', { timeZone: 'Asia/Colombo', dateStyle: 'medium', timeStyle: 'short' })

function ActivityItems({ items }) {
  return <ul className="admin-reporting__activity">{items.map((item, index) => <li key={index}>
    <strong>{item.kind}</strong><span>{item.description}</span><time dateTime={item.occurredAt}>{dateTime(item.occurredAt)}</time>
  </li>)}</ul>
}

function PlatformActivity({ items }) {
  const [expanded, setExpanded] = useState(false)
  const [full, setFull] = useState([])
  const [page, setPage] = useState(0)
  const [hasMore, setHasMore] = useState(true)
  const [status, setStatus] = useState('idle')
  const request = useRef(null)
  const listId = useId()
  useEffect(() => () => request.current?.abort(), [])

  async function loadPage(nextPage) {
    request.current?.abort()
    const controller = new AbortController()
    request.current = controller
    setStatus('loading')
    try {
      const data = await getAdminActivityPage(nextPage, controller.signal)
      if (controller.signal.aborted) return
      setFull((previous) => nextPage === 1 ? data : [...previous, ...data])
      setPage(nextPage)
      setHasMore(data.length === 50)
      setStatus('ready')
    } catch {
      if (!controller.signal.aborted) setStatus('error')
    }
  }

  function toggle() {
    if (expanded) {
      request.current?.abort()
      if (status === 'loading') setStatus('idle')
      setExpanded(false)
    } else {
      setExpanded(true)
      if (!page) loadPage(1)
    }
  }

  if (!items.length) return <p>No platform activity yet.</p>
  return <>
    <div id={listId} className={expanded ? 'admin-reporting__activity-expanded' : undefined}
      role={expanded ? 'region' : undefined} aria-label={expanded ? 'All platform activity' : undefined} tabIndex={expanded ? 0 : undefined}>
      <ActivityItems items={expanded && page ? full : items.slice(0, 7)} />
      {expanded && status === 'loading' && <p role="status">Loading platform activity…</p>}
      {expanded && status === 'error' && <div role="alert"><p>Platform activity could not be loaded.</p>
        <button className="shared-button shared-button--outline" type="button" onClick={() => loadPage(page + 1)}>Try again</button></div>}
      {expanded && page > 0 && hasMore && status === 'ready' && <button className="shared-button shared-button--outline" type="button" onClick={() => loadPage(page + 1)}>Load more</button>}
    </div>
    {items.length > 7 && <button className="shared-button shared-button--outline" type="button" aria-expanded={expanded} aria-controls={listId} onClick={toggle}>{expanded ? 'Show less' : 'See all'}</button>}
  </>
}

export default function AdminReportingPanel({ kind, identityKey, monitorLink = false }) {
  const state = useAdminReport(kind, identityKey)
  const [title, icon, description] = panelDetails[kind]
  return <section className="shared-card admin-overview-panel admin-reporting-panel" aria-label={title} aria-busy={state.status === 'loading'}>
    <div className="admin-overview-panel__heading">
      <span className="admin-overview__icon"><Icon name={icon} size={21} /></span>
      <div><p className="role-dashboard__eyebrow">Reporting</p><h2>{title}</h2></div>
      {state.status === 'ready' && <StatusBadge tone="success">Live reporting</StatusBadge>}
    </div>
    <p className="admin-overview-panel__description">{description}</p>
    <AdminReportState state={state} />
    {state.status === 'ready' && <>
      {kind === 'activity' && <PlatformActivity key={identityKey} items={state.data} />}
      {kind === 'workflows' && <div className="admin-reporting__table-wrap"><table className="admin-reporting__table">
        <thead><tr><th>Workflow</th><th>Total</th><th>Pending</th><th>Running</th><th>Awaiting review</th><th>Completed</th><th>Failed</th></tr></thead>
        <tbody>{state.data.map((item) => <tr key={item.name}><th scope="row">{item.name}</th>{['total', 'pending', 'running', 'awaitingReview', 'completed', 'failed'].map((field) => <td key={field}>{item[field]}</td>)}</tr>)}</tbody>
      </table></div>}
      {kind === 'health' && <><ul className="admin-reporting__health">{state.data.services.map((service) => <li key={service.name}>
        <div><strong>{service.name}</strong><p>{service.detail}</p></div><StatusBadge tone={service.status === 'available' ? 'success' : 'warning'}>{service.status === 'available' ? 'Available' : 'Unavailable'}</StatusBadge>
      </li>)}</ul><p className="admin-reporting__checked">Checked {dateTime(state.data.checkedAt)}</p><button className="shared-button shared-button--outline" type="button" onClick={state.retry}>Refresh health</button></>}
    </>}
    {monitorLink && <Link className="role-dashboard__text-link" to="/modules/ai-system-overview">Open workflow monitor <Icon name="arrow" size={17} /></Link>}
  </section>
}
