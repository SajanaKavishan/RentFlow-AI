import { useEffect, useRef, useState } from 'react'
import { ApiError } from '../../core/api/apiClient.js'
import { deactivateAdminUser, getAdminUserDetails } from './adminUsersApi.js'
import Icon from '../../shared/ui/Icons.jsx'

export default function AdminUserProfileDialog({ id, currentUserId, confirmInitially = false, onClose, onUpdated, returnFocusRef }) {
  const [state, setState] = useState({ status: 'loading', user: null })
  const [retry, setRetry] = useState(0)
  const [confirming, setConfirming] = useState(confirmInitially)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState(false)
  const dialog = useRef(null)
  const close = useRef(null)
  const mutation = useRef(null)

  useEffect(() => {
    const trigger = document.activeElement
    const fallback = returnFocusRef?.current
    const overflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    close.current?.focus()
    return () => {
      document.body.style.overflow = overflow
      mutation.current?.abort()
      if (trigger?.isConnected) trigger.focus()
      else if (fallback?.isConnected) fallback.focus()
    }
  }, [returnFocusRef])

  useEffect(() => {
    const controller = new AbortController()
    getAdminUserDetails(id, controller.signal).then((user) => {
      if (!controller.signal.aborted) setState({ status: 'ready', user })
    }).catch(() => { if (!controller.signal.aborted) setState({ status: 'error', user: null }) })
    return () => controller.abort()
  }, [id, retry])

  async function deactivate() {
    if (mutation.current || !state.user?.isActive || state.user.id.toLowerCase() === currentUserId.toLowerCase()) return
    const controller = new AbortController()
    mutation.current = controller
    setBusy(true)
    setError('')
    try {
      const user = await deactivateAdminUser(id, controller.signal)
      if (controller.signal.aborted) return
      setState({ status: 'ready', user })
      setConfirming(false)
      setSuccess(true)
      onUpdated(user)
    } catch (caught) {
      if (!controller.signal.aborted) setError(caught instanceof ApiError ? caught.message : 'The account could not be deactivated. Please try again.')
    } finally {
      if (!controller.signal.aborted) { mutation.current = null; setBusy(false) }
    }
  }

  function keyDown(event) {
    if (event.key === 'Escape') { event.preventDefault(); if (!busy) onClose(); return }
    if (event.key !== 'Tab') return
    const buttons = Array.from(dialog.current.querySelectorAll('button:not([disabled])'))
    if (!buttons.length) { event.preventDefault(); return }
    const first = buttons[0], last = buttons.at(-1)
    if (!buttons.includes(document.activeElement) || (event.shiftKey && document.activeElement === first)) { event.preventDefault(); (event.shiftKey ? last : first)?.focus() }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus() }
  }

  const user = state.user
  const isSelf = user?.id.toLowerCase() === currentUserId.toLowerCase()
  return <div className="admin-users-modal" onMouseDown={(event) => { if (!busy && event.target === event.currentTarget) onClose() }}>
    <section ref={dialog} className="shared-card admin-user-profile" role="dialog" aria-modal="true" aria-labelledby="admin-user-profile-title" onKeyDown={keyDown}>
      <header><h2 id="admin-user-profile-title">User Profile</h2><button ref={close} type="button" className="admin-users-provisioning__close" aria-label="Close user profile" disabled={busy} onClick={onClose}><Icon name="close" size={20} /></button></header>
      {state.status === 'loading' && <p role="status">Loading user details…</p>}
      {state.status === 'error' && <div role="alert"><p>User details could not be loaded.</p><button type="button" className="shared-button shared-button--outline" onClick={() => { setState({ status: 'loading', user: null }); setRetry((value) => value + 1) }}>Try again</button></div>}
      {user && <>
        <div className="admin-user-profile__identity"><span aria-hidden="true">{user.fullName.trim().charAt(0).toUpperCase()}</span><h3>{user.fullName}</h3>
          <span className={`admin-users-directory__role admin-users-directory__role--${user.role.toLowerCase()}`}>{user.role === 'MaintenanceTechnician' ? 'Technician' : user.role}</span></div>
        <dl><div><dt>Email</dt><dd>{user.email}</dd></div><div><dt>Phone</dt><dd>{user.phoneNumber || 'Not provided'}</dd></div>
          <div><dt>Status</dt><dd>{user.isActive ? 'Active' : 'Inactive'}</dd></div>
          <div><dt>Joined</dt><dd>{new Date(user.createdAt).toLocaleDateString('en-US', { timeZone: 'Asia/Colombo', year: 'numeric', month: 'short', day: 'numeric' })}</dd></div></dl>
        {success && <p role="status" className="admin-user-profile__success">Account deactivated. Sign-in and existing sessions are blocked.</p>}
        {error && <p role="alert">{error}</p>}
        {user.isActive && !isSelf && (confirming ? <div className="admin-user-profile__confirm"><p>Deactivate {user.fullName}? This will block sign-in and revoke existing sessions.</p>
          <div><button type="button" className="shared-button shared-button--outline" disabled={busy} onClick={() => { setConfirming(false); setError('') }}>Cancel</button>
            <button type="button" className="admin-user-deactivate" disabled={busy} onClick={deactivate}>{busy ? 'Deactivating…' : 'Confirm deactivation'}</button></div></div>
          : <button type="button" className="admin-user-deactivate admin-user-profile__deactivate" onClick={() => setConfirming(true)}>Deactivate Account</button>)}
        {isSelf && <p className="admin-user-profile__note">You cannot deactivate your own Admin account.</p>}
      </>}
    </section>
  </div>
}
