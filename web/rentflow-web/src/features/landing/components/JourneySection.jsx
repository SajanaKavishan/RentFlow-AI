const steps = ['Discover', 'View', 'Apply', 'Rent', 'Get Support']

export default function JourneySection() {
  return <section id="how-it-works" className="landing-section landing-journey" aria-labelledby="journey-title">
    <div className="landing-container">
      <div className="landing-section__heading landing-section__heading--center">
        <p className="landing-eyebrow">How it works</p>
        <h2 id="journey-title">One connected rental journey.</h2>
        <p>From the first search to ongoing support, each step stays clear and manageable.</p>
      </div>
      <ol className="landing-journey__steps">
        {steps.map((step, index) => <li key={step}>
          <span className="landing-journey__number">{String(index + 1).padStart(2, '0')}</span>
          <span className="landing-journey__label">{step}</span>
        </li>)}
      </ol>
    </div>
  </section>
}
