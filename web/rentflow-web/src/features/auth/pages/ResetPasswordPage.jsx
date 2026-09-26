import { useLayoutEffect, useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { ApiError } from '../../../core/api/apiClient.js'
import Icon from '../../../shared/ui/Icons.jsx'
import { resetPassword } from '../authApi.js'
import { validateNewPassword } from '../passwordPolicy.js'
import AuthVisual from './AuthVisual.jsx'
import './auth.css'

function consumeResetToken(location) {
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

export default function ResetPasswordPage() {
  const location = useLocation()
  const navigate = useNavigate()
  const [resetToken, setResetToken] = useState(() => consumeResetToken(location))
  const [form, setForm] = useState({ newPassword: '', newPasswordConfirmation: '' })
  const [error, setError] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [passwordVisible, setPasswordVisible] = useState(false)
  const [confirmationVisible, setConfirmationVisible] = useState(false)

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
    const validationError = validateNewPassword(
      form.newPassword,
      form.newPasswordConfirmation,
    )
    if (validationError) {
      setError(validationError)
      return
    }

    setIsSubmitting(true)
    try {
      await resetPassword({ token: resetToken, ...form })
      setResetToken('')
      setForm({ newPassword: '', newPasswordConfirmation: '' })
      navigate('/login', { replace: true, state: { passwordResetComplete: true } })
    } catch (caught) {
      if (caught instanceof ApiError && caught.statusCode === 429) {
        setError('Too many password reset attempts. Wait a minute and try again.')
      } else {
        setError(caught instanceof ApiError
          ? caught.message
          : 'Password reset could not be completed.')
      }
    } finally {
      setIsSubmitting(false)
    }
  }

  return <main className="auth-page"><AuthVisual
    kicker="Secure account recovery"
    title="Choose a new password for your account."
    description="Reset links are short-lived and single-use. A successful reset returns you to normal sign-in."
    trustItems={['Single-use reset token', 'Existing sessions invalidated']}
  /><section className="auth-content"><div className="auth-card" aria-labelledby="reset-password-title">
    <p className="auth-eyebrow">Account recovery</p>
    <h1 id="reset-password-title">Reset password</h1>
    <p className="auth-intro">Use at least 8 characters with uppercase, lowercase, number and symbol.</p>
    {!resetToken ? <div className="auth-setup-missing" role="alert">
      <h2>Reset link unavailable</h2>
      <p>This password-reset link is missing or has already been removed from this browser. Request a new secure link if needed.</p>
      <Link className="shared-button" to="/forgot-password">Request another link</Link>
    </div> : <form onSubmit={handleSubmit} noValidate>
      <label htmlFor="resetPassword">New password</label>
      <div className="auth-password"><input id="resetPassword" type={passwordVisible ? 'text' : 'password'} autoComplete="new-password" value={form.newPassword} onChange={(event) => setForm((current) => ({ ...current, newPassword: event.target.value }))} disabled={isSubmitting} /><button type="button" aria-label={passwordVisible ? 'Hide new password' : 'Show new password'} aria-pressed={passwordVisible} onClick={() => setPasswordVisible((visible) => !visible)}><Icon name={passwordVisible ? 'eyeOff' : 'eye'} /></button></div>
      <label htmlFor="resetPasswordConfirmation">Confirm new password</label>
      <div className="auth-password"><input id="resetPasswordConfirmation" type={confirmationVisible ? 'text' : 'password'} autoComplete="new-password" value={form.newPasswordConfirmation} onChange={(event) => setForm((current) => ({ ...current, newPasswordConfirmation: event.target.value }))} disabled={isSubmitting} /><button type="button" aria-label={confirmationVisible ? 'Hide confirm password' : 'Show confirm password'} aria-pressed={confirmationVisible} onClick={() => setConfirmationVisible((visible) => !visible)}><Icon name={confirmationVisible ? 'eyeOff' : 'eye'} /></button></div>
      {error && <div className="auth-error" role="alert">{error}</div>}
      <button className="auth-submit" type="submit" disabled={isSubmitting}>{isSubmitting ? 'Resetting password…' : 'Reset password'}</button>
    </form>}
    {resetToken && <p className="auth-switch"><Link to="/login">Return to sign in</Link></p>}
  </div></section></main>
}
