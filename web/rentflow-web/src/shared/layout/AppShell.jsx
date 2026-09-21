import { useEffect, useRef, useState } from 'react'
import { Link, Outlet, useLocation } from 'react-router-dom'
import { useAuth } from '../../features/auth/useAuth.js'
import { navigationForRole } from '../navigation/roleNavigation.js'
import Icon from '../ui/Icons.jsx'
import { BrandWordmark } from '../ui/BrandLogo.jsx'
import { initialsForName } from '../ui/userDisplay.js'
import { USER_ROLES } from '../../features/auth/authModel.js'
import { propertyIdFromLocation } from '../property/usePropertyContext.js'
import './shell.css'

function navigationPath(pathname) {
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

export default function AppShell() {
  const { user, logout } = useAuth()
  const roleLabel = user.role === USER_ROLES.MAINTENANCE_TECHNICIAN
    ? 'Maintenance technician' : user.role
  const location = useLocation()
  const propertyId = user.role === USER_ROLES.LANDLORD ? propertyIdFromLocation(location) : null
  const activePath = navigationPath(location.pathname)
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
  const current = items.find((item) => item.path === activePath)?.label
    || (location.pathname === '/unauthorized' ? 'Access restricted' : 'RentFlow AI')
  const closeMenu = () => { setMenu({ path: location.pathname, open: false }); if (menuOpen) menuRef.current?.focus() }
  const navLink = (item) => <Link key={`${item.label}-${item.path}`} to={scopedPath(item.path)} aria-current={activePath === item.path ? 'page' : undefined} onClick={closeMenu} className={`shared-nav-link${activePath === item.path ? ' shared-nav-link--active' : ''}`}>
    <Icon name={iconForItem(item.label)} size={19} /><span className="shared-nav-link__label">{item.label}</span>{!item.available && <span className="shared-nav-link__soon">Soon</span>}
  </Link>

  return <div className="shared-shell">
    <aside ref={sidebarRef} id="shared-navigation" role={menuOpen ? 'dialog' : undefined} aria-modal={menuOpen ? 'true' : undefined} aria-label={menuOpen ? 'Navigation menu' : undefined} className={`shared-sidebar${menuOpen ? ' shared-sidebar--open' : ''}`}>
      <Link className="shared-brand" to={scopedPath('/dashboard')} aria-label="RentFlow dashboard" onClick={closeMenu}>
        <BrandWordmark className="shared-brand__image" decorative />
        <span className="shared-brand__tagline">A better way to rent</span>
      </Link>
      <button className="shared-sidebar__close" type="button" aria-label="Close menu" onClick={closeMenu}><Icon name="close" size={20} /></button>
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
        <div className="shared-topbar__title"><span className="shared-topbar__eyebrow">{roleLabel} workspace</span><strong>{current}</strong></div>
        <Link className="shared-topbar__account" to={scopedPath('/profile')} title={user.email} onClick={closeMenu} aria-label={`Profile for ${user.fullName}`}><span className="shared-topbar__identity"><span className="shared-topbar__name">{user.fullName}</span><span className="shared-topbar__role">{roleLabel}</span></span><span className="shared-avatar" aria-hidden="true">{initialsForName(user.fullName)}</span></Link>
      </header>
      <div className="shared-shell__content"><Outlet /></div>
    </div>
  </div>
}
