import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, Outlet, useLocation } from 'react-router-dom'
import { useAuth } from '../../features/auth/useAuth.js'
import { navigationForRole } from '../navigation/roleNavigation.js'
import Icon from '../ui/Icons.jsx'
import { BrandWordmark } from '../ui/BrandLogo.jsx'
import { initialsForName } from '../ui/userDisplay.js'
import { USER_ROLES } from '../../features/auth/authModel.js'
import { propertyIdFromLocation } from '../property/usePropertyContext.js'
import { getUnreadCount } from '../../features/notifications/notificationsApi.js'
import { NotificationCountContext } from '../../features/notifications/NotificationCountContext.js'
import { PendingViewingsContext } from './PendingViewingsContext.js'
import { PendingApplicationsContext } from './PendingApplicationsContext.js'
import { getViewingsByProperty, VIEWING_STATUS } from '../../features/viewings/services/viewingApiService.js'
import { getApplicationsByProperty, RENTAL_APPLICATION_STATUS } from '../../features/rentalApplications/services/rentalApplicationApiService.js'
import './shell.css'

function navigationPath(pathname) {
  if (pathname.startsWith('/notifications/')) return '/notifications'
  const scoped = /^\/properties\/[^/]+\/(viewing-requests|rental-applications|ai-review)\/?$/.exec(pathname)
  return scoped ? `/${scoped[1]}` : pathname
}

function iconForItem(label) {
  if (label === 'Dashboard') return 'home'
  if (label === 'Profile') return 'user'
  if (/Viewing|Viewings/.test(label)) return 'calendar'
  if (/Maintenance/.test(label)) return 'tools'
  if (/Application|AI|System|Lease|Payment/.test(label)) return 'document'
  return 'building'
}

function pendingCountForProperty(records, propertyId, isPending) {
  if (!Array.isArray(records) || records.some((record) =>
    !record || typeof record.id !== 'string' || !record.id.trim() ||
    typeof record.propertyId !== 'string' || record.propertyId.toLowerCase() !== propertyId.toLowerCase() ||
    !Number.isInteger(record.status)) || new Set(records.map((record) => record.id.toLowerCase())).size !== records.length) return null
  return records.filter(isPending).length
}

