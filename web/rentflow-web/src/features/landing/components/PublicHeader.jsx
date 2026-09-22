import { Link } from 'react-router-dom'
import { BrandMark } from '../../../shared/ui/BrandLogo.jsx'
import { useAutoHideNavbar } from '../useAutoHideNavbar.js'

const links = [
  { href: '#platform', label: 'Platform' },
  { href: '#how-it-works', label: 'How It Works' },
  { href: '#smart-assistance', label: 'Smart Assistance' },
]

export default function PublicHeader({ onSignIn, isSignInPending }) {
  const { isAtTop, isVisible } = useAutoHideNavbar()

  const headerClassName = [
    'public-header',
    isAtTop ? 'public-header--top' : 'public-header--scrolled',
    isVisible ? 'public-header--visible' : 'public-header--hidden',
  ].filter(Boolean).join(' ')

  return <header className={headerClassName} data-surface={isAtTop ? 'transparent' : 'dark'} data-visible={isVisible ? 'true' : 'false'}>
    <div className="landing-container public-header__inner">
      <a className="public-header__brand" href="#top" aria-label="RentFlow AI home">
        <BrandMark className="public-header__mark" decorative />
        <span className="public-header__brand-name">RentFlow <strong>AI</strong></span>
      </a>
      <nav id="public-navigation" className="public-header__nav" aria-label="Landing page navigation">
        <div className="public-header__links">
          {links.map((link) => <a key={link.href} href={link.href}>{link.label}</a>)}
        </div>
        <div className="public-header__actions">
          <button className="landing-button landing-button--ghost" type="button" onClick={onSignIn} disabled={isSignInPending}>{isSignInPending ? 'Restoring…' : 'Sign In'}</button>
          <Link className="landing-button landing-button--light" to="/register">Get Started</Link>
        </div>
      </nav>
      <button className="public-header__mobile-signin" type="button" onClick={onSignIn} disabled={isSignInPending}>{isSignInPending ? 'Restoring…' : 'Sign In'}</button>
    </div>
  </header>
}
