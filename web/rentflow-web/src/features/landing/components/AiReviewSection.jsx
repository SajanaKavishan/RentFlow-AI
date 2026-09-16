const checks = [
  { label: 'Application completeness', status: 'Completed', tone: 'complete' },
  { label: 'Document checks', status: 'Needs Review', tone: 'review' },
  { label: 'Consistency checks', status: 'Matched', tone: 'complete' },
]

export default function AiReviewSection() {
  return <section id="ai-review" className="landing-section landing-ai" aria-labelledby="ai-review-title">
    <div className="landing-container landing-ai__layout">
      <div className="landing-ai__copy">
        <p className="landing-eyebrow landing-eyebrow--sage">Smart processing</p>
        <h2 id="ai-review-title">AI assistance.<br />Human decisions.</h2>
        <p>RentFlow AI can support application validation with structured checks, document review, consistency checks and auditable workflow steps.</p>
        <div className="landing-ai__statement"><span aria-hidden="true">✓</span><strong>AI supports the review process. Final rental decisions remain human-controlled.</strong></div>
      </div>
      <div className="landing-review-card" aria-label="Illustrative application review">
        <div className="landing-review-card__top"><div><span>Application review</span><strong>Structured checks</strong></div><span className="landing-review-card__mark" aria-hidden="true">AI</span></div>
        <div className="landing-review-card__checks">
          {checks.map((check) => <div className="landing-review-row" key={check.label}><span>{check.label}</span><strong className={`landing-review-status landing-review-status--${check.tone}`}>{check.status}</strong></div>)}
        </div>
        <div className="landing-review-card__human"><span className="landing-review-card__avatar" aria-hidden="true">HR</span><div><span>Decision step</span><strong>Human Review Required</strong></div></div>
      </div>
    </div>
  </section>
}
