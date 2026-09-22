import { Link } from 'react-router-dom'
import { BrandMark } from '../../../shared/ui/BrandLogo.jsx'

export default function AuthVisual() {
  return <aside className="auth-visual">
    <Link className="auth-visual__brand" to="/" aria-label="RentFlow AI home"><BrandMark className="auth-visual__mark" decorative /><span className="auth-visual__brand-name">RentFlow <strong>AI</strong></span></Link>
    <div className="auth-visual__copy"><span className="auth-visual__kicker">A better way to rent</span><h2>Find your perfect home, smarter.</h2><p>AI-powered rental search and management.</p><div className="auth-visual__trust"><span>Thoughtful rental journeys</span><span>One place for your next move</span></div></div>
  </aside>
}
