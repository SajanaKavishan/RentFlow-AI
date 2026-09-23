import { useEffect, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { ApiError } from '../../core/api/apiClient.js'
import { createMaintenanceTechnician } from '../../features/staffProvisioning/staffProvisioningApi.js'
import { StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import './admin-users.css'

const initialForm = { fullName: '', email: '', phoneNumber: '' }

function validate(form) {
  if (form.fullName.trim().length < 2) return "Enter the Technician's full name."
  if (!/^\S+@\S+\.\S+$/.test(form.email.trim())) return 'Enter a valid email address.'
  if (!/^[+\d][\d\s().-]{6,31}$/.test(form.phoneNumber.trim())) return 'Enter a valid phone number.'
  return ''
}

function setupLinkFor(token) {
  const url = new URL('/setup-password', window.location.origin)
  url.hash = new URLSearchParams({ token }).toString()
  return url.toString()
}

function errorMessageFor(error) {
  if (!(error instanceof ApiError)) return 'The pending Technician account could not be created.'
  if (error.statusCode === 401) return 'Your Admin session is no longer valid. Sign in again.'
  if (error.statusCode === 403) return 'Your account is not authorized to add Technicians.'
  if (error.statusCode === 409) return 'An account with this email already exists.'
  return error.message
}

export default function AdminUsersPage() {
  const [searchParams] = useSearchParams()
  const [isPanelOpen, setIsPanelOpen] = useState(() => searchParams.get('action') === 'add-technician')
  const [form, setForm] = useState(initialForm)
  const [error, setError] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [provisioned, setProvisioned] = useState(null)
  const [copyStatus, setCopyStatus] = useState('')
  const addButtonRef = useRef(null)
  const dialogRef = useRef(null)
  const fullNameRef = useRef(null)
  const successHeadingRef = useRef(null)

  const hasDraft = Object.values(form).some((value) => value.trim())

  useEffect(() => {
    if (isPanelOpen) (provisioned ? successHeadingRef : fullNameRef).current?.focus()
  }, [isPanelOpen, provisioned])

  useEffect(() => {
    if (!isPanelOpen) return undefined
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => { document.body.style.overflow = previousOverflow }
  }, [isPanelOpen])

  const update = (field) => (event) => {
    setForm((current) => ({ ...current, [field]: event.target.value }))
    if (error) setError('')
  }

  function openPanel() {
    setIsPanelOpen(true)
    if (isPanelOpen) (provisioned ? successHeadingRef : fullNameRef).current?.focus()
  }

  function closePanel() {
    if (isSubmitting) return
    if (provisioned && !window.confirm('Close this panel and clear the one-time setup link? Make sure it has been delivered securely first.')) return
    if (!provisioned && hasDraft && !window.confirm('Discard the unsent Technician details?')) return
    setIsPanelOpen(false)
    setForm(initialForm)
    setError('')
    setProvisioned(null)
    setCopyStatus('')
    addButtonRef.current?.focus()
  }

  function handlePanelKeyDown(event) {
    if (event.key === 'Escape') {
      event.preventDefault()
      closePanel()
      return
    }
    if (event.key !== 'Tab') return
    const focusable = Array.from(dialogRef.current?.querySelectorAll(
      'button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [href], [tabindex]:not([tabindex="-1"])',
    ) || [])
    if (!focusable.length) return
    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    const activeIndex = focusable.indexOf(document.activeElement)
    if (activeIndex === -1) {
      event.preventDefault()
      const focusTarget = event.shiftKey ? last : first
      focusTarget.focus()
    } else if (event.shiftKey && activeIndex === 0) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && activeIndex === focusable.length - 1) {
      event.preventDefault()
      first.focus()
    }
  }

  async function handleSubmit(event) {
    event.preventDefault()
    const validationError = validate(form)
    setError(validationError)
    if (validationError) return

    setIsSubmitting(true)
    setProvisioned(null)
    setCopyStatus('')
    try {
      const response = await createMaintenanceTechnician({
        fullName: form.fullName.trim(),
        email: form.email.trim(),
        phoneNumber: form.phoneNumber.trim(),
      })
      const setupLink = setupLinkFor(response.passwordSetupToken)
      setProvisioned({
        fullName: response.fullName,
        email: response.email,
        passwordSetupExpiresAt: response.passwordSetupExpiresAt,
        setupLink,
      })
      setForm(initialForm)
    } catch (caught) {
      setError(errorMessageFor(caught))
    } finally {
      setIsSubmitting(false)
    }
  }

  async function copySetupLink() {
    try {
      await navigator.clipboard.writeText(provisioned.setupLink)
      setCopyStatus('Setup link copied. Deliver it through an approved secure channel.')
    } catch {
      setCopyStatus('Copy failed. Select and copy the setup link manually.')
    }
  }

  function clearSetupLink() {
    fullNameRef.current?.focus()
    setProvisioned(null)
    setCopyStatus('')
  }

  return <main className="shared-page admin-users-page">
    <header className="admin-users-page__header">
      <div>
        <h1>Users</h1>
        <p>Manage Technician access and review user-directory availability.</p>
      </div>
      <button
        ref={addButtonRef}
        className="shared-button admin-users-page__add"
        type="button"
        aria-expanded={isPanelOpen}
        aria-controls="add-technician-panel"
        onClick={openPanel}
      ><span aria-hidden="true">+</span>Add Technician</button>
    </header>

    {isPanelOpen && <div className="admin-users-modal" onMouseDown={(event) => { if (event.target === event.currentTarget) closePanel() }}>
      <section
        ref={dialogRef}
        id="add-technician-panel"
        className="shared-card admin-users-provisioning"
        role="dialog"
        aria-modal="true"
        aria-labelledby="add-technician-title"
        aria-describedby="add-technician-description"
        onKeyDown={handlePanelKeyDown}
      >
      <div className="admin-users-provisioning__heading">
        <div>
          <p className="admin-users-page__eyebrow">Staff provisioning</p>
          <h2 id="add-technician-title">Add Technician</h2>
          <p id="add-technician-description">Create an inactive Maintenance Technician account and securely share its one-time password-setup link.</p>
        </div>
        <button className="admin-users-provisioning__close" type="button" onClick={closePanel} disabled={isSubmitting} aria-label="Close Add Technician panel"><Icon name="close" size={19} /></button>
      </div>

      {provisioned ? <section className="admin-users-success" aria-labelledby="technician-created-title">
        <div className="admin-users-success__heading">
          <div><StatusBadge tone="success">Pending account created</StatusBadge><h3 ref={successHeadingRef} tabIndex="-1" id="technician-created-title">Securely deliver the setup link</h3></div>
          <button className="shared-button shared-button--quiet" type="button" onClick={clearSetupLink}>Clear setup link</button>
        </div>
        <p>The account is inactive until the Technician opens this link and successfully sets a password. No email has been sent.</p>
        <dl>
          <div><dt>Name</dt><dd>{provisioned.fullName}</dd></div>
          <div><dt>Email</dt><dd>{provisioned.email}</dd></div>
          <div><dt>Role</dt><dd>Maintenance Technician</dd></div>
          <div><dt>Status</dt><dd>Pending password setup</dd></div>
        </dl>
        <label htmlFor="technicianSetupLink">One-time password-setup link</label>
        <div className="admin-users-success__link"><input id="technicianSetupLink" readOnly value={provisioned.setupLink} onFocus={(event) => event.target.select()} /><button className="shared-button" type="button" onClick={copySetupLink}>Copy link</button></div>
        <small>Expires {new Date(provisioned.passwordSetupExpiresAt).toLocaleString()}. Treat this link as a password.</small>
        {copyStatus && <p className="admin-users-success__copy-status" role="status">{copyStatus}</p>}
      </section> : <form className="admin-users-form" onSubmit={handleSubmit} noValidate>
        <div className="admin-users-form__fields">
          <div className="admin-users-form__field admin-users-form__field--wide"><label htmlFor="technicianFullName">Full name</label><input ref={fullNameRef} id="technicianFullName" autoComplete="name" value={form.fullName} onChange={update('fullName')} disabled={isSubmitting} /></div>
          <div className="admin-users-form__field"><label htmlFor="technicianEmail">Email</label><input id="technicianEmail" type="email" autoComplete="email" value={form.email} onChange={update('email')} disabled={isSubmitting} /></div>
          <div className="admin-users-form__field"><label htmlFor="technicianPhoneNumber">Phone number</label><input id="technicianPhoneNumber" type="tel" autoComplete="tel" value={form.phoneNumber} onChange={update('phoneNumber')} disabled={isSubmitting} /></div>
        </div>
        {error && <div className="shared-notice shared-notice--error" role="alert">{error}</div>}
        <div className="admin-users-form__actions">
          <button className="shared-button shared-button--quiet" type="button" onClick={closePanel} disabled={isSubmitting}>Cancel</button>
          <button className="shared-button" type="submit" disabled={isSubmitting}>{isSubmitting ? 'Creating pending account...' : 'Create pending Technician'}</button>
        </div>
      </form>}
      </section>
    </div>}

    <section className="shared-card admin-users-directory" aria-labelledby="admin-user-directory-title">
      <div className="admin-users-directory__heading">
        <div>
          <p className="admin-users-page__eyebrow">User management</p>
          <h2 id="admin-user-directory-title">User directory</h2>
        </div>
        <span className="admin-users-directory__scope"><Icon name="user" size={17} />Admin-only workspace</span>
      </div>
      <div className="admin-users-directory__pending" role="status">
        <span className="admin-users-page__icon"><Icon name="user" size={30} /></span>
        <StatusBadge tone="warning">Integration pending</StatusBadge>
        <h3>User directory awaiting secure integration</h3>
        <p>The backend does not currently expose an Admin-authorized endpoint for listing RentFlow users.</p>
        <p>No user records, totals, roles, joined dates, account statuses, search controls, or account-changing actions are shown without that contract.</p>
        <div className="admin-users-directory__note"><Icon name="info" size={18} /><span>The existing <code>/api/auth/me</code> endpoint identifies only the signed-in account and cannot supply a user directory.</span></div>
      </div>
    </section>
  </main>
}
