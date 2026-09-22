import { useCallback, useEffect, useRef, useState } from 'react'
import { getNotifications, markNotificationRead } from './notificationsApi.js'
import { useNotificationCount } from './NotificationCountContext.js'
import { AppCard, PageHeader } from '../../shared/ui/States.jsx'
import Icon from '../../shared/ui/Icons.jsx'
import './notifications.css'

function notificationTime(value) {
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? 'Date unavailable' : new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium', timeStyle: 'short',
  }).format(date)
}

export default function NotificationsPage() {
  const { refreshCount } = useNotificationCount()
  const [page, setPage] = useState(1)
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [selectedId, setSelectedId] = useState(null)
  const [markingIds, setMarkingIds] = useState([])
  const [markError, setMarkError] = useState(null)
  const [reload, setReload] = useState(0)
  const requestId = useRef(0)
  const markingRef = useRef(new Set())
  const confirmedReads = useRef(new Map())
  const mounted = useRef(true)

  useEffect(() => {
    mounted.current = true
    return () => { mounted.current = false }
  }, [])

  useEffect(() => {
    const currentRequest = ++requestId.current
    const requestCounter = requestId
    getNotifications(page).then((response) => {
      if (currentRequest !== requestId.current) return
      setData({ ...response, items: response.items.map((item) => confirmedReads.current.get(item.id) ?? item) })
      setError('')
      setLoading(false)
    }).catch((failure) => {
      if (currentRequest !== requestId.current) return
      setError(failure.message)
      setLoading(false)
    })
    return () => { requestCounter.current++ }
  }, [page, reload])

  const refresh = useCallback(() => {
    setLoading(true)
    setError('')
    setReload((value) => value + 1)
    refreshCount()
  }, [refreshCount])

  const goToPage = (nextPage) => {
    setPage(nextPage)
    setData(null)
    setLoading(true)
    setError('')
    setMarkError(null)
    setSelectedId(null)
  }

  const select = async (item) => {
    setSelectedId(item.id)
    setMarkError(null)
    if (item.isRead || markingRef.current.has(item.id)) return
    markingRef.current.add(item.id)
    setMarkingIds(Array.from(markingRef.current))
    try {
      const updated = await markNotificationRead(item.id)
      if (!mounted.current) return
      confirmedReads.current.set(item.id, updated)
      setData((current) => current && ({ ...current, items: current.items.map((entry) => entry.id === item.id ? updated : entry) }))
      refreshCount()
    } catch (failure) {
      if (mounted.current) setMarkError({ id: item.id, message: failure.message })
    } finally {
      markingRef.current.delete(item.id)
      if (mounted.current) setMarkingIds(Array.from(markingRef.current))
    }
  }

  const selected = data?.items.find((item) => item.id === selectedId)
  return <main className="shared-page notifications-page">
    <div className="notifications-page__heading"><PageHeader eyebrow="Your updates" title="Notifications"><p>Updates for your account, newest first.</p></PageHeader><button className="shared-button shared-button--outline" type="button" onClick={refresh} disabled={loading}><Icon name="refresh" size={18} />Refresh</button></div>
    {loading && <div className="notifications-feedback" role="status"><span className="shared-spinner" aria-hidden="true" />Loading notifications…</div>}
    {!loading && error && <div className="notifications-feedback" role="alert"><strong>Notifications could not be loaded.</strong><p>{error}</p><button className="shared-button" type="button" onClick={refresh}>Try again</button></div>}
    {!loading && !error && data?.items.length === 0 && <AppCard className="notifications-feedback"><span className="notifications-feedback__icon"><Icon name="bell" size={26} /></span><h2>No notifications yet</h2><p>Updates for your account will appear here.</p></AppCard>}
    {!loading && !error && data?.items.length > 0 && <>
      <div className="notifications-layout">
        <section className="notifications-list" aria-label="Notification list">
          {data.items.map((item) => <button key={item.id} type="button" className={`notification-item${item.isRead ? '' : ' notification-item--unread'}${selectedId === item.id ? ' notification-item--selected' : ''}`} aria-pressed={selectedId === item.id} onClick={() => select(item)}>
            <span className="notification-item__top"><strong>{item.title}</strong><span className="notification-item__state">{item.isRead ? 'Read' : 'Unread'}</span></span>
            <span className="notification-item__message">{item.message}</span>
            <time dateTime={item.createdAt}>{notificationTime(item.createdAt)}</time>
          </button>)}
        </section>
        <AppCard className="notifications-detail">
          {selected ? <><span className="notifications-detail__eyebrow">{selected.isRead ? 'Read notification' : markingIds.includes(selected.id) ? 'Marking as read…' : 'Unread notification'}</span><h2>{selected.title}</h2><time dateTime={selected.createdAt}>{notificationTime(selected.createdAt)}</time><p>{selected.message}</p>{markError?.id === selected.id && <div role="alert" className="shared-notice shared-notice--error">{markError.message} Select this notification to try again.</div>}</>
            : <div className="notifications-detail__placeholder"><Icon name="bell" size={26} /><h2>Select a notification</h2><p>Choose an update to read its full message.</p></div>}
        </AppCard>
      </div>
      <nav className="notifications-pagination" aria-label="Notification pages"><button className="shared-button shared-button--outline" type="button" onClick={() => goToPage(page - 1)} disabled={!data.pagination.hasPreviousPage}>Previous</button><span>Page {data.pagination.page} of {data.pagination.totalPages}</span><button className="shared-button shared-button--outline" type="button" onClick={() => goToPage(page + 1)} disabled={!data.pagination.hasNextPage}>Next</button></nav>
    </>}
  </main>
}
