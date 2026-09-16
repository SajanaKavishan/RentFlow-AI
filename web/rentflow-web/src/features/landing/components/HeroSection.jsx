import { Link } from 'react-router-dom'
import Icon from '../../../shared/ui/Icons.jsx'

export default function HeroSection() {
  return <section id="top" className="landing-hero" aria-labelledby="landing-title">
    <div className="landing-hero__image" aria-hidden="true" />
    <div className="landing-hero__overlay" aria-hidden="true" />
    <div className="landing-container landing-hero__content">
      <p className="landing-eyebrow landing-eyebrow--light">A better way to rent</p>
      <h1 id="landing-title">Find your perfect home, smarter.</h1>
      <p className="landing-hero__intro">AI-powered rental search and management for a simpler rental journey.</p>
      <div className="landing-hero__actions">
        <Link className="landing-button landing-button--sage" to="/register">Get Started <Icon name="arrow" size={18} /></Link>
        <a className="landing-hero__explore" href="#platform">Explore the platform <Icon name="arrow" size={17} /></a>
      </div>
    </div>
  </section>
}
