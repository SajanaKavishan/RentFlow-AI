import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../auth/useAuth.js'
import { getNotifications, markNotificationRead } from './notificationsApi.js'
import { notificationDestination, notificationNavigationError } from './notificationNavigation.js'
import { notificationTime } from './notificationFormat.js'
import { notificationTypeLabel, SUPPORTED_NOTIFICATION_TYPES } from './notificationTypes.js'
import { useNotificationCount } from './NotificationCountContext.js'
import { AppCard, PageHeader } from '../../shared/ui/States.jsx'
import Icon from '../../shared/ui/Icons.jsx'
import './notifications.css'

export default function NotificationsPage() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const { refreshCount } = useNotificationCount()
  const [page, setPage] = useState(1)
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [selectedId, setSelectedId] = useState(null)
  const [markingIds, setMarkingIds] = useState([])
  const [markError, setMarkError] = useState(null)
  const [navigationError, setNavigationError] = useState(null)
  const [openingId, setOpeningId] = useState(null)
  const [readFilter, setReadFilter] = useState('all')
  const [typeFilter, setTypeFilter] = useState('all')
  const [reload, setReload] = useState(0)
  const requestId = useRef(0)
  const markingRef = useRef(new Set())
  const openingRef = useRef(new Set())
  const selectedRef = useRef(null)
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
  }, [page, reload, user.id])

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
    setNavigationError(null)
    setSelectedId(null)
    selectedRef.current = null
  }

  const select = async (item) => {
    selectedRef.current = item.id
    setSelectedId(item.id)
    setMarkError(null)
    setNavigationError(null)
    if (openingRef.current.has(item.id)) return
    openingRef.current.add(item.id)
    setOpeningId(item.id)
    try {
      if (!item.isRead) {
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
          return
        } finally {
          markingRef.current.delete(item.id)
          if (mounted.current) setMarkingIds(Array.from(markingRef.current))
        }
      }
      if (!mounted.current || selectedRef.current !== item.id) return
      try {
        const path = await notificationDestination(item, user.role)
        if (mounted.current && selectedRef.current === item.id) navigate(path)
      } catch (failure) {
        if (mounted.current && selectedRef.current === item.id) {
          setNavigationError({ id: item.id, message: notificationNavigationError(failure) })
        }
      }
    } finally {
      openingRef.current.delete(item.id)
      if (mounted.current) setOpeningId(null)
    }
  }

  const selected = data?.items.find((item) => item.id === selectedId)
  const filteredItems = useMemo(() => (data?.items || []).filter((item) => {
    const matchesRead = readFilter === 'all'
      || (readFilter === 'unread' && !item.isRead)
      || (readFilter === 'read' && item.isRead)
    return matchesRead && (typeFilter === 'all' || item.eventType === typeFilter)
  }), [data, readFilter, typeFilter])
  const filtersActive = readFilter !== 'all' || typeFilter !== 'all'
  const clearFilters = () => { setReadFilter('all'); setTypeFilter('all') }

  return <main className="shared-page notifications-page">
    <div className="notifications-page__heading"><PageHeader eyebrow="Your updates" title="Notifications"><p>Updates for your account, newest first.</p></PageHeader><button className="shared-button shared-button--outline" type="button" onClick={refresh} disabled={loading}><Icon name="refresh" size={18} />Refresh</button></div>
    {!loading && !error && data?.items.length > 0 && <section className="notification-filters" aria-label="Notification filters">
      <div className="notification-filters__status" role="group" aria-label="Read status">
        {['all', 'unread', 'read'].map((filter) => <button key={filter} type="button" className={readFilter === filter ? 'notification-filter--active' : ''} aria-pressed={readFilter === filter} onClick={() => setReadFilter(filter)}>{filter[0].toUpperCase() + filter.slice(1)}</button>)}
      </div>
      <label>Type
        <select aria-label="Notification type" value={typeFilter} onChange={(event) => setTypeFilter(event.target.value)}>
          <option value="all">All supported types</option>
          {SUPPORTED_NOTIFICATION_TYPES.map((type) => <option key={type.value} value={type.value}>{type.label}</option>)}
        </select>
      </label>
      <p>Filters apply to the {data.items.length} notifications loaded on this page.</p>
    </section>}
    {loading && <div className="notifications-feedback" role="status"><span className="shared-spinner" aria-hidden="true" />Loading notifications…</div>}
    {!loading && error && <div className="notifications-feedback" role="alert"><strong>Notifications could not be loaded.</strong><p>{error}</p><button className="shared-button" type="button" onClick={refresh}>Try again</button></div>}
    {!loading && !error && data?.items.length === 0 && <AppCard className="notifications-feedback"><span className="notifications-feedback__icon"><Icon name="bell" size={26} /></span><h2>No notifications yet</h2><p>Updates for your account will appear here.</p></AppCard>}
    {!loading && !error && data?.items.length > 0 && filteredItems.length === 0 && <AppCard className="notifications-feedback"><span className="notifications-feedback__icon"><Icon name="bell" size={26} /></span><h2>No matching notifications on this page</h2><p>Try another filter or move to a different page.</p>{filtersActive && <button className="shared-button shared-button--outline" type="button" onClick={clearFilters}>Clear filters</button>}</AppCard>}
    {!loading && !error && data?.items.length > 0 && <>
      {filteredItems.length > 0 && <div className="notifications-layout">
        <section className="notifications-list" aria-label="Notification list">
          {filteredItems.map((item) => <button key={item.id} type="button" className={`notification-item${item.isRead ? '' : ' notification-item--unread'}${selectedId === item.id ? ' notification-item--selected' : ''}`} aria-pressed={selectedId === item.id} onClick={() => select(item)}>
            <span className="notification-item__top"><strong>{item.title}</strong><span className="notification-item__state">{item.isRead ? 'Read' : 'Unread'}</span></span>
            <span className="notification-type">{notificationTypeLabel(item.eventType)}</span>
            <span className="notification-item__message">{item.message}</span>
            <time dateTime={item.createdAt}>{notificationTime(item.createdAt)}</time>
          </button>)}
        </section>
        <AppCard className="notifications-detail">
          {selected ? <><span className="notifications-detail__eyebrow">{markingIds.includes(selected.id) ? 'Marking as read…' : openingId === selected.id ? 'Opening related record…' : selected.isRead ? 'Read notification' : 'Unread notification'}</span><h2>{selected.title}</h2><span className="notification-type">{notificationTypeLabel(selected.eventType)}</span><time dateTime={selected.createdAt}>{notificationTime(selected.createdAt)}</time><p>{selected.message}</p>{markError?.id === selected.id && <div role="alert" className="shared-notice shared-notice--error">{markError.message} Select this notification to try again.</div>}{navigationError?.id === selected.id && <div role="alert" className="shared-notice shared-notice--error">{navigationError.message} Select this notification to try again.</div>}</>
            : <div className="notifications-detail__placeholder"><Icon name="bell" size={26} /><h2>Select a notification</h2><p>Choose an update to read its full message.</p></div>}
        </AppCard>
      </div>}
      <nav className="notifications-pagination" aria-label="Notification pages"><button className="shared-button shared-button--outline" type="button" onClick={() => goToPage(page - 1)} disabled={!data.pagination.hasPreviousPage}>Previous</button><span>Page {data.pagination.page} of {data.pagination.totalPages}</span><button className="shared-button shared-button--outline" type="button" onClick={() => goToPage(page + 1)} disabled={!data.pagination.hasNextPage}>Next</button></nav>
    </>}
  </main>
}
