import { useEffect, useRef, useState } from 'react'
import Icon from '../ui/Icons.jsx'

const initialForm = {
  currentPassword: '',
  newPassword: '',
  newPasswordConfirmation: '',
}

const passwordChecks = [
  ['length', 'At least 8 characters', (value) => value.length >= 8],
  ['uppercase', 'One uppercase letter', (value) => /[A-Z]/.test(value)],
  ['lowercase', 'One lowercase letter', (value) => /[a-z]/.test(value)],
  ['number', 'One number', (value) => /\d/.test(value)],
  ['symbol', 'One symbol', (value) => /[^A-Za-z0-9]/.test(value)],
]

function validate(form) {
  if (!form.currentPassword) return 'Enter your current password.'
  const failedCheck = passwordChecks.find(([, , passes]) => !passes(form.newPassword))
  if (failedCheck) return `New password must include: ${failedCheck[1].toLowerCase()}.`
  if (form.newPassword !== form.newPasswordConfirmation) return 'New password and confirmation must match.'
  if (form.newPassword === form.currentPassword) return 'New password must be different from the current password.'
  return ''
}

export default function ChangePasswordDialog({ changePassword, onClose, onSuccess }) {
  const [form, setForm] = useState(initialForm)
  const [passwordsVisible, setPasswordsVisible] = useState(false)
  const [status, setStatus] = useState({ type: 'idle', message: '' })
  const currentPasswordRef = useRef(null)
  const dialogRef = useRef(null)
  const isSubmitting = status.type === 'submitting'

  useEffect(() => {
    currentPasswordRef.current?.focus()
  }, [])

  useEffect(() => {
    const handleKeyDown = (event) => {
      if (event.key === 'Escape' && !isSubmitting) onClose()
      if (event.key !== 'Tab') return
      const focusable = Array.from(dialogRef.current?.querySelectorAll(
        'button:not(:disabled), input:not(:disabled)',
      ) || [])
      if (focusable.length === 0) return
      const first = focusable[0]
      const last = focusable[focusable.length - 1]
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault()
        first.focus()
      }
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [isSubmitting, onClose])

  const update = (field) => (event) => {
    setForm((current) => ({ ...current, [field]: event.target.value }))
    if (status.type === 'error') setStatus({ type: 'idle', message: '' })
  }

  async function submit(event) {
    event.preventDefault()
    const validationError = validate(form)
    if (validationError) {
      setStatus({ type: 'error', message: validationError })
      return
    }

    setStatus({ type: 'submitting', message: '' })
    try {
      const response = await changePassword(form)
      const message = response?.message || 'Your password was changed successfully.'
      setForm(initialForm)
      setStatus({ type: 'success', message })
      onSuccess(message)
    } catch (error) {
      setStatus({ type: 'error', message: error?.message || 'Your password could not be changed.' })
    }
  }

  return <div className="profile-dialog-backdrop" onMouseDown={(event) => {
    if (event.target === event.currentTarget && !isSubmitting) onClose()
  }}>
    <section ref={dialogRef} className="profile-dialog" role="dialog" aria-modal="true" aria-labelledby="change-password-title" aria-describedby="change-password-description">
      <header className="profile-dialog__header">
        <div><p>Account security</p><h2 id="change-password-title">Change password</h2></div>
        <button type="button" className="profile-dialog__close" aria-label="Close change password dialog" disabled={isSubmitting} onClick={onClose}><Icon name="close" /></button>
      </header>
      {status.type === 'success' ? <div className="profile-dialog__success" role="status">
        <span aria-hidden="true">✓</span>
        <h3>Password changed</h3>
        <p>{status.message}</p>
        <p>Your current session remains signed in.</p>
        <button className="shared-button" type="button" onClick={onClose}>Done</button>
      </div> : <form className="change-password-form" onSubmit={submit} noValidate>
        <p id="change-password-description">Enter your current password, then choose a new secure password.</p>
        <label htmlFor="currentPassword">Current password</label>
        <div className="change-password-field">
          <input ref={currentPasswordRef} id="currentPassword" type={passwordsVisible ? 'text' : 'password'} autoComplete="current-password" maxLength="128" value={form.currentPassword} disabled={isSubmitting} onChange={update('currentPassword')} />
          <button type="button" aria-label={passwordsVisible ? 'Hide passwords' : 'Show passwords'} aria-pressed={passwordsVisible} disabled={isSubmitting} onClick={() => setPasswordsVisible((visible) => !visible)}><Icon name={passwordsVisible ? 'eyeOff' : 'eye'} /></button>
        </div>
        <label htmlFor="newPassword">New password</label>
        <div className="change-password-field">
          <input id="newPassword" type={passwordsVisible ? 'text' : 'password'} autoComplete="new-password" maxLength="128" value={form.newPassword} disabled={isSubmitting} onChange={update('newPassword')} />
        </div>
        <ul className="change-password-policy" aria-label="Password requirements" aria-live="polite">
          {passwordChecks.map(([key, label, passes]) => <li key={key} className={passes(form.newPassword) ? 'is-met' : ''}><span aria-hidden="true">{passes(form.newPassword) ? '✓' : '○'}</span>{label}</li>)}
        </ul>
        <label htmlFor="newPasswordConfirmation">Confirm new password</label>
        <div className="change-password-field">
          <input id="newPasswordConfirmation" type={passwordsVisible ? 'text' : 'password'} autoComplete="new-password" maxLength="128" value={form.newPasswordConfirmation} disabled={isSubmitting} onChange={update('newPasswordConfirmation')} />
        </div>
        {status.type === 'error' && <div className="change-password-error" role="alert">{status.message}</div>}
        <div className="profile-dialog__actions">
          <button className="shared-button shared-button--outline" type="button" disabled={isSubmitting} onClick={onClose}>Cancel</button>
          <button className="shared-button" type="submit" disabled={isSubmitting}>{isSubmitting ? 'Changing password…' : 'Change password'}</button>
        </div>
      </form>}
    </section>
  </div>
}
