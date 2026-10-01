import { Link } from 'react-router-dom'
import Icon from '../../../shared/ui/Icons.jsx'
import PublicPageLayout from '../components/PublicPageLayout.jsx'

const journeys = [
  {
    role: 'Tenant journey',
    title: 'From preferences to a rental',
    steps: ['Create a Tenant account', 'Set the property preferences that matter to you', 'Discover available properties and review match information', 'Open property details and request a viewing', 'Manage viewing progress through the supported workflow', 'Apply for a rental and provide required documents', 'Continue through offers, lease and payment visibility'],
    cta: 'Start as a Tenant',
    path: '/register?role=tenant',
  },
  {
    role: 'Landlord journey',
    title: 'From listing to an approved tenant',
    steps: ['Create a Landlord account', 'Add a property with listing details, images and location', 'Publish and manage the listing', 'Review and manage viewing requests', 'Review rental applications and validation advice', 'Progress an approved applicant through offers, lease and payment workflows'],
    cta: 'Start as a Landlord',
    path: '/register?role=landlord',
  },
]

export default function HowItWorksPage() {
  return <PublicPageLayout>
    <main className="public-page__main">
      <section className="public-page__hero public-page__hero--center" aria-labelledby="how-it-works-title">
        <div className="landing-container public-page__hero-inner">
          <p className="landing-eyebrow">How it works</p>
          <h1 id="how-it-works-title">A clear path through the rental journey.</h1>
          <p>RentFlow connects the supported steps without blurring who can access or act on each workspace.</p>
        </div>
      </section>
      <section className="public-page__section" aria-label="Rental journeys">
        <div className="landing-container journey-grid">
          {journeys.map((journey) => <article className="public-info-card journey-card" key={journey.role}>
            <p className="role-choice-card__role">{journey.role}</p>
            <h2>{journey.title}</h2>
            <ol>{journey.steps.map((step, index) => <li key={step}><span>{index + 1}</span><p>{step}</p></li>)}</ol>
            <Link className="landing-button public-page__button" to={journey.path}>{journey.cta}<Icon name="arrow" size={17} /></Link>
          </article>)}
        </div>
      </section>
    </main>
  </PublicPageLayout>
}

