import { Link } from 'react-router-dom'
import { BrandMark } from '../../../shared/ui/BrandLogo.jsx'

export default function AuthVisual({
  kicker = 'A better way to rent',
  title = 'Find your perfect home, smarter.',
  description = 'AI-powered rental search and management.',
  trustItems = ['Thoughtful rental journeys', 'One place for your next move'],
}) {
  return <aside className="auth-visual">
    <Link className="auth-visual__brand" to="/" aria-label="RentFlow AI home"><BrandMark className="auth-visual__mark" decorative /><span className="auth-visual__brand-name">RentFlow <strong>AI</strong></span></Link>
    <div className="auth-visual__copy"><span className="auth-visual__kicker">{kicker}</span><h2>{title}</h2><p>{description}</p><div className="auth-visual__trust">{trustItems.map((item) => <span key={item}>{item}</span>)}</div></div>
  </aside>
}
