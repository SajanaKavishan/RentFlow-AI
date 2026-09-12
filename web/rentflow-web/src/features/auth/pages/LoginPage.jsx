import { useState } from 'react'
import { Link, Navigate, useLocation, useNavigate } from 'react-router-dom'
import { ApiError } from '../../../core/api/apiClient.js'
import { useAuth } from '../useAuth.js'
import './auth.css'

export default function LoginPage() {
  const { isAuthenticated, login } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const [form, setForm] = useState({ email: '', password: '' })
  const [error, setError] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  if (isAuthenticated) return <Navigate to="/" replace />

  async function handleSubmit(event) {
    event.preventDefault(); setError('')
    if (!form.email.trim() || !/^\S+@\S+\.\S+$/.test(form.email)) { setError('Enter a valid email address.'); return }
    if (!form.password) { setError('Enter your password.'); return }
    setIsSubmitting(true)
    try {
      await login({ email: form.email.trim(), password: form.password })
      const target = location.state?.from?.pathname
      navigate(target && target !== '/login' ? target : '/', { replace: true })
    } catch (caught) {
      setError(caught instanceof ApiError ? caught.message : 'Sign in could not be completed.')
    } finally { setIsSubmitting(false) }
  }

  return <main className="auth-page"><section className="auth-card" aria-labelledby="login-title">
    <p className="auth-eyebrow">Welcome back</p><h1 id="login-title">Sign in to RentFlow</h1>
    <p className="auth-intro">Manage your rental journey in one place.</p>
    <form onSubmit={handleSubmit} noValidate>
      <label htmlFor="email">Email</label><input id="email" type="email" autoComplete="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} disabled={isSubmitting} />
      <label htmlFor="password">Password</label><input id="password" type="password" autoComplete="current-password" value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} disabled={isSubmitting} />
      {error && <div className="auth-error" role="alert">{error}</div>}
      <button className="auth-submit" type="submit" disabled={isSubmitting}>{isSubmitting ? 'Signing in…' : 'Sign in'}</button>
    </form><p className="auth-switch">New to RentFlow? <Link to="/register">Create an account</Link></p>
  </section></main>
}
