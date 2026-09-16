import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import Icon from '../../../shared/ui/Icons.jsx'
import { BrandMark } from '../../../shared/ui/BrandLogo.jsx'
import { useAutoHideNavbar } from '../useAutoHideNavbar.js'

const links = [
  { href: '#platform', label: 'Platform' },
  { href: '#how-it-works', label: 'How It Works' },
  { href: '#smart-assistance', label: 'Smart Assistance' },
]

export default function PublicHeader({ onSignIn, isSignInPending }) {
  const [menuOpen, setMenuOpen] = useState(false)
  const menuButtonRef = useRef(null)
  const { isAtTop, isVisible } = useAutoHideNavbar(menuOpen)

  useEffect(() => {
    if (!menuOpen) return undefined
    const onKeyDown = (event) => {
      if (event.key === 'Escape') {
        setMenuOpen(false)
        menuButtonRef.current?.focus()
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [menuOpen])

  const closeMenu = () => setMenuOpen(false)

  const headerClassName = [
    'public-header',
    isAtTop ? 'public-header--top' : 'public-header--scrolled',
    isVisible ? 'public-header--visible' : 'public-header--hidden',
    menuOpen ? 'public-header--menu-open' : '',
  ].filter(Boolean).join(' ')

  return <header className={headerClassName} data-surface={isAtTop ? 'transparent' : 'dark'} data-visible={isVisible ? 'true' : 'false'}>
    <div className="landing-container public-header__inner">
      <a className="public-header__brand" href="#top" aria-label="RentFlow AI home">
        <BrandMark className="public-header__mark" decorative />
        <span className="public-header__brand-name">RentFlow <strong>AI</strong></span>
      </a>
      <nav id="public-navigation" className={`public-header__nav${menuOpen ? ' public-header__nav--open' : ''}`} aria-label="Landing page navigation">
        <div className="public-header__links">
          {links.map((link) => <a key={link.href} href={link.href} onClick={closeMenu}>{link.label}</a>)}
        </div>
        <div className="public-header__actions">
          <button className="landing-button landing-button--ghost" type="button" onClick={() => { closeMenu(); onSignIn() }} disabled={isSignInPending}>{isSignInPending ? 'Restoring…' : 'Sign In'}</button>
          <Link className="landing-button landing-button--light" to="/register" onClick={closeMenu}>Get Started</Link>
        </div>
      </nav>
      <button ref={menuButtonRef} className="public-header__menu" type="button" aria-label={menuOpen ? 'Close menu' : 'Open menu'} aria-expanded={menuOpen} aria-controls="public-navigation" onClick={() => setMenuOpen((open) => !open)}>
        <Icon name={menuOpen ? 'close' : 'menu'} size={24} />
      </button>
    </div>
  </header>
}
