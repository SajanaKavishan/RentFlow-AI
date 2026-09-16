import { Link } from 'react-router-dom'
import Icon from '../../../shared/ui/Icons.jsx'

const benefits = ['Property discovery', 'Secure applications', 'AI-assisted review', 'Rental management']

export default function HeroSection({ onSignIn, isSignInPending }) {
  return <section id="top" className="landing-hero" aria-labelledby="landing-title">
    <div className="landing-hero__image" aria-hidden="true" />
    <div className="landing-hero__overlay" aria-hidden="true" />
    <div className="landing-container landing-hero__content">
      <p className="landing-eyebrow landing-eyebrow--light">A better way to rent</p>
      <h1 id="landing-title">Find your perfect home, smarter.</h1>
      <p className="landing-hero__intro">AI-powered rental search and management for a simpler rental journey.</p>
      <div className="landing-hero__actions">
        <Link className="landing-button landing-button--sage" to="/register">Get Started <Icon name="arrow" size={18} /></Link>
        <button className="landing-button landing-button--outline-light" type="button" onClick={onSignIn} disabled={isSignInPending}>{isSignInPending ? 'Restoring…' : 'Sign In'}</button>
        <a className="landing-hero__explore" href="#platform">Explore the platform <Icon name="arrow" size={17} /></a>
      </div>
      <ul className="landing-hero__benefits" aria-label="Platform benefits">
        {benefits.map((benefit) => <li key={benefit}><span aria-hidden="true">✓</span>{benefit}</li>)}
      </ul>
    </div>
  </section>
}
