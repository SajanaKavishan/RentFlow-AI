import { useLayoutEffect, useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { ApiError } from '../../core/api/apiClient.js'
import Icon from '../../shared/ui/Icons.jsx'
import AuthVisual from '../auth/pages/AuthVisual.jsx'
import { activateMaintenanceTechnician } from './staffProvisioningApi.js'
import '../auth/pages/auth.css'

function consumeSetupToken(location) {
  const params = new URLSearchParams(location.hash.replace(/^#/, ''))
  const token = params.get('token')?.trim() ?? ''
  if (typeof window !== 'undefined' && window.location.hash) {
    window.history.replaceState(
      window.history.state,
      '',
      `${window.location.pathname}${window.location.search}`,
    )
  }
  return token
}

function validatePassword(password, confirmation) {
  if (password.length < 8) return 'Password must be at least 8 characters.'
  if (!/[A-Z]/.test(password)) return 'Password must contain an uppercase letter.'
  if (!/[a-z]/.test(password)) return 'Password must contain a lowercase letter.'
  if (!/\d/.test(password)) return 'Password must contain a number.'
  if (!/[^A-Za-z0-9]/.test(password)) return 'Password must contain a non-alphanumeric character.'
  if (password !== confirmation) return 'Passwords do not match.'
  return ''
}

export default function PasswordSetupPage() {
  const location = useLocation()
  const navigate = useNavigate()
  const [setupToken, setSetupToken] = useState(() => consumeSetupToken(location))
  const [form, setForm] = useState({ password: '', passwordConfirmation: '' })
  const [error, setError] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [passwordVisible, setPasswordVisible] = useState(false)

  useLayoutEffect(() => {
    if (location.hash) {
      navigate(
        { pathname: location.pathname, search: location.search, hash: '' },
        { replace: true },
      )
    }
  }, [location.hash, location.pathname, location.search, navigate])

  async function handleSubmit(event) {
    event.preventDefault()
    setError('')
    const validationError = validatePassword(
      form.password,
      form.passwordConfirmation,
    )
    if (validationError) {
      setError(validationError)
      return
    }

    setIsSubmitting(true)
    try {
      await activateMaintenanceTechnician({
        setupToken,
        password: form.password,
        passwordConfirmation: form.passwordConfirmation,
      })
      setSetupToken('')
      setForm({ password: '', passwordConfirmation: '' })
      navigate('/login', {
        replace: true,
        state: { passwordSetupComplete: true },
      })
    } catch (caught) {
      if (caught instanceof ApiError && caught.statusCode === 429) {
        setError('Too many password setup attempts. Wait a minute and try again.')
      } else {
        setError(caught instanceof ApiError
          ? caught.message
          : 'Password setup could not be completed.')
      }
    } finally {
      setIsSubmitting(false)
    }
  }

  return <main className="auth-page"><AuthVisual
    kicker="Secure staff access"
    title="Finish setting up your Technician account."
    description="Choose a strong password, then sign in through the normal RentFlow login."
    trustItems={['Single-use setup link', 'No automatic sign-in']}
  /><section className="auth-content"><div className="auth-card" aria-labelledby="password-setup-title">
    <p className="auth-eyebrow">Maintenance Technician</p>
    <h1 id="password-setup-title">Set your password</h1>
    <p className="auth-intro">Your password needs an uppercase letter, lowercase letter, number and symbol.</p>
    {!setupToken ? <div className="auth-setup-missing" role="alert">
      <h2>Setup link unavailable</h2>
      <p>This password-setup link is missing or has already been removed from this browser. Request a new secure link from an Administrator if needed.</p>
      <Link className="shared-button" to="/login">Return to sign in</Link>
    </div> : <form onSubmit={handleSubmit} noValidate>
      <label htmlFor="setupPassword">Password</label>
      <div className="auth-password"><input id="setupPassword" type={passwordVisible ? 'text' : 'password'} autoComplete="new-password" value={form.password} onChange={(event) => setForm((current) => ({ ...current, password: event.target.value }))} disabled={isSubmitting} /><button type="button" aria-label={passwordVisible ? 'Hide passwords' : 'Show passwords'} aria-pressed={passwordVisible} onClick={() => setPasswordVisible((visible) => !visible)}><Icon name={passwordVisible ? 'eyeOff' : 'eye'} /></button></div>
      <label htmlFor="setupPasswordConfirmation">Confirm password</label>
      <input id="setupPasswordConfirmation" type={passwordVisible ? 'text' : 'password'} autoComplete="new-password" value={form.passwordConfirmation} onChange={(event) => setForm((current) => ({ ...current, passwordConfirmation: event.target.value }))} disabled={isSubmitting} />
      {error && <div className="auth-error" role="alert">{error}</div>}
      <button className="auth-submit" type="submit" disabled={isSubmitting}>{isSubmitting ? 'Activating account…' : 'Activate account'}</button>
    </form>}
    {setupToken && <p className="auth-switch">Already activated? <Link to="/login">Sign in</Link></p>}
  </div></section></main>
}
