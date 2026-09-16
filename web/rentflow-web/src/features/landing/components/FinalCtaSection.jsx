import { Link } from 'react-router-dom'

export default function FinalCtaSection({ onSignIn, isSignInPending }) {
  return <section className="landing-section landing-final" aria-labelledby="final-cta-title">
    <div className="landing-container">
      <div className="landing-final__panel">
        <div><p className="landing-eyebrow landing-eyebrow--sage">Your next chapter</p><h2 id="final-cta-title">Ready to start your rental journey?</h2><p>Create your RentFlow account or sign in to continue.</p></div>
        <div className="landing-final__actions">
          <Link className="landing-button landing-button--sage" to="/register">Create Account</Link>
          <button className="landing-button landing-button--outline-light" type="button" onClick={onSignIn} disabled={isSignInPending}>{isSignInPending ? 'Restoring…' : 'Sign In'}</button>
        </div>
      </div>
    </div>
  </section>
}
