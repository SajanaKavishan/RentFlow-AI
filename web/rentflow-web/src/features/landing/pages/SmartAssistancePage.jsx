import { Link } from 'react-router-dom'
import Icon from '../../../shared/ui/Icons.jsx'
import PublicPageLayout from '../components/PublicPageLayout.jsx'

const assistance = [
  {
    icon: 'search',
    label: 'Tenant matching',
    title: 'Preference-based property ranking',
    copy: 'RentFlow calculates match scores from saved Tenant preferences using deterministic rules. When available, AI adds plain-language context without changing those scores.',
    note: 'Deterministic score · optional AI explanation',
  },
  {
    icon: 'document',
    label: 'Application review',
    title: 'Structured validation support',
    copy: 'Required fields, document metadata and consistency checks produce authoritative findings. AI can organize advisory context for the Landlord review, while decisions remain human-controlled.',
    note: 'Deterministic findings · advisory AI review',
  },
  {
    icon: 'trend',
    label: 'Landlord pricing',
    title: 'Evidence-led pricing analysis',
    copy: 'The Landlord pricing workspace combines property facts and available rental evidence with an advisory analysis. Evidence sufficiency and human judgment remain visible parts of the workflow.',
    note: 'Evidence assessment · advisory analysis',
  },
]

export default function SmartAssistancePage() {
  return <PublicPageLayout>
    <main className="public-page__main">
      <section className="public-page__hero public-page__hero--dark" aria-labelledby="smart-page-title">
        <div className="landing-container public-page__hero-inner">
          <p className="landing-eyebrow landing-eyebrow--sage">Smart assistance</p>
          <h1 id="smart-page-title">Useful intelligence, with clear boundaries.</h1>
          <p>RentFlow combines rule-based checks with optional AI advice. Automated explanations support the work; they do not replace access controls or human decisions.</p>
        </div>
      </section>
      <section className="public-page__section" aria-label="Smart assistance features">
        <div className="landing-container assistance-page-grid">
          {assistance.map((item) => <article className="public-info-card assistance-page-card" key={item.title}>
            <span className="public-info-card__icon"><Icon name={item.icon} size={24} /></span>
            <p className="role-choice-card__role">{item.label}</p>
            <h2>{item.title}</h2>
            <p>{item.copy}</p>
            <small>{item.note}</small>
          </article>)}
        </div>
        <div className="landing-container public-page__callout">
          <Icon name="shield" size={24} />
          <div><h2>People stay in control.</h2><p>Important rental decisions, approvals and account permissions remain with authorized people.</p></div>
          <Link className="landing-button public-page__button" to="/get-started">Choose your account type</Link>
        </div>
      </section>
    </main>
  </PublicPageLayout>
}
