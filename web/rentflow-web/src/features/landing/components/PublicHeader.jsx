import { useState } from 'react'
import { Link, NavLink } from 'react-router-dom'
import { BrandMark } from '../../../shared/ui/BrandLogo.jsx'
import Icon from '../../../shared/ui/Icons.jsx'
import { useAuth } from '../../auth/useAuth.js'
import { useAutoHideNavbar } from '../useAutoHideNavbar.js'
import { explorePathForSession, PUBLIC_NAVIGATION_LINKS, PUBLIC_PATHS } from '../publicNavigation.js'

export default function PublicHeader({ solid = false }) {
  const { isAuthenticated, isLoading, user } = useAuth()
  const { isAtTop, isVisible } = useAutoHideNavbar()
  const [isMenuOpen, setIsMenuOpen] = useState(false)
  const hasSurface = solid || !isAtTop
  const closeMenu = () => setIsMenuOpen(false)

  const headerClassName = [
    'public-header',
    hasSurface ? 'public-header--scrolled' : 'public-header--top',
    solid ? 'public-header--solid' : '',
    isVisible ? 'public-header--visible' : 'public-header--hidden',
  ].filter(Boolean).join(' ')

  const sessionActions = isAuthenticated
    ? <Link className="landing-button landing-button--light" to={explorePathForSession(true, user?.role)} onClick={closeMenu}>Open Workspace</Link>
    : <>
      <Link className="landing-button landing-button--ghost" to={PUBLIC_PATHS.login} onClick={closeMenu}>Sign In</Link>
      <Link className="landing-button landing-button--light" to={PUBLIC_PATHS.getStarted} onClick={closeMenu}>Get Started</Link>
    </>

  return <header className={headerClassName} data-surface={hasSurface ? 'dark' : 'transparent'} data-visible={isVisible ? 'true' : 'false'}>
    <div className="landing-container public-header__inner">
      <Link className="public-header__brand" to={PUBLIC_PATHS.home} aria-label="RentFlow AI home" onClick={closeMenu}>
        <BrandMark className="public-header__mark" decorative />
        <span className="public-header__brand-name">RentFlow <strong>AI</strong></span>
      </Link>
      <nav id="public-navigation" className={`public-header__nav${isMenuOpen ? ' is-open' : ''}`} aria-label="Landing page navigation">
        <div className="public-header__links">
          {PUBLIC_NAVIGATION_LINKS.map((link) => <NavLink key={link.path} to={link.path} onClick={closeMenu}>{link.label}</NavLink>)}
        </div>
        <div className="public-header__actions">
          {isLoading && !isAuthenticated
            ? <span className="public-header__restoring" role="status">Restoring&hellip;</span>
            : sessionActions}
        </div>
      </nav>
      <button className="public-header__menu-toggle" type="button" aria-label={isMenuOpen ? 'Close menu' : 'Open menu'} aria-expanded={isMenuOpen} aria-controls="public-navigation" onClick={() => setIsMenuOpen((open) => !open)}>
        <Icon name={isMenuOpen ? 'close' : 'menu'} size={22} />
      </button>
    </div>
  </header>
}
