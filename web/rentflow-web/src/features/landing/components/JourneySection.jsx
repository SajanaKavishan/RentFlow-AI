const steps = [
  { title: 'Discover', copy: "Find places that fit what you're looking for." },
  { title: 'View', copy: 'Request and manage property viewings.' },
  { title: 'Apply', copy: 'Submit your rental application and documents.' },
  { title: 'Rent', copy: 'Move into the lease and payment journey.' },
  { title: 'Get Support', copy: 'Handle maintenance and ongoing rental needs.' },
]

export default function JourneySection() {
  return <section id="how-it-works" className="landing-section landing-journey" aria-labelledby="journey-title">
    <div className="landing-container">
      <div className="landing-section__heading landing-section__heading--center">
        <p className="landing-eyebrow">How it works</p>
        <h2 id="journey-title">One connected rental journey.</h2>
        <p>From the first search to ongoing support, each step stays clear and manageable.</p>
      </div>
      <ol className="landing-journey__steps">
        {steps.map((step, index) => <li key={step.title}>
          <span className="landing-journey__number">{String(index + 1).padStart(2, '0')}</span>
          <span className="landing-journey__content"><strong className="landing-journey__label">{step.title}</strong><span className="landing-journey__description">{step.copy}</span></span>
        </li>)}
      </ol>
    </div>
  </section>
}