export default function AppShell() {
  const { user, logout } = useAuth()
  const portalRole = user.role === USER_ROLES.MAINTENANCE_TECHNICIAN ? 'Technician' : user.role
  const location = useLocation()
  const [countResult, setCountResult] = useState(null)
  const unreadCount = countResult?.userId === user.id ? countResult.count : null
  const countRequest = useRef(0)
  const refreshCount = useCallback(() => {
    const request = ++countRequest.current
    return getUnreadCount().then((count) => {
      if (request === countRequest.current) setCountResult({ userId: user.id, count })
    }).catch(() => {
      if (request === countRequest.current) setCountResult({ userId: user.id, count: null })
    })
  }, [user.id])
  useEffect(() => {
    const requestCounter = countRequest
    refreshCount()
    return () => { requestCounter.current++ }
  }, [location.pathname, user.id, refreshCount])
  const propertyId = user.role === USER_ROLES.LANDLORD ? propertyIdFromLocation(location) : null
  const [viewingSummary, setViewingSummary] = useState(null)
  const [applicationSummary, setApplicationSummary] = useState(null)
  const [dismissedViewings, setDismissedViewings] = useState(null)
  const [dismissedApplications, setDismissedApplications] = useState(null)
  const publishPendingViewings = useCallback((summaryPropertyId, count) => {
    setViewingSummary({ userId: user.id, propertyId: summaryPropertyId, count })
  }, [user.id])
  const publishPendingApplications = useCallback((summaryPropertyId, count) => {
    setApplicationSummary({ userId: user.id, propertyId: summaryPropertyId, count })
  }, [user.id])
  const pendingViewings = viewingSummary?.userId === user.id && viewingSummary.propertyId === propertyId
    ? viewingSummary.count : null
  const pendingApplications = applicationSummary?.userId === user.id && applicationSummary.propertyId === propertyId
    ? applicationSummary.count : null
  const shownViewings = pendingViewings > 0 && !(
    dismissedViewings?.userId === user.id && dismissedViewings.propertyId === propertyId &&
    pendingViewings <= dismissedViewings.count
  ) ? pendingViewings : 0
  const shownApplications = pendingApplications > 0 && !(
    dismissedApplications?.userId === user.id && dismissedApplications.propertyId === propertyId &&
    pendingApplications <= dismissedApplications.count
  ) ? pendingApplications : 0
  const activePath = navigationPath(location.pathname)
  useEffect(() => {
    if (user.role !== USER_ROLES.LANDLORD || !propertyId || activePath === '/dashboard' ||
      (viewingSummary?.userId === user.id && viewingSummary.propertyId === propertyId && viewingSummary.count !== null)) return undefined
    let active = true
    getViewingsByProperty(propertyId).then((records) => {
      const count = pendingCountForProperty(records, propertyId, (record) => record.status === VIEWING_STATUS.PENDING)
      if (active && count !== null) setViewingSummary({ userId: user.id, propertyId, count })
    }).catch(() => {})
    return () => { active = false }
  }, [user.id, user.role, propertyId, activePath, viewingSummary])
  useEffect(() => {
    if (user.role !== USER_ROLES.LANDLORD || !propertyId || activePath === '/dashboard' ||
      (applicationSummary?.userId === user.id && applicationSummary.propertyId === propertyId && applicationSummary.count !== null)) return undefined
    let active = true
    getApplicationsByProperty(propertyId).then((records) => {
      const count = pendingCountForProperty(records, propertyId, (record) =>
        [RENTAL_APPLICATION_STATUS.SUBMITTED, RENTAL_APPLICATION_STATUS.UNDER_REVIEW].includes(record.status))
      if (active && count !== null) setApplicationSummary({ userId: user.id, propertyId, count })
    }).catch(() => {})
    return () => { active = false }
  }, [user.id, user.role, propertyId, activePath, applicationSummary])
  const scopedPath = (path) => propertyId ? `${path}?${new URLSearchParams({ propertyId })}` : path
  const [menu, setMenu] = useState({ path: location.pathname, open: false })
  const menuOpen = menu.path === location.pathname && menu.open
  const menuRef = useRef(null)
  const sidebarRef = useRef(null)
  useEffect(() => {
    if (!menuOpen) return undefined
    const sidebar = sidebarRef.current
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    sidebar?.querySelector('a[href]')?.focus()
    const desktop = window.matchMedia('(min-width: 901px)')
    const onDesktop = (event) => {
      if (event.matches) setMenu({ path: location.pathname, open: false })
    }
    const onKeyDown = (event) => {
      if (event.key === 'Escape') { setMenu({ path: location.pathname, open: false }); menuRef.current?.focus() }
      if (event.key === 'Tab' && sidebar) {
        const focusable = Array.from(sidebar.querySelectorAll('a[href], button:not([disabled])'))
        if (!focusable.length) return
        const first = focusable[0]
        const last = focusable[focusable.length - 1]
        if (event.shiftKey && (document.activeElement === first || !sidebar.contains(document.activeElement))) { event.preventDefault(); last.focus() }
        else if (!event.shiftKey && (document.activeElement === last || !sidebar.contains(document.activeElement))) { event.preventDefault(); first.focus() }
      }
    }
    window.addEventListener('keydown', onKeyDown)
    desktop.addEventListener('change', onDesktop)
    return () => {
      document.body.style.overflow = previousOverflow
      window.removeEventListener('keydown', onKeyDown)
      desktop.removeEventListener('change', onDesktop)
    }
  }, [menuOpen, location.pathname])
  const items = navigationForRole(user.role)
  const current = (activePath === '/dashboard' ? `${portalRole} Portal` : activePath === '/notifications' ? 'Notifications' : activePath === '/viewing-requests' ? 'Viewings Management' : activePath === '/rental-applications' ? 'Applications Management' : items.find((item) => item.path === activePath)?.label)
    || (location.pathname === '/unauthorized' ? 'Access restricted' : 'RentFlow AI')
  const closeMenu = () => { setMenu({ path: location.pathname, open: false }); if (menuOpen) menuRef.current?.focus() }
  const navLink = (item) => {
    const badgeCount = item.id === 'viewing-requests' ? shownViewings : item.id === 'rental-applications' ? shownApplications : 0
    return <Link key={`${item.label}-${item.path}`} to={scopedPath(item.path)} aria-current={activePath === item.path ? 'page' : undefined} aria-label={badgeCount ? `${item.label}, ${badgeCount} pending` : undefined} onClick={() => {
    if (item.id === 'viewing-requests' && shownViewings) setDismissedViewings({ userId: user.id, propertyId, count: shownViewings })
    if (item.id === 'rental-applications' && shownApplications) setDismissedApplications({ userId: user.id, propertyId, count: shownApplications })
    closeMenu()
  }} className={`shared-nav-link${activePath === item.path ? ' shared-nav-link--active' : ''}`}>
    <Icon name={iconForItem(item.label)} size={19} /><span className="shared-nav-link__label">{item.label}</span>{badgeCount > 0 && <span className="shared-nav-link__pending" aria-hidden="true">{badgeCount}</span>}{!item.available && <span className="shared-nav-link__soon">Soon</span>}
  </Link>
  }

  return <div className="shared-shell">
    <aside ref={sidebarRef} id="shared-navigation" role={menuOpen ? 'dialog' : undefined} aria-modal={menuOpen ? 'true' : undefined} aria-label={menuOpen ? 'Navigation menu' : undefined} className={`shared-sidebar${menuOpen ? ' shared-sidebar--open' : ''}`}>
      <Link className="shared-brand" to={scopedPath('/dashboard')} aria-label="RentFlow dashboard" onClick={closeMenu}>
        <BrandWordmark className="shared-brand__image" decorative />
        <span className="shared-brand__tagline">A better way to rent</span>
      </Link>
      <span className="shared-brand__workspace">{portalRole} workspace</span>
      <nav aria-label="Primary navigation" className="shared-sidebar__nav">
        <div className="shared-sidebar__nav-main">{items.filter((item) => item.path !== '/profile').map(navLink)}</div>
        <div className="shared-sidebar__nav-bottom">{items.filter((item) => item.path === '/profile').map(navLink)}
          <button className="shared-nav-link shared-nav-link--button" type="button" onClick={logout}><Icon name="logout" size={19} /><span className="shared-nav-link__label">Logout</span></button>
        </div>
      </nav>
    </aside>
    {menuOpen && <button type="button" className="shared-nav-scrim" aria-label="Close navigation" onClick={() => { closeMenu(); menuRef.current?.focus() }} />}
    <div className="shared-shell__body">
      <header className="shared-topbar">
        <button ref={menuRef} type="button" className="shared-menu-button" aria-label={menuOpen ? 'Close navigation' : 'Open navigation'} aria-expanded={menuOpen} aria-controls="shared-navigation" onClick={() => setMenu({ path: location.pathname, open: !menuOpen })}><Icon name={menuOpen ? 'close' : 'menu'} size={22} /></button>
        <div className="shared-topbar__title"><strong>{current}</strong></div>
        <Link className="shared-topbar__notifications" to="/notifications" onClick={closeMenu} aria-label={unreadCount > 0 ? `Notifications, ${unreadCount} unread` : 'Notifications'} aria-current={activePath === '/notifications' ? 'page' : undefined}><Icon name="bell" size={21} />{unreadCount > 0 && <span className="shared-topbar__notification-count" aria-hidden="true">{unreadCount}</span>}</Link>
        <Link className="shared-topbar__account" to={scopedPath('/profile')} title={user.email} onClick={closeMenu} aria-label={`Profile for ${user.fullName}`}><span className="shared-topbar__identity"><span className="shared-topbar__name">{user.fullName}</span></span><span className="shared-avatar" aria-hidden="true">{initialsForName(user.fullName)}</span></Link>
      </header>
      <NotificationCountContext.Provider value={{ refreshCount }}><PendingViewingsContext.Provider value={publishPendingViewings}><PendingApplicationsContext.Provider value={publishPendingApplications}><div className="shared-shell__content"><Outlet key={user.id} /></div></PendingApplicationsContext.Provider></PendingViewingsContext.Provider></NotificationCountContext.Provider>
    </div>
  </div>
}
