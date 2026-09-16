const values = [
  'Easy property discovery',
  'Clear viewing requests',
  'Simple rental applications',
  'Secure document handling',
  'Smarter property matching',
  'Clear application progress',
  'Helpful pricing insights',
  'Human-controlled decisions',
  'Connected web and mobile experience',
  'Organized lease and payment workflows',
  'Faster maintenance coordination',
  'Clear status updates',
]

function ValueList({ duplicate = false }) {
  return <ul className="experience-rail__list" aria-hidden={duplicate ? 'true' : undefined}>
    {values.map((value) => <li className="experience-rail__card" key={value}><span aria-hidden="true">✓</span>{value}</li>)}
  </ul>
}

export default function ExperienceRailSection() {
  return <section id="experience" className="landing-section landing-experience" aria-labelledby="experience-title">
    <div className="landing-container">
      <div className="landing-section__heading landing-section__heading--center">
        <p className="landing-eyebrow">Renting, simplified</p>
        <h2 id="experience-title">Built around a simpler rental experience.</h2>
        <p>Clearer steps, connected tools and smarter assistance throughout the rental journey.</p>
      </div>
    </div>
    <div className="experience-rail" tabIndex="0" aria-label="Product experience highlights">
      <div className="experience-rail__track"><ValueList /><ValueList duplicate /></div>
    </div>
  </section>
}
