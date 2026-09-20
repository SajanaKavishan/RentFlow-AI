import Icon from '../../../shared/ui/Icons.jsx'

const features = [
  { icon: 'search', title: 'Property Discovery', copy: "Explore available rentals and find places that fit what you're looking for." },
  { icon: 'calendar', title: 'Viewings & Applications', copy: 'Request viewings, submit rental applications and manage supporting documents.' },
  { icon: 'document', title: 'Lease & Payments', copy: 'Keep rental agreements, schedules and payment activity organized.' },
  { icon: 'tools', title: 'Maintenance & Support', copy: 'Handle maintenance requests and ongoing rental support in one place.' },
]

export default function PlatformSection() {
  return <section id="platform" className="landing-section landing-platform" aria-labelledby="platform-title">
    <div className="landing-container">
      <div className="landing-section__heading" data-reveal="up">
        <p className="landing-eyebrow">The platform</p>
        <h2 id="platform-title">Everything you need for the rental journey.</h2>
      </div>
      <div className="landing-card-grid landing-card-grid--features">
        {features.map((feature) => <article className="landing-card landing-feature-card" data-reveal="up" key={feature.title}>
          <span className="landing-card__icon"><Icon name={feature.icon} size={24} /></span>
          <h3>{feature.title}</h3>
          <p>{feature.copy}</p>
        </article>)}
      </div>
    </div>
  </section>
}
