import { Link, Navigate } from 'react-router-dom'
import Icon from '../../../shared/ui/Icons.jsx'
import { useAuth } from '../../auth/useAuth.js'
import PublicPageLayout from '../components/PublicPageLayout.jsx'
import { explorePathForSession } from '../publicNavigation.js'

const accountTypes = [
  {
    icon: 'search',
    title: 'Find a Home',
    role: 'Tenant',
    description: 'Search properties, get smarter matches, manage viewings and rental applications.',
    cta: 'Continue as Tenant',
    path: '/register?role=tenant',
  },
  {
    icon: 'building',
    title: 'List a Property',
    role: 'Landlord',
    description: 'Publish and manage properties, review viewing requests and rental applications.',
    cta: 'Continue as Landlord',
    path: '/register?role=landlord',
  },
]

export default function GetStartedPage() {
  const { isAuthenticated, isLoading, user } = useAuth()

  if (isLoading) return <div className="auth-restoring" role="status"><span className="shared-spinner" aria-hidden="true" />Restoring your session&hellip;</div>
  if (isAuthenticated) return <Navigate to={explorePathForSession(true, user?.role)} replace />

  return <PublicPageLayout>
    <main className="public-page__main">
      <section className="public-page__hero public-page__hero--center" aria-labelledby="get-started-title">
        <div className="landing-container public-page__hero-inner">
          <p className="landing-eyebrow">Choose your path</p>
          <h1 id="get-started-title">How would you like to use RentFlow?</h1>
          <p>Select the account type that fits your rental journey. You can sign up publicly as a Tenant or Landlord.</p>
        </div>
      </section>
      <section className="public-page__section" aria-label="Account types">
        <div className="landing-container role-choice-grid">
          {accountTypes.map((account) => <article className="public-info-card role-choice-card" key={account.role}>
            <span className="public-info-card__icon"><Icon name={account.icon} size={25} /></span>
            <p className="role-choice-card__role">{account.role}</p>
            <h2>{account.title}</h2>
            <p>{account.description}</p>
            <Link className="landing-button public-page__button" to={account.path}>{account.cta}<Icon name="arrow" size={18} /></Link>
          </article>)}
        </div>
        <p className="public-page__signin">Already have an account? <Link to="/login">Sign In</Link></p>
      </section>
    </main>
  </PublicPageLayout>
}

