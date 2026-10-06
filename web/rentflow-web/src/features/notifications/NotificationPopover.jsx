import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../auth/useAuth.js'
import Icon from '../../shared/ui/Icons.jsx'
import { getNotifications, markNotificationRead } from './notificationsApi.js'
import { notificationTime } from './notificationFormat.js'
import { notificationTypeLabel } from './notificationTypes.js'
import { notificationDestination } from './notificationNavigation.js'
import './notifications.css'

const PREVIEW_SIZE = 5

export default function NotificationPopover({ userId, unreadCount, refreshCount, onOpen }) {
  const location = useLocation()
  const navigate = useNavigate()
  const { user } = useAuth()
  const [popover, setPopover] = useState({ userId, path: location.pathname, open: false })
  const [result, setResult] = useState({ userId, items: [], status: 'idle', error: '' })
  const [markingId, setMarkingId] = useState(null)
  const [markError, setMarkError] = useState(null)
  const [reload, setReload] = useState(0)
  const triggerRef = useRef(null)
  const popupRef = useRef(null)
  const wrapperRef = useRef(null)
  const requestId = useRef(0)
  const mounted = useRef(true)
  const open = popover.userId === userId && popover.path === location.pathname && popover.open
  const currentResult = result.userId === userId
    ? result
    : { userId, items: [], status: 'idle', error: '' }
  const { items, status, error } = currentResult

  useEffect(() => {
    mounted.current = true
    return () => { mounted.current = false }
  }, [])

  const close = useCallback((restoreFocus = false) => {
    setPopover({ userId, path: location.pathname, open: false })
    if (restoreFocus) triggerRef.current?.focus()
  }, [location.pathname, userId])

  useEffect(() => {
    if (!open) return undefined
    const currentRequest = ++requestId.current
    const requestCounter = requestId
    const requestedUserId = userId
    getNotifications(1, PREVIEW_SIZE).then((response) => {
      if (currentRequest !== requestId.current) return
      setResult({ userId: requestedUserId, items: response.items, status: 'ready', error: '' })
    }).catch((failure) => {
      if (currentRequest !== requestId.current) return
      setResult({ userId: requestedUserId, items: [], status: 'error', error: failure.message })
    })
    return () => { requestCounter.current++ }
  }, [open, reload, userId])

  useEffect(() => {
    if (!open) return undefined
    popupRef.current?.focus()
    const onPointerDown = (event) => {
      if (!wrapperRef.current?.contains(event.target)) close(false)
    }
    const onKeyDown = (event) => {
      if (event.key === 'Escape') close(true)
    }
    document.addEventListener('mousedown', onPointerDown)
    window.addEventListener('keydown', onKeyDown)
    return () => {
      document.removeEventListener('mousedown', onPointerDown)
      window.removeEventListener('keydown', onKeyDown)
    }
  }, [close, open])

  const toggle = () => {
    const nextOpen = !open
    setPopover({ userId, path: location.pathname, open: nextOpen })
    if (nextOpen) {
      setResult({ userId, items: [], status: 'loading', error: '' })
      setMarkingId(null)
      setMarkError(null)
      onOpen?.()
    }
  }

  const markRead = async (item) => {
    if (item.isRead || markingId) return true
    const requestedUserId = userId
    setMarkingId(item.id)
    setMarkError(null)
    try {
      const updated = await markNotificationRead(item.id)
      if (!mounted.current) return
      setResult((current) => current.userId !== requestedUserId ? current : {
        ...current,
        items: current.items.map((entry) => entry.id === item.id ? updated : entry),
      })
      refreshCount()
      return true
    } catch (failure) {
      if (mounted.current) setMarkError({ id: item.id, message: failure.message })
      return false
    } finally {
      if (mounted.current) setMarkingId(null)
    }

  }

  const openNotification = async (item) => {
    setMarkError(null)
    try {
      if (!item.isRead && !await markRead(item)) return
      const destination = await notificationDestination(item, user.role)
      if (destination) {
        close(false)
        navigate(destination)
      }
    } catch (failure) {
      if (mounted.current) setMarkError({ id: item.id, message: failure.message })
    }
  }

  const label = Number.isInteger(unreadCount) && unreadCount > 0
    ? `Notifications, ${unreadCount} unread`
    : 'Notifications'

  return <div className="notification-popover" ref={wrapperRef}>
    <Link
      ref={triggerRef}
      className="shared-topbar__notifications"
      to="/notifications"
      aria-label={label}
      aria-haspopup="dialog"
      aria-expanded={open}
      aria-controls="notification-preview"
      onClick={(event) => { event.preventDefault(); toggle() }}
    >
      <Icon name="bell" size={21} />
      {Number.isInteger(unreadCount) && unreadCount > 0 && <span className="shared-topbar__notification-count" aria-hidden="true">{unreadCount}</span>}
    </Link>
    {open && <section
      id="notification-preview"
      ref={popupRef}
      className="notification-popover__panel"
      role="dialog"
      aria-label="Recent notifications"
      tabIndex="-1"
    >
      <div className="notification-popover__header">
        <span><strong>Notifications</strong><small>Most recent for your account</small></span>
        <button type="button" aria-label="Close notifications" onClick={() => close(true)}><Icon name="close" size={18} /></button>
      </div>
      <div className="notification-popover__content">
        {status === 'loading' && <div className="notification-popover__feedback" role="status"><span className="shared-spinner" aria-hidden="true" />Loading notifications…</div>}
        {status === 'error' && <div className="notification-popover__feedback" role="alert"><strong>Notifications could not be loaded.</strong><span>{error}</span><button className="shared-button shared-button--outline" type="button" onClick={() => { setResult({ userId, items: [], status: 'loading', error: '' }); setReload((value) => value + 1) }}>Try again</button></div>}
        {status === 'ready' && items.length === 0 && <div className="notification-popover__feedback"><Icon name="bell" size={22} /><strong>No notifications yet</strong><span>Updates for your account will appear here.</span></div>}
        {status === 'ready' && items.length > 0 && <div className="notification-popover__list" aria-label="Recent notification list">
          {items.map((item) => <article key={item.id} className={`notification-preview-item${item.isRead ? '' : ' notification-preview-item--unread'}`} role="button" tabIndex="0" onClick={() => openNotification(item)} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') openNotification(item) }}>
            <div className="notification-preview-item__heading"><strong>{item.title}</strong><span>{item.isRead ? 'Read' : 'Unread'}</span></div>
            <span className="notification-type">{notificationTypeLabel(item.eventType)}</span>
            <p>{item.message}</p>
            <div className="notification-preview-item__footer">
              <time dateTime={item.createdAt}>{notificationTime(item.createdAt)}</time>
              {!item.isRead && <button type="button" disabled={markingId === item.id} onClick={(event) => { event.stopPropagation(); markRead(item) }}>{markingId === item.id ? 'Marking…' : 'Mark as read'}</button>}
            </div>
            {markError?.id === item.id && <div className="notification-preview-item__error" role="alert">{markError.message}</div>}
          </article>)}
        </div>}
      </div>
      <Link className="notification-popover__all" to="/notifications" onClick={() => close(false)}>See all notifications <Icon name="arrow" size={17} /></Link>
    </section>}
  </div>
}
