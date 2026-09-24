import { useEffect, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { ApiError } from '../../core/api/apiClient.js'
import { useAuth } from '../../features/auth/useAuth.js'
import {
  ADMIN_USER_ROLES,
  ADMIN_USERS_PAGE_SIZE,
  getAdminUsers,
} from '../../features/adminUsers/adminUsersApi.js'
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

function directoryErrorFor(error) {
  if (error instanceof ApiError && error.statusCode === 401) {
    return 'Your Admin session is no longer valid. Sign in again to view the user directory.'
  }
  if (error instanceof ApiError && error.statusCode === 403) {
    return 'Your account is no longer authorized to view the user directory.'
  }
  if (error instanceof ApiError) return error.message
  return 'The user directory could not be loaded.'
}

function roleLabel(role) {
  return role === 'MaintenanceTechnician' ? 'Maintenance Technician' : role
}

function joinedDate(createdAt) {
  return new Intl.DateTimeFormat('en-US', {
    year: 'numeric', month: 'short', day: 'numeric',
  }).format(new Date(createdAt))
}

export default function AdminUsersPage() {
  const { user } = useAuth()
  const [searchParams] = useSearchParams()
  const [isPanelOpen, setIsPanelOpen] = useState(() => searchParams.get('action') === 'add-technician')
  const [form, setForm] = useState(initialForm)
  const [error, setError] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [provisioned, setProvisioned] = useState(null)
  const [copyStatus, setCopyStatus] = useState('')
  const [closeConfirmation, setCloseConfirmation] = useState(null)
  const [searchDraft, setSearchDraft] = useState('')
  const [directoryQuery, setDirectoryQuery] = useState({ search: '', role: '', active: '' })
  const [directoryPage, setDirectoryPage] = useState(1)
  const [directoryRefresh, setDirectoryRefresh] = useState(0)
  const [directoryState, setDirectoryState] = useState({ requestKey: '', status: 'loading', data: null, error: null })
  const addButtonRef = useRef(null)
  const dialogRef = useRef(null)
  const fullNameRef = useRef(null)
  const successHeadingRef = useRef(null)
  const closeTriggerRef = useRef(null)
  const confirmationRef = useRef(null)
  const confirmationCancelRef = useRef(null)
  const directoryRequest = useRef(0)

  const hasDraft = Object.values(form).some((value) => value.trim())
  const directoryRequestKey = JSON.stringify([
    user.id,
    directoryPage,
    directoryQuery.search,
    directoryQuery.role,
    directoryQuery.active,
    directoryRefresh,
  ])
  const visibleDirectoryState = directoryState.requestKey === directoryRequestKey
    ? directoryState
    : { status: 'loading', data: null, error: null }

  useEffect(() => {
    if (isPanelOpen) (provisioned ? successHeadingRef : fullNameRef).current?.focus()
  }, [isPanelOpen, provisioned])

  useEffect(() => {
    if (closeConfirmation) confirmationCancelRef.current?.focus()
  }, [closeConfirmation])

  useEffect(() => {
    if (!isPanelOpen) return undefined
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => { document.body.style.overflow = previousOverflow }
  }, [isPanelOpen])

  useEffect(() => {
    const request = ++directoryRequest.current
    const controller = new AbortController()
    getAdminUsers({
      page: directoryPage,
      pageSize: ADMIN_USERS_PAGE_SIZE,
      search: directoryQuery.search,
      role: directoryQuery.role,
      isActive: directoryQuery.active === '' ? undefined : directoryQuery.active === 'true',
      signal: controller.signal,
    }).then((data) => {
      if (request === directoryRequest.current) {
        setDirectoryState({ requestKey: directoryRequestKey, status: 'ready', data, error: null })
      }
    }).catch((caught) => {
      if (request === directoryRequest.current) {
        setDirectoryState({ requestKey: directoryRequestKey, status: 'error', data: null, error: caught })
      }
    })
    return () => {
      controller.abort()
    }
  }, [
    user.id,
    directoryPage,
    directoryQuery.search,
    directoryQuery.role,
    directoryQuery.active,
    directoryRefresh,
    directoryRequestKey,
  ])

  const update = (field) => (event) => {
    setForm((current) => ({ ...current, [field]: event.target.value }))
    if (error) setError('')
  }

  function openPanel() {
    setIsPanelOpen(true)
    if (isPanelOpen) (provisioned ? successHeadingRef : fullNameRef).current?.focus()
  }

  function finishClosingPanel() {
    setCloseConfirmation(null)
    setIsPanelOpen(false)
    setForm(initialForm)
    setError('')
    setProvisioned(null)
    setCopyStatus('')
    addButtonRef.current?.focus()
  }

  function closePanel() {
    if (isSubmitting || closeConfirmation) return
    if (provisioned || (!provisioned && hasDraft)) {
      closeTriggerRef.current = document.activeElement
      setCloseConfirmation(provisioned ? 'setup-link' : 'draft')
      return
    }
    finishClosingPanel()
  }

  function cancelCloseConfirmation() {
    setCloseConfirmation(null)
    closeTriggerRef.current?.focus()
  }

  function handleConfirmationKeyDown(event) {
    event.stopPropagation()
    if (event.key === 'Escape') {
      event.preventDefault()
      cancelCloseConfirmation()
      return
    }
    if (event.key !== 'Tab') return
    const focusable = Array.from(confirmationRef.current?.querySelectorAll('button:not([disabled])') || [])
    if (!focusable.length) return
    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus() }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus() }
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
      setDirectoryRefresh((current) => current + 1)
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

  function submitDirectorySearch(event) {
    event.preventDefault()
    setDirectoryPage(1)
    setDirectoryQuery((current) => ({ ...current, search: searchDraft.trim() }))
  }

  function updateDirectoryFilter(field) {
    return (event) => {
      setDirectoryPage(1)
      setDirectoryQuery((current) => ({ ...current, [field]: event.target.value }))
    }
  }

  function clearDirectoryFilters() {
    setSearchDraft('')
    setDirectoryPage(1)
    setDirectoryQuery({ search: '', role: '', active: '' })
  }

  return <main className="shared-page admin-users-page">
    <header className="admin-users-page__header">
      <div>
        <h1>Users</h1>
        <p>Manage the user directory and securely provision Maintenance Technicians.</p>
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
        aria-hidden={closeConfirmation ? 'true' : undefined}
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
      {closeConfirmation && <div className="admin-users-confirmation-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) cancelCloseConfirmation() }}>
        <section ref={confirmationRef} className="admin-users-confirmation" role="dialog" aria-modal="true" aria-labelledby="admin-close-confirmation-title" aria-describedby="admin-close-confirmation-description" onKeyDown={handleConfirmationKeyDown}>
          <span className="admin-users-confirmation__icon" aria-hidden="true"><Icon name="alert" size={22} /></span>
          <div className="admin-users-confirmation__copy">
            <h3 id="admin-close-confirmation-title">{closeConfirmation === 'setup-link' ? 'Clear the setup link?' : 'Discard Technician details?'}</h3>
            <p id="admin-close-confirmation-description">{closeConfirmation === 'setup-link'
              ? 'Closing this panel permanently clears the one-time setup link. Confirm only after it has been delivered securely.'
              : 'The Technician details entered in this form have not been submitted and will be discarded.'}</p>
          </div>
          <div className="admin-users-confirmation__actions">
            <button ref={confirmationCancelRef} className="shared-button shared-button--outline" type="button" onClick={cancelCloseConfirmation}>Keep panel open</button>
            <button className="shared-button admin-users-confirmation__confirm" type="button" onClick={finishClosingPanel}>{closeConfirmation === 'setup-link' ? 'Clear link and close' : 'Discard and close'}</button>
          </div>
        </section>
      </div>}
    </div>}

    <section className="shared-card admin-users-directory" aria-labelledby="admin-user-directory-title">
      <div className="admin-users-directory__heading">
        <div>
          <p className="admin-users-page__eyebrow">User management</p>
          <h2 id="admin-user-directory-title">User directory</h2>
          <p>{visibleDirectoryState.status === 'ready'
            ? `${visibleDirectoryState.data.pagination.totalCount} ${visibleDirectoryState.data.pagination.totalCount === 1 ? 'user' : 'users'} in the current results`
            : 'Authorized RentFlow accounts'}</p>
        </div>
        <StatusBadge tone={visibleDirectoryState.status === 'error' ? 'warning' : 'success'}>
          {visibleDirectoryState.status === 'error' ? 'Directory unavailable' : 'Directory available'}
        </StatusBadge>
      </div>

      <div className="admin-users-directory__controls">
        <form className="admin-users-directory__search" role="search" aria-label="Search user directory" onSubmit={submitDirectorySearch}>
          <Icon name="search" size={19} />
          <label className="admin-users-visually-hidden" htmlFor="adminUserSearch">Search users by name or email</label>
          <input
            id="adminUserSearch"
            type="search"
            maxLength="320"
            placeholder="Search by name or email..."
            value={searchDraft}
            onChange={(event) => setSearchDraft(event.target.value)}
          />
          <button type="submit">Search</button>
        </form>
        <label className="admin-users-directory__filter">
          <span className="admin-users-visually-hidden">Filter users by role</span>
          <select aria-label="Filter users by role" value={directoryQuery.role} onChange={updateDirectoryFilter('role')}>
            <option value="">All roles</option>
            {ADMIN_USER_ROLES.map((role) => <option key={role} value={role}>{roleLabel(role)}</option>)}
          </select>
        </label>
        <label className="admin-users-directory__filter">
          <span className="admin-users-visually-hidden">Filter users by active status</span>
          <select aria-label="Filter users by active status" value={directoryQuery.active} onChange={updateDirectoryFilter('active')}>
            <option value="">All statuses</option>
            <option value="true">Active</option>
            <option value="false">Inactive</option>
          </select>
        </label>
      </div>

      {visibleDirectoryState.status === 'loading' && <div className="admin-users-directory__state" role="status">
        <span className="shared-spinner" aria-hidden="true" />
        <h3>Loading user directory</h3>
        <p>Retrieving authorized user records.</p>
      </div>}

      {visibleDirectoryState.status === 'error' && <div className="admin-users-directory__state admin-users-directory__state--error" role="alert">
        <span className="admin-users-page__icon"><Icon name="alert" size={28} /></span>
        <h3>{visibleDirectoryState.error instanceof ApiError && [401, 403].includes(visibleDirectoryState.error.statusCode)
          ? 'Directory access unavailable'
          : 'User directory unavailable'}</h3>
        <p>{directoryErrorFor(visibleDirectoryState.error)}</p>
        {!(visibleDirectoryState.error instanceof ApiError && [401, 403].includes(visibleDirectoryState.error.statusCode))
          && <button className="shared-button" type="button" onClick={() => setDirectoryRefresh((current) => current + 1)}>Try again</button>}
      </div>}

      {visibleDirectoryState.status === 'ready' && visibleDirectoryState.data.items.length === 0 && <div className="admin-users-directory__state">
        <span className="admin-users-page__icon"><Icon name="search" size={28} /></span>
        <h3>No users match these filters</h3>
        <p>Try a different name, email, role, or active-status filter.</p>
        {(directoryQuery.search || directoryQuery.role || directoryQuery.active)
          && <button className="shared-button shared-button--quiet" type="button" onClick={clearDirectoryFilters}>Clear filters</button>}
      </div>}

      {visibleDirectoryState.status === 'ready' && visibleDirectoryState.data.items.length > 0 && <>
        <div className="admin-users-directory__table-wrap">
          <table className="admin-users-directory__table">
            <caption className="admin-users-visually-hidden">Admin-authorized RentFlow user directory</caption>
            <thead><tr><th scope="col">User</th><th scope="col">Role</th><th scope="col">Joined</th><th scope="col">Status</th></tr></thead>
            <tbody>{visibleDirectoryState.data.items.map((directoryUser) => <tr key={directoryUser.id}>
              <td data-label="User"><div className="admin-users-directory__identity"><span aria-hidden="true">{directoryUser.fullName.trim().charAt(0).toUpperCase()}</span><div><strong>{directoryUser.fullName}</strong><small>{directoryUser.email}</small></div></div></td>
              <td data-label="Role"><span className={`admin-users-directory__role admin-users-directory__role--${directoryUser.role.toLowerCase()}`}>{roleLabel(directoryUser.role)}</span></td>
              <td data-label="Joined"><time dateTime={directoryUser.createdAt}>{joinedDate(directoryUser.createdAt)}</time></td>
              <td data-label="Status"><span className={`admin-users-directory__status admin-users-directory__status--${directoryUser.isActive ? 'active' : 'inactive'}`}><span aria-hidden="true" />{directoryUser.isActive ? 'Active' : 'Inactive'}</span></td>
            </tr>)}</tbody>
          </table>
        </div>
        <nav className="admin-users-directory__pagination" aria-label="User directory pagination">
          <p>Showing {(visibleDirectoryState.data.pagination.page - 1) * visibleDirectoryState.data.pagination.pageSize + 1}-{Math.min(visibleDirectoryState.data.pagination.page * visibleDirectoryState.data.pagination.pageSize, visibleDirectoryState.data.pagination.totalCount)} of {visibleDirectoryState.data.pagination.totalCount}</p>
          <div>
            <button className="shared-button shared-button--quiet" type="button" disabled={!visibleDirectoryState.data.pagination.hasPreviousPage} onClick={() => setDirectoryPage((current) => current - 1)}>Previous</button>
            <span>Page {visibleDirectoryState.data.pagination.page} of {visibleDirectoryState.data.pagination.totalPages}</span>
            <button className="shared-button shared-button--quiet" type="button" disabled={!visibleDirectoryState.data.pagination.hasNextPage} onClick={() => setDirectoryPage((current) => current + 1)}>Next</button>
          </div>
        </nav>
      </>}

      <div className="admin-users-directory__note"><Icon name="info" size={18} /><span>User directory access and Technician provisioning are available. Deactivation, role editing, deletion, and other account-changing operations are not supported.</span></div>
    </section>
  </main>
}
