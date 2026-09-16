import { Link } from 'react-router-dom'
import { BrandWordmark } from '../../../shared/ui/BrandLogo.jsx'

export default function PublicFooter({ onSignIn, isSignInPending }) {
  return <footer className="public-footer">
    <div className="landing-container public-footer__inner">
      <div className="public-footer__brand"><a href="#top" aria-label="RentFlow AI home"><BrandWordmark className="public-footer__wordmark" decorative /></a><p>A simpler, more connected rental journey.</p></div>
      <nav className="public-footer__links" aria-label="Footer navigation">
        <a href="#platform">Platform</a><a href="#how-it-works">How It Works</a><a href="#smart-assistance">Smart Assistance</a>
        <button type="button" onClick={onSignIn} disabled={isSignInPending}>Sign In</button><Link to="/register">Create Account</Link>
      </nav>
      <p className="public-footer__copyright">© {new Date().getFullYear()} RentFlow AI</p>
    </div>
  </footer>
}
