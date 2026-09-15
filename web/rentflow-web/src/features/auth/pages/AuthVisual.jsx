import residence from '../../../assets/auth-residence.png'

export default function AuthVisual() {
  return <aside className="auth-visual" style={{ backgroundImage: `linear-gradient(180deg, rgb(24 30 19 / 34%), rgb(24 30 19 / 30%) 38%, rgb(24 30 19 / 82%)), url(${residence})` }}>
    <div className="auth-visual__brand"><span className="auth-visual__mark" aria-hidden="true">R</span><span>RentFlow <small>AI</small></span></div>
    <div className="auth-visual__copy"><span className="auth-visual__kicker">A better way to rent</span><h2>Find your perfect home, smarter.</h2><p>AI-powered rental search and management.</p><div className="auth-visual__trust"><span>Thoughtful rental journeys</span><span>One place for your next move</span></div></div>
  </aside>
}
