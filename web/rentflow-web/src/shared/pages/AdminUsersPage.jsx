import { useState } from 'react'
import { Link } from 'react-router-dom'
import { ApiError } from '../../core/api/apiClient.js'
import { createMaintenanceTechnician } from '../../features/staffProvisioning/staffProvisioningApi.js'
import { StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import './admin-users.css'

const initialForm = { fullName: '', email: '', phoneNumber: '' }

function validate(form) {
  if (form.fullName.trim().length < 2) return 'Enter the Technician’s full name.'
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
  const [form, setForm] = useState(initialForm)
  const [error, setError] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [provisioned, setProvisioned] = useState(null)
  const [copyStatus, setCopyStatus] = useState('')

  const update = (field) => (event) => {
    setForm((current) => ({ ...current, [field]: event.target.value }))
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
        id: response.id,
        fullName: response.fullName,
        email: response.email,
        phoneNumber: response.phoneNumber,
        role: response.role,
        isActive: response.isActive,
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

  return <main className="shared-page admin-users-page">
    <header className="admin-users-page__header">
      <div>
        <p className="admin-users-page__eyebrow">Administration workspace</p>
        <h1>Users</h1>
        <p>Create pending Technician access while the complete user directory and account-management APIs remain pending.</p>
      </div>
      <div className="admin-users-page__header-actions" aria-label="Users page navigation">
        <Link className="shared-button shared-button--outline" to="/dashboard"><Icon name="home" size={18} />Back to dashboard</Link>
        <Link className="shared-button" to="/notifications" aria-label="Open notification inbox"><Icon name="bell" size={18} />Notifications</Link>
      </div>
    </header>

    <div className="admin-users-page__layout">
      <section className="shared-card admin-users-workspace" aria-labelledby="add-technician-title">
        <div className="admin-users-workspace__heading">
          <div><p className="admin-users-page__eyebrow">Staff provisioning</p><h2 id="add-technician-title">Add Technician</h2></div>
          <StatusBadge tone="success">Creation available</StatusBadge>
        </div>

        <p className="admin-users-form__intro">Create an inactive Maintenance Technician account and securely share its one-time password-setup link.</p>
        <form className="admin-users-form" onSubmit={handleSubmit} noValidate>
          <label htmlFor="technicianFullName">Full name</label>
          <input id="technicianFullName" autoComplete="name" value={form.fullName} onChange={update('fullName')} disabled={isSubmitting} />
          <label htmlFor="technicianEmail">Email</label>
          <input id="technicianEmail" type="email" autoComplete="email" value={form.email} onChange={update('email')} disabled={isSubmitting} />
          <label htmlFor="technicianPhoneNumber">Phone number</label>
          <input id="technicianPhoneNumber" type="tel" autoComplete="tel" value={form.phoneNumber} onChange={update('phoneNumber')} disabled={isSubmitting} />
          {error && <div className="shared-notice shared-notice--error" role="alert">{error}</div>}
          <button className="shared-button admin-users-form__submit" type="submit" disabled={isSubmitting}>{isSubmitting ? 'Creating pending account…' : 'Create pending Technician'}</button>
        </form>

        {provisioned && <section className="admin-users-success" aria-labelledby="technician-created-title">
          <div className="admin-users-success__heading"><div><StatusBadge tone="success">Pending account created</StatusBadge><h3 id="technician-created-title">Securely deliver the setup link</h3></div><button className="shared-button shared-button--quiet" type="button" onClick={() => { setProvisioned(null); setCopyStatus('') }}>Clear setup link</button></div>
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
        </section>}
      </section>

      <aside className="admin-users-page__side" aria-label="User management integration details">
        <section className="shared-card admin-users-requirements" aria-labelledby="admin-user-directory-title">
          <div className="admin-users-requirements__heading"><span className="admin-users-page__icon admin-users-page__icon--small"><Icon name="info" size={21} /></span><div><p className="admin-users-page__eyebrow">User management</p><h2 id="admin-user-directory-title">User directory</h2></div></div>
          <div className="admin-users-directory-status"><StatusBadge tone="warning">Integration pending</StatusBadge><p>Technician creation is available, but the backend does not expose an Admin-authorized user directory or account-management endpoints.</p><p>No user list, account counts or unsupported account-changing controls are shown.</p></div>
          <p className="admin-users-requirements__note">The existing <code>/api/auth/me</code> endpoint identifies only the signed-in account and cannot supply a user directory.</p>
        </section>

        <section className="shared-card admin-users-tools" aria-labelledby="admin-users-tools-title">
          <div><p className="admin-users-page__eyebrow">Shared tools</p><h2 id="admin-users-tools-title">Account access</h2></div>
          <Link to="/notifications" aria-label="Open notifications from Users"><span className="admin-users-page__icon admin-users-page__icon--small"><Icon name="bell" size={20} /></span><span><strong>Notifications</strong><small>Review updates for your account</small></span><Icon name="arrow" size={17} /></Link>
          <Link to="/profile"><span className="admin-users-page__icon admin-users-page__icon--small"><Icon name="user" size={20} /></span><span><strong>Profile</strong><small>View account details and sign out</small></span><Icon name="arrow" size={17} /></Link>
        </section>
      </aside>
    </div>
  </main>
}
