import { useState } from 'react'
import { Link, Navigate, useNavigate } from 'react-router-dom'
import { ApiError } from '../../../core/api/apiClient.js'
import { useAuth } from '../useAuth.js'
import { PUBLIC_REGISTRATION_ROLES, USER_ROLES } from '../authModel.js'
import './auth.css'

const initialForm = { fullName: '', email: '', phoneNumber: '', password: '', confirmPassword: '', role: USER_ROLES.TENANT }
function validate(form) {
  if (form.fullName.trim().length < 2) return 'Enter your full name.'
  if (!/^\S+@\S+\.\S+$/.test(form.email)) return 'Enter a valid email address.'
  if (!/^[+\d][\d\s().-]{6,31}$/.test(form.phoneNumber.trim())) return 'Enter a valid phone number.'
  if (form.password.length < 8) return 'Password must be at least 8 characters.'
  if (form.password !== form.confirmPassword) return 'Passwords do not match.'
  if (!PUBLIC_REGISTRATION_ROLES.includes(form.role)) return 'Select a supported account type.'
  return ''
}

export default function RegisterPage() {
  const { isAuthenticated, register } = useAuth(); const navigate = useNavigate()
  const [form, setForm] = useState(initialForm); const [error, setError] = useState(''); const [isSubmitting, setIsSubmitting] = useState(false)
  if (isAuthenticated) return <Navigate to="/" replace />
  const update = (field) => (event) => setForm((current) => ({ ...current, [field]: event.target.value }))
  async function handleSubmit(event) {
    event.preventDefault(); const validationError = validate(form); setError(validationError); if (validationError) return
    setIsSubmitting(true)
    try {
      await register({ fullName: form.fullName.trim(), email: form.email.trim(), phoneNumber: form.phoneNumber.trim(), password: form.password, role: form.role })
      navigate('/', { replace: true })
    } catch (caught) { setError(caught instanceof ApiError ? caught.message : 'Registration could not be completed.') }
    finally { setIsSubmitting(false) }
  }
  return <main className="auth-page"><section className="auth-card auth-card--wide" aria-labelledby="register-title">
    <p className="auth-eyebrow">Get started</p><h1 id="register-title">Create your RentFlow account</h1>
    <form onSubmit={handleSubmit} noValidate><div className="auth-grid">
      <div><label htmlFor="fullName">Full name</label><input id="fullName" autoComplete="name" value={form.fullName} onChange={update('fullName')} disabled={isSubmitting} /></div>
      <div><label htmlFor="registerEmail">Email</label><input id="registerEmail" type="email" autoComplete="email" value={form.email} onChange={update('email')} disabled={isSubmitting} /></div>
      <div><label htmlFor="phoneNumber">Phone number</label><input id="phoneNumber" type="tel" autoComplete="tel" value={form.phoneNumber} onChange={update('phoneNumber')} disabled={isSubmitting} /></div>
      <div><label htmlFor="role">Account type</label><select id="role" value={form.role} onChange={update('role')} disabled={isSubmitting}>{PUBLIC_REGISTRATION_ROLES.map((role) => <option key={role} value={role}>{role}</option>)}</select></div>
      <div><label htmlFor="registerPassword">Password</label><input id="registerPassword" type="password" autoComplete="new-password" value={form.password} onChange={update('password')} disabled={isSubmitting} /></div>
      <div><label htmlFor="confirmPassword">Confirm password</label><input id="confirmPassword" type="password" autoComplete="new-password" value={form.confirmPassword} onChange={update('confirmPassword')} disabled={isSubmitting} /></div>
    </div>{error && <div className="auth-error" role="alert">{error}</div>}
    <button className="auth-submit" type="submit" disabled={isSubmitting}>{isSubmitting ? 'Creating account…' : 'Create account'}</button></form>
    <p className="auth-switch">Already registered? <Link to="/login">Sign in</Link></p>
  </section></main>
}
