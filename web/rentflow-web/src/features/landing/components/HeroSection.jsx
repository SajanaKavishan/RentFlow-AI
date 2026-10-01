import { Link } from 'react-router-dom'
import Icon from '../../../shared/ui/Icons.jsx'
import { useAuth } from '../../auth/useAuth.js'
import { heroActionsForSession } from '../publicNavigation.js'

export default function HeroSection() {
  const { isAuthenticated, user } = useAuth()
  const actions = heroActionsForSession(isAuthenticated, user?.role)

  return <section id="top" className="landing-hero" aria-labelledby="landing-title">
    <div className="landing-hero__image" aria-hidden="true" />
    <div className="landing-hero__overlay" aria-hidden="true" />
    <div className="landing-container landing-hero__content">
      <div className="landing-hero__copy">
        <p className="landing-eyebrow landing-eyebrow--light">A better way to rent</p>
        <h1 id="landing-title">Find your perfect home, smarter.</h1>
        <p className="landing-hero__intro">AI-powered rental search and management for a simpler rental journey.</p>
      </div>
      <div className="landing-hero__actions">
        {actions.map((action) => action.primary
          ? <Link className="landing-button landing-button--sage" to={action.path} key={action.label}>{action.label} <Icon name="arrow" size={18} /></Link>
          : <Link className="landing-hero__explore" to={action.path} key={action.label}>{action.label}</Link>)}
      </div>
    </div>
  </section>
}
