import Icon from '../../../shared/ui/Icons.jsx'

const benefits = [
  { icon: 'search', title: 'Find better matches', copy: 'Surface properties that better fit what renters are looking for.' },
  { icon: 'document', title: 'Apply with fewer surprises', copy: 'Help identify missing information and inconsistencies before applications are reviewed.' },
  { icon: 'building', title: 'Make informed rental decisions', copy: 'Use pricing insights to support clearer rental and lease decisions.' },
  { icon: 'tools', title: 'Resolve maintenance faster', copy: 'Help understand, prioritize and coordinate maintenance requests more efficiently.' },
]

export default function SmartAssistanceSection() {
  return <section id="smart-assistance" className="landing-section landing-smart" aria-labelledby="smart-assistance-title">
    <div className="landing-container">
      <div className="landing-smart__intro">
        <div className="landing-section__heading" data-reveal="left">
          <p className="landing-eyebrow landing-eyebrow--sage">Smart assistance</p>
          <h2 id="smart-assistance-title">Smarter help throughout your rental journey.</h2>
        </div>
        <p className="landing-smart__lead" data-reveal="right">RentFlow uses AI-assisted features to help make searching, applying, pricing and maintenance easier to manage.</p>
      </div>
      <div className="landing-assistance-grid">
        {benefits.map((benefit) => <article className="landing-assistance-card" data-reveal="up" key={benefit.title}>
          <span className="landing-assistance-card__icon"><Icon name={benefit.icon} size={23} /></span>
          <div><h3>{benefit.title}</h3><p>{benefit.copy}</p></div>
        </article>)}
      </div>
      <aside className="landing-smart__trust" aria-label="Human control" data-reveal="up">
        <span className="landing-smart__trust-mark" aria-hidden="true">✓</span>
        <div><h3>AI helps with the work. People stay in control.</h3><p>Important rental decisions and approvals remain human-controlled.</p></div>
      </aside>
    </div>
  </section>
}
