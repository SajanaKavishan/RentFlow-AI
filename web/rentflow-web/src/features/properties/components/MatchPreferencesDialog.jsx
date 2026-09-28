import { useEffect, useMemo, useRef, useState } from 'react'
import Icon from '../../../shared/ui/Icons.jsx'

const emptyForm = {
  preferredCity: '',
  maximumMonthlyRent: '',
  minimumBedrooms: '',
  minimumBathrooms: '',
  preferredAmenities: '',
}

function preferenceForm(preferences) {
  if (!preferences?.isConfigured) return emptyForm
  return {
    preferredCity: preferences.preferredCity || '',
    maximumMonthlyRent: preferences.maximumMonthlyRent ?? '',
    minimumBedrooms: preferences.minimumBedrooms ?? '',
    minimumBathrooms: preferences.minimumBathrooms ?? '',
    preferredAmenities: (preferences.preferredAmenities || []).join(', '),
  }
}

function requestFrom(form) {
  return {
    preferredCity: form.preferredCity.trim() || null,
    maximumMonthlyRent: form.maximumMonthlyRent === '' ? null : Number(form.maximumMonthlyRent),
    minimumBedrooms: form.minimumBedrooms === '' ? null : Number(form.minimumBedrooms),
    minimumBathrooms: form.minimumBathrooms === '' ? null : Number(form.minimumBathrooms),
    preferredAmenities: form.preferredAmenities
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean),
  }
}

export default function MatchPreferencesDialog({ preferences, onClose, onSave, onReset }) {
  const [form, setForm] = useState(() => preferenceForm(preferences))
  const [status, setStatus] = useState('idle')
  const [error, setError] = useState('')
  const cityRef = useRef(null)
  const initialRequest = useMemo(() => requestFrom(preferenceForm(preferences)), [preferences])
  const currentRequest = requestFrom(form)
  const hasChanges = JSON.stringify(currentRequest) !== JSON.stringify(initialRequest)

  useEffect(() => {
    cityRef.current?.focus()
    const onKeyDown = (event) => {
      if (event.key === 'Escape' && status !== 'saving') onClose()
    }
    document.addEventListener('keydown', onKeyDown)
    return () => document.removeEventListener('keydown', onKeyDown)
  }, [onClose, status])

  const update = (event) => {
    const { name, value } = event.target
    setForm((current) => ({ ...current, [name]: value }))
  }

  const submit = async (event) => {
    event.preventDefault()
    const request = requestFrom(form)
    if (!request.preferredCity
      && request.maximumMonthlyRent === null
      && request.minimumBedrooms === null
      && request.minimumBathrooms === null
      && request.preferredAmenities.length === 0) {
      setError('Set at least one match preference.')
      return
    }
    setStatus('saving')
    setError('')
    try {
      await onSave(request)
    } catch (saveError) {
      setStatus('idle')
      setError(saveError.message || "We couldn't save your match preferences.")
    }
  }

  const reset = async () => {
    if (!preferences?.isConfigured) {
      setForm(emptyForm)
      setError('')
      cityRef.current?.focus()
      return
    }
    setStatus('saving')
    setError('')
    try {
      await onReset()
    } catch (resetError) {
      setStatus('idle')
      setError(resetError.message || "We couldn't reset your match preferences.")
    }
  }

  return <div className="match-dialog-backdrop" role="presentation" onMouseDown={(event) => {
    if (event.target === event.currentTarget && status !== 'saving') onClose()
  }}>
    <section className="match-dialog" role="dialog" aria-modal="true" aria-labelledby="match-dialog-title">
      <header className="match-dialog__header">
        <div><p>Personalized matching</p><h2 id="match-dialog-title">{preferences?.isConfigured ? 'Edit match preferences' : 'Set match preferences'}</h2></div>
        <button type="button" className="match-dialog__close" aria-label="Close match preferences" onClick={onClose} disabled={status === 'saving'}><Icon name="close" size={20} /></button>
      </header>
      <form className="match-dialog__form" onSubmit={submit}>
        <p className="match-dialog__intro">RentFlow uses only the preferences you provide here to rank currently available properties.</p>
        <div className="match-dialog__fields">
          <label className="property-form-field property-form-field--wide"><span>Preferred city</span><input ref={cityRef} name="preferredCity" value={form.preferredCity} onChange={update} maxLength="100" placeholder="e.g. Kurunegala" disabled={status === 'saving'} /></label>
          <label className="property-form-field"><span>Maximum monthly rent</span><div className="property-input-prefix"><span>Rs.</span><input type="number" min="0" name="maximumMonthlyRent" value={form.maximumMonthlyRent} onChange={update} placeholder="150000" disabled={status === 'saving'} /></div></label>
          <label className="property-form-field"><span>Minimum bedrooms</span><select name="minimumBedrooms" value={form.minimumBedrooms} onChange={update} disabled={status === 'saving'}><option value="">Any</option><option value="1">1+</option><option value="2">2+</option><option value="3">3+</option><option value="4">4+</option><option value="5">5+</option></select></label>
          <label className="property-form-field"><span>Minimum bathrooms</span><select name="minimumBathrooms" value={form.minimumBathrooms} onChange={update} disabled={status === 'saving'}><option value="">Any</option><option value="1">1+</option><option value="2">2+</option><option value="3">3+</option><option value="4">4+</option></select></label>
          <label className="property-form-field property-form-field--wide"><span>Preferred amenities</span><input name="preferredAmenities" value={form.preferredAmenities} onChange={update} placeholder="Parking, Security" disabled={status === 'saving'} /><small>Separate amenities with commas.</small></label>
        </div>
        {error && <p className="match-dialog__error" role="alert">{error}</p>}
        <footer className="match-dialog__actions">
          <button type="button" className="property-button property-button--danger-quiet" onClick={reset} disabled={status === 'saving'}>Reset preferences</button>
          <div><button type="button" className="property-button property-button--quiet" onClick={onClose} disabled={status === 'saving'}>Cancel</button><button type="submit" className="property-button property-button--primary" disabled={status === 'saving' || !hasChanges}>{status === 'saving' ? 'Saving…' : 'Save preferences'}</button></div>
        </footer>
      </form>
    </section>
  </div>
}
