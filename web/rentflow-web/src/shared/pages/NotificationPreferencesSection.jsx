import { useEffect, useState } from 'react'
import {
  getNotificationPreferences,
  updateNotificationPreferences,
} from '../../features/notifications/notificationPreferencesApi.js'
import { AppCard } from '../ui/States.jsx'

function PreferenceToggle({ id, title, explanation, checked, disabled, required, onChange }) {
  return <div className="notification-preference">
    <label className="notification-preference__copy" htmlFor={id}>
      <strong>{title}</strong>
      <small id={`${id}-description`}>{explanation}</small>
    </label>
    <span className="notification-preference__control">
      {required && <span className="notification-preference__required">On / Required</span>}
      <input
        id={id}
        type="checkbox"
        checked={checked}
        disabled={disabled}
        aria-describedby={`${id}-description`}
        onChange={onChange}
      />
    </span>
  </div>
}

export default function NotificationPreferencesSection({ userId, showToast }) {
  const [loadAttempt, setLoadAttempt] = useState(0)
  const [state, setState] = useState({ status: 'loading', saved: null, draft: null, message: '' })

  useEffect(() => {
    let active = true
    getNotificationPreferences()
      .then((preferences) => {
        if (active) setState({ status: 'ready', saved: preferences, draft: preferences, message: '' })
      })
      .catch((error) => {
        if (active) setState({
          status: 'load-error',
          saved: null,
          draft: null,
          message: error?.message || 'Notification preferences could not be loaded.',
        })
      })
    return () => { active = false }
  }, [userId, loadAttempt])

  const setOptionalPreference = (name, checked) => {
    setState((current) => ({
      ...current,
      status: 'ready',
      message: '',
      draft: { ...current.draft, [name]: checked },
    }))
  }

  const save = async () => {
    const requested = state.draft
    setState((current) => ({ ...current, status: 'saving', message: '' }))
    try {
      const confirmed = await updateNotificationPreferences(requested)
      setState({ status: 'success', saved: confirmed, draft: confirmed, message: 'Notification preferences saved.' })
      showToast?.('success', 'Notification preferences saved.')
    } catch (error) {
      const message = error?.message || 'Notification preferences could not be saved.'
      setState((current) => ({ ...current, status: 'save-error', message }))
      showToast?.('error', message)
    }
  }

  if (state.status === 'loading') {
    return <section className="shared-card profile-section__card notification-preferences-state" role="status">
      <p>Loading notification preferences&hellip;</p>
    </section>
  }

  if (state.status === 'load-error') {
    return <section className="shared-card profile-section__card notification-preferences-state" role="alert">
      <p>{state.message}</p>
      <button className="shared-button shared-button--outline" type="button" onClick={() => {
        setState({ status: 'loading', saved: null, draft: null, message: '' })
        setLoadAttempt((attempt) => attempt + 1)
      }}>Retry</button>
    </section>
  }

  const busy = state.status === 'saving'
  const dirty = state.draft.viewingUpdatesEnabled !== state.saved.viewingUpdatesEnabled
    || state.draft.rentalApplicationUpdatesEnabled !== state.saved.rentalApplicationUpdatesEnabled

  return <AppCard className="profile-section__card notification-preferences">
    <div className="notification-preferences__list">
      <PreferenceToggle
        id="viewingUpdatesEnabled"
        title="Viewing updates"
        explanation="New viewing requests and viewing decisions."
        checked={state.draft.viewingUpdatesEnabled}
        disabled={busy}
        onChange={(event) => setOptionalPreference('viewingUpdatesEnabled', event.target.checked)}
      />
      <PreferenceToggle
        id="rentalApplicationUpdatesEnabled"
        title="Rental application updates"
        explanation="Application submissions, decisions, and requested changes."
        checked={state.draft.rentalApplicationUpdatesEnabled}
        disabled={busy}
        onChange={(event) => setOptionalPreference('rentalApplicationUpdatesEnabled', event.target.checked)}
      />
      <PreferenceToggle
        id="accountSecurityUpdatesEnabled"
        title="Account & security updates"
        explanation="Critical account notices cannot be disabled."
        checked
        disabled
        required
        onChange={() => {}}
      />
    </div>
    <div className="notification-preferences__actions">
      <div aria-live="polite">
        {state.status === 'saving' && <span role="status">Saving notification preferences&hellip;</span>}
        {state.status === 'success' && <span role="status">{state.message}</span>}
        {state.status === 'save-error' && <span role="alert">{state.message} Your previous settings are still saved.</span>}
      </div>
      <button className="shared-button" type="button" disabled={busy || (!dirty && state.status !== 'save-error')} onClick={save}>
        {state.status === 'save-error' ? 'Try again' : busy ? 'Saving...' : 'Save preferences'}
      </button>
    </div>
  </AppCard>
}
