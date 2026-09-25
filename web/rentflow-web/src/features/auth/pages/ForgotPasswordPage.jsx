import { useState } from 'react'
import { Link } from 'react-router-dom'
import { ApiError } from '../../../core/api/apiClient.js'
import { requestPasswordReset } from '../authApi.js'
import AuthVisual from './AuthVisual.jsx'
import './auth.css'

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState('')
  const [state, setState] = useState({ status: 'editing', message: '', developmentResetLink: '' })

  async function handleSubmit(event) {
    event.preventDefault()
    const normalizedEmail = email.trim()
    if (!/^\S+@\S+\.\S+$/.test(normalizedEmail)) {
      setState({ status: 'error', message: 'Enter a valid email address.', developmentResetLink: '' })
      return
    }

    setState({ status: 'submitting', message: '', developmentResetLink: '' })
    try {
      const response = await requestPasswordReset({ email: normalizedEmail })
      setState({
        status: 'confirmed',
        message: response.message,
        developmentResetLink: response.developmentResetLink || '',
      })
    } catch (caught) {
      const message = caught instanceof ApiError && caught.statusCode === 429
        ? 'Too many password reset requests. Wait a minute and try again.'
        : caught instanceof ApiError
          ? caught.message
          : 'Password reset instructions could not be created.'
      setState({ status: 'error', message, developmentResetLink: '' })
    }
  }

  return <main className="auth-page"><AuthVisual
    kicker="Account recovery"
    title="Recover access without exposing your account."
    description="Request a short-lived, single-use password reset link, then return to the normal sign-in flow."
    trustItems={['Generic account-safe response', 'Single-use recovery link']}
  /><section className="auth-content"><div className="auth-card" aria-labelledby="forgot-password-title">
    <p className="auth-eyebrow">Account recovery</p>
    <h1 id="forgot-password-title">Forgot password</h1>
    <p className="auth-intro">Enter the email address associated with your RentFlow account.</p>
    {state.status === 'confirmed' ? <div className="auth-recovery-confirmed" role="status">
      <h2>Request confirmed</h2>
      <p>{state.message}</p>
      {state.developmentResetLink && <p className="auth-development-link"><strong>Development only:</strong> <a href={state.developmentResetLink}>Open the local reset page</a></p>}
      <Link className="shared-button" to="/login">Return to sign in</Link>
    </div> : <form onSubmit={handleSubmit} noValidate>
      <label htmlFor="recoveryEmail">Email</label>
      <input id="recoveryEmail" type="email" autoComplete="email" placeholder="you@example.com" value={email} onChange={(event) => setEmail(event.target.value)} disabled={state.status === 'submitting'} />
      {state.status === 'error' && <div className="auth-error" role="alert">{state.message}</div>}
      <button className="auth-submit" type="submit" disabled={state.status === 'submitting'}>{state.status === 'submitting' ? 'Creating instructions…' : 'Continue'}</button>
    </form>}
    {state.status !== 'confirmed' && <p className="auth-switch"><Link to="/login">Return to sign in</Link></p>}
  </div></section></main>
}
