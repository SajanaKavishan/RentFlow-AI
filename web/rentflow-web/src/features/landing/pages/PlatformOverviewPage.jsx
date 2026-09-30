import { Link } from 'react-router-dom'
import Icon from '../../../shared/ui/Icons.jsx'
import PublicPageLayout from '../components/PublicPageLayout.jsx'

const roles = [
  {
    role: 'Tenant',
    title: 'Find and manage your next home',
    icon: 'search',
    features: ['Browse available properties', 'Set preferences and review property matches', 'Open property details and listing information', 'Request and manage viewings', 'Submit and track rental applications', 'Review lease, rent schedule and payment information'],
    cta: 'Get Started as Tenant',
    path: '/register?role=tenant',
  },
  {
    role: 'Landlord',
    title: 'Run your rental portfolio',
    icon: 'building',
    features: ['Add, edit and manage properties', 'Manage property images and map locations', 'Review viewing requests', 'Review rental applications and documents', 'Set listing preferences and amenities', 'Use property and portfolio dashboard views'],
    cta: 'Get Started as Landlord',
    path: '/register?role=landlord',
  },
  {
    role: 'Technician',
    title: 'Stay focused on assigned work',
    icon: 'tools',
    features: ['Review assigned maintenance requests', 'See priority, category and current job status', 'Use account notifications and profile tools'],
    cta: 'Technician Sign In',
    path: '/login',
  },
  {
    role: 'Admin',
    title: 'Oversee the platform securely',
    icon: 'shield',
    features: ['Access the authorized user directory', 'Provision Technician accounts', 'Manage support requests', 'Review the available system overview'],
    cta: 'Admin Sign In',
    path: '/login',
  },
]

export default function PlatformOverviewPage() {
  return <PublicPageLayout>
    <main className="public-page__main">
      <section className="public-page__hero" aria-labelledby="platform-overview-title">
        <div className="landing-container public-page__hero-inner">
          <p className="landing-eyebrow">The platform</p>
          <h1 id="platform-overview-title">One rental platform. A workspace for every role.</h1>
          <p>Explore what RentFlow supports before you sign in. Each workspace remains private and role-protected.</p>
        </div>
      </section>
      <section className="public-page__section" aria-label="RentFlow workspaces">
        <div className="landing-container public-role-grid">
          {roles.map((item) => <article className="public-info-card public-role-card" key={item.role}>
            <header><span className="public-info-card__icon"><Icon name={item.icon} size={24} /></span><p>{item.role}</p></header>
            <h2>{item.title}</h2>
            <ul>{item.features.map((feature) => <li key={feature}>{feature}</li>)}</ul>
            <Link className="landing-button public-page__button" to={item.path}>{item.cta}<Icon name="arrow" size={17} /></Link>
          </article>)}
        </div>
      </section>
    </main>
  </PublicPageLayout>
}

