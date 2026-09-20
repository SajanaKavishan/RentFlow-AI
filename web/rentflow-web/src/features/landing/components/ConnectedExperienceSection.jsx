import Icon from '../../../shared/ui/Icons.jsx'

const experiences = [
  { icon: 'home', title: 'Everything in one place', copy: 'Viewings, applications, documents, leases, payments and support stay connected.' },
  { icon: 'devices', title: 'Web and mobile', copy: "Continue your rental tasks across RentFlow's web and mobile experiences." },
  { icon: 'trend', title: 'Clear progress', copy: 'Statuses and workflow steps help you understand where things stand and what happens next.' },
]

export default function ConnectedExperienceSection() {
  return <section id="connected-experience" className="landing-section landing-connected" aria-labelledby="connected-title">
    <div className="landing-container landing-connected__layout">
      <div className="landing-section__heading" data-reveal="left">
        <p className="landing-eyebrow">One connected experience</p>
        <h2 id="connected-title">Your rental journey, kept together.</h2>
      </div>
      <div className="landing-connected__cards">
        {experiences.map((experience, index) => <article className={`landing-connected-card landing-connected-card--${index + 1}`} data-reveal="right" key={experience.title}>
          <span className="landing-connected-card__icon"><Icon name={experience.icon} size={22} /></span>
          <h3>{experience.title}</h3>
          <p>{experience.copy}</p>
        </article>)}
      </div>
    </div>
  </section>
}
