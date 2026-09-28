import { useCallback, useEffect, useRef, useState } from 'react'
import MatchPreferenceSummary from './MatchPreferenceSummary.jsx'
import MatchPreferencesDialog from './MatchPreferencesDialog.jsx'
import {
  getMatchPreferences,
  resetMatchPreferences,
  saveMatchPreferences,
} from '../services/propertyApiService.js'
import '../properties.css'

export default function TenantMatchPreferencesSection({ userId, showToast }) {
  const [state, setState] = useState({ status: 'loading', data: null, message: '' })
  const [editing, setEditing] = useState(false)
  const actionRef = useRef(null)

  const load = useCallback(async () => {
    setState({ status: 'loading', data: null, message: '' })
    try {
      const data = await getMatchPreferences()
      setState({ status: 'ready', data, message: '' })
    } catch (error) {
      setState({ status: 'error', data: null, message: error.message || "We couldn't load your match preferences." })
    }
  }, [])

  useEffect(() => {
    Promise.resolve().then(load)
  }, [load, userId])

  const close = () => {
    setEditing(false)
    window.requestAnimationFrame(() => actionRef.current?.focus())
  }
  const save = async (request) => {
    const data = await saveMatchPreferences(request)
    setState({ status: 'ready', data, message: '' })
    showToast?.('success', 'Match preferences saved.')
    close()
  }
  const reset = async () => {
    await resetMatchPreferences()
    setState({ status: 'ready', data: { isConfigured: false, preferredAmenities: [] }, message: '' })
    showToast?.('success', 'Match preferences reset.')
    close()
  }

  return <>
    <div className="profile-match-preferences" aria-busy={state.status === 'loading'}>
      {state.status === 'loading' && <p role="status">Loading match preferences…</p>}
      {state.status === 'error' && <div role="alert"><p>{state.message}</p><button type="button" className="shared-button shared-button--outline" onClick={load}>Retry</button></div>}
      {state.status === 'ready' && state.data?.isConfigured && <MatchPreferenceSummary preferences={state.data} />}
      {state.status === 'ready' && !state.data?.isConfigured && <div className="profile-match-preferences__empty"><strong>Get personalized property matches</strong><p>Set your rental preferences to rank real available properties.</p></div>}
      {state.status === 'ready' && <button ref={actionRef} type="button" className="profile-match-preferences__action" onClick={() => setEditing(true)}>{state.data?.isConfigured ? 'Edit preferences' : 'Set match preferences'}</button>}
    </div>
    {editing && <MatchPreferencesDialog preferences={state.data} onClose={close} onSave={save} onReset={reset} />}
  </>
}
