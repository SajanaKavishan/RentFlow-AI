import { useEffect, useRef, useState } from 'react'
import { useAuth } from '../../features/auth/useAuth.js'
import ProfileAvatar from '../../features/auth/ProfileAvatar.jsx'
import { USER_ROLES } from '../../features/auth/authModel.js'
import { AppCard, PageHeader } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import TenantApplicationDocuments from './TenantApplicationDocuments.jsx'
import NotificationPreferencesSection from './NotificationPreferencesSection.jsx'
import ChangePasswordDialog from './ChangePasswordDialog.jsx'
import SupportRequestsSection from './SupportRequestsSection.jsx'
import TenantMatchPreferencesSection from '../../features/properties/components/TenantMatchPreferencesSection.jsx'
import './profile.css'

const allowedImageTypes = new Set(['image/jpeg', 'image/png', 'image/webp'])
const maximumImageBytes = 5 * 1024 * 1024

function validateProfile(fullName, phoneNumber) {
  const name = fullName.trim()
  const phone = phoneNumber.trim()
  if (name.length < 2 || name.length > 200) return 'Full name must be between 2 and 200 characters.'
  if (!/^[+\d][\d\s().-]{6,31}$/.test(phone)) return 'Enter a valid phone number.'
  return null
}

export default function ProfilePage() {
  const { user, updateProfile, uploadProfileImage, changePassword } = useAuth()
  const showsNotificationPreferences = [USER_ROLES.TENANT, USER_ROLES.LANDLORD].includes(user.role)
  const isAdmin = user.role === USER_ROLES.ADMIN
  const [editing, setEditing] = useState(false)
  const [form, setForm] = useState(() => ({ fullName: user.fullName, phoneNumber: user.phoneNumber }))
  const [imageFile, setImageFile] = useState(null)
  const [imageError, setImageError] = useState('')
  const [previewUrl, setPreviewUrl] = useState(null)
  const previewUrlRef = useRef(null)
  const [submitState, setSubmitState] = useState({ status: 'idle', message: '' })
  const [toast, setToast] = useState(null)
  const [changingPassword, setChangingPassword] = useState(false)
  const changePasswordButtonRef = useRef(null)
  const hasProfileChanges = form.fullName.trim() !== user.fullName.trim()
    || (form.phoneNumber || '').trim() !== (user.phoneNumber?.trim() || '')
    || imageFile !== null
  const profileLayoutClassName = isAdmin
    ? 'profile-layout profile-layout--account-only'
    : `profile-layout${showsNotificationPreferences ? '' : ' profile-layout--without-preferences'}`

  useEffect(() => () => {
    if (previewUrlRef.current) URL.revokeObjectURL(previewUrlRef.current)
  }, [])
  useEffect(() => {
    if (!toast) return undefined
    const timer = window.setTimeout(() => setToast(null), 3000)
    return () => window.clearTimeout(timer)
  }, [toast])

  const showToast = (tone, message) => setToast({ id: Date.now(), tone, message })
  const closeChangePassword = () => {
    setChangingPassword(false)
    window.requestAnimationFrame(() => changePasswordButtonRef.current?.focus())
  }

  const clearSelectedImage = () => {
    if (previewUrlRef.current) URL.revokeObjectURL(previewUrlRef.current)
    previewUrlRef.current = null
    setPreviewUrl(null)
    setImageFile(null)
  }

  const startEditing = () => {
    setForm({ fullName: user.fullName, phoneNumber: user.phoneNumber })
    clearSelectedImage()
    setImageError('')
    setSubmitState({ status: 'idle', message: '' })
    setEditing(true)
  }
  const cancelEditing = () => {
    setEditing(false)
    clearSelectedImage()
    setImageError('')
    setSubmitState({ status: 'idle', message: '' })
  }
  const chooseImage = (event) => {
    const file = event.target.files?.[0] || null
    if (!file) { clearSelectedImage(); setImageError(''); return }
    if (!allowedImageTypes.has(file.type)) {
      clearSelectedImage()
      const message = 'Choose a JPEG, PNG, or WEBP image.'
      setImageError(message)
      showToast('error', message)
      return
    }
    if (file.size <= 0 || file.size > maximumImageBytes) {
      clearSelectedImage()
      const message = 'Profile image must be no larger than 5 MB.'
      setImageError(message)
      showToast('error', message)
      return
    }
    clearSelectedImage()
    setImageError('')
    setImageFile(file)
    const url = URL.createObjectURL(file)
    previewUrlRef.current = url
    setPreviewUrl(url)
  }
  const submit = async (event) => {
    event.preventDefault()
    if (!hasProfileChanges) return
    const validationError = validateProfile(form.fullName, form.phoneNumber)
    if (validationError || imageError) {
      const message = validationError || imageError
      setSubmitState({ status: 'error', message })
      showToast('error', message)
      return
    }
    setSubmitState({ status: 'submitting', message: '' })
    try {
      await updateProfile({ fullName: form.fullName.trim(), phoneNumber: form.phoneNumber.trim() })
      if (imageFile) await uploadProfileImage(imageFile)
      setEditing(false)
      clearSelectedImage()
      setSubmitState({ status: 'success', message: 'Profile updated successfully.' })
      showToast('success', 'Profile updated successfully.')
    } catch (error) {
      const message = error?.message || 'Your profile could not be updated.'
      setSubmitState({ status: 'error', message })
      showToast('error', message)
    }
  }

  return <main className="shared-page profile-page">
    {toast && <div className={`profile-toast profile-toast--${toast.tone}`} role={toast.tone === 'error' ? 'alert' : 'status'} aria-live="polite">
      <span className="profile-toast__mark" aria-hidden="true">{toast.tone === 'success' ? '✓' : '×'}</span>
      <p>{toast.message}</p>
    </div>}
    <PageHeader eyebrow="Your account" title="Profile">
      <p>View and update your account details.</p>
    </PageHeader>

    <AppCard className="profile-identity">
      <ProfileAvatar user={user} className="profile-identity__avatar" previewUrl={previewUrl} />
      <div className="profile-identity__copy">
        <h2>{user.fullName}</h2>
        <p>{user.email}</p>
      </div>
    </AppCard>

    <div className={profileLayoutClassName}>
      <section className="profile-section profile-section--account" aria-labelledby="profile-account-title">
        <h2 id="profile-account-title">Account</h2>
        <AppCard className="profile-section__card">
          <dl className="profile-details">
            <div><dt>Full name</dt><dd>{user.fullName}</dd></div>
            <div><dt>Email address</dt><dd>{user.email}</dd></div>
            <div><dt>Phone number</dt><dd>{user.phoneNumber?.trim() || 'Not provided'}</dd></div>
          </dl>
          {editing && <form className="profile-edit" aria-label="Edit profile" onSubmit={submit}>
            <div className="profile-edit__fields">
              <label htmlFor="profileFullName">Full name<input id="profileFullName" value={form.fullName} maxLength="200" autoComplete="name" disabled={submitState.status === 'submitting'} onChange={(event) => setForm((current) => ({ ...current, fullName: event.target.value }))} /></label>
              <label htmlFor="profilePhoneNumber">Phone number<input id="profilePhoneNumber" type="tel" value={form.phoneNumber} maxLength="32" autoComplete="tel" disabled={submitState.status === 'submitting'} onChange={(event) => setForm((current) => ({ ...current, phoneNumber: event.target.value }))} /></label>
              <label className="profile-edit__image" htmlFor="profileImage">Profile image<span>JPEG, PNG, or WEBP. Maximum 5 MB.</span><input id="profileImage" type="file" accept="image/jpeg,image/png,image/webp" disabled={submitState.status === 'submitting'} onChange={chooseImage} /></label>
            </div>
            <div className="profile-edit__buttons">
              <button className="shared-button shared-button--outline" type="button" disabled={submitState.status === 'submitting'} onClick={cancelEditing}>Cancel</button>
              <button className="shared-button profile-edit__save" type="submit" disabled={submitState.status === 'submitting' || !hasProfileChanges}>{submitState.status === 'submitting' ? 'Saving…' : 'Save profile'}</button>
            </div>
          </form>}
          <div className="profile-actions">
            {user.role === USER_ROLES.TENANT && <TenantApplicationDocuments key={user.id} />}
            <button className="profile-action profile-action--available" type="button" onClick={startEditing} disabled={editing}>
              <span className="profile-action__icon"><Icon name="user" size={20} /></span>
              <span className="profile-action__copy"><strong>Edit profile</strong><small>Update your name, phone number, and profile image.</small></span>
              <Icon name="arrow" size={18} />
            </button>
            <button ref={changePasswordButtonRef} className="profile-action profile-action--available" type="button" onClick={() => setChangingPassword(true)}>
              <span className="profile-action__icon"><Icon name="shield" size={20} /></span>
              <span className="profile-action__copy"><strong>Change password</strong><small>Update your password securely.</small></span>
              <Icon name="arrow" size={18} />
            </button>
          </div>
        </AppCard>
      </section>

      {showsNotificationPreferences && <section className="profile-section profile-section--preferences" aria-labelledby="profile-preferences-title">
        <h2 id="profile-preferences-title">Preferences</h2>
        <NotificationPreferencesSection key={user.id} userId={user.id} showToast={showToast} />
      </section>}

      {user.role === USER_ROLES.TENANT && <section className="profile-section profile-section--match" aria-labelledby="profile-match-title">
        <h2 id="profile-match-title">Match Preferences</h2>
        <AppCard className="profile-section__card">
          <TenantMatchPreferencesSection key={user.id} userId={user.id} showToast={showToast} />
        </AppCard>
      </section>}

      {!isAdmin && <section className="profile-section profile-section--support" aria-labelledby="profile-support-title">
        <h2 id="profile-support-title">Support</h2>
        <AppCard className="profile-section__card profile-actions">
          <SupportRequestsSection key={user.id} />
        </AppCard>
      </section>}
    </div>
    {changingPassword && <ChangePasswordDialog changePassword={changePassword} onClose={closeChangePassword} onSuccess={(message) => showToast('success', message)} />}
  </main>
}
