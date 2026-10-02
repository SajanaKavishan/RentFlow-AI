import { useEffect, useState } from 'react'
import { getViewingAvailability, saveViewingAvailability } from '../services/viewingAvailabilityApi.js'
import './viewing-availability.css'

// Shared contract: Sunday=0 through Saturday=6. Display Monday first.
const WEEKDAYS = [[1, 'Monday'], [2, 'Tuesday'], [3, 'Wednesday'], [4, 'Thursday'], [5, 'Friday'], [6, 'Saturday'], [0, 'Sunday']]
const DURATIONS = [30, 45, 60, 90]

function parseSchedule(value, propertyId) {
  if (value?.propertyId?.toLowerCase() !== propertyId.toLowerCase()
    || typeof value.timeZoneId !== 'string' || !DURATIONS.includes(value.slotDurationMinutes)
    || !Array.isArray(value.windows) || value.windows.length > 7
    || new Set(value.windows.map(w => w.dayOfWeek)).size !== value.windows.length
    || value.windows.some(w => !Number.isInteger(w.dayOfWeek) || w.dayOfWeek < 0 || w.dayOfWeek > 6
      || typeof w.isEnabled !== 'boolean'
      || (w.isEnabled && (!/^\d{2}:\d{2}(:00)?$/.test(w.startTime) || !/^\d{2}:\d{2}(:00)?$/.test(w.endTime))))) {
    throw new Error('The viewing schedule response could not be verified.')
  }
  return { ...value, windows: WEEKDAYS.map(([dayOfWeek]) => {
    const row = value.windows.find(w => w.dayOfWeek === dayOfWeek)
    return { dayOfWeek, isEnabled: row?.isEnabled ?? false,
      startTime: row?.isEnabled ? row.startTime.slice(0, 5) : '', endTime: row?.isEnabled ? row.endTime.slice(0, 5) : '' }
  }) }
}

function validation(schedule) {
  const errors = {}
  for (const row of schedule.windows.filter(w => w.isEnabled)) {
    const minutes = value => value ? Number(value.slice(0, 2)) * 60 + Number(value.slice(3, 5)) : NaN
    const start = minutes(row.startTime), end = minutes(row.endTime)
    if (!Number.isFinite(start) || !Number.isFinite(end) || start >= end)
      errors[row.dayOfWeek] = 'Choose a start time before the end time.'
    else if (end - start < schedule.slotDurationMinutes)
      errors[row.dayOfWeek] = 'The window must fit at least one complete slot.'
  }
  return errors
}

export default function ViewingAvailabilityEditor({ propertyId, onDirtyChange, disabled = false }) {
  const [schedule, setSchedule] = useState(null)
  const [saved, setSaved] = useState('')
  const [error, setError] = useState('')
  const [errors, setErrors] = useState({})
  const [saving, setSaving] = useState(false)
  const [notice, setNotice] = useState('')
  const [attempt, setAttempt] = useState(0)
  const dirty = schedule !== null && JSON.stringify(schedule) !== saved

  useEffect(() => {
    let active = true
    getViewingAvailability(propertyId).then(value => {
      const parsed = parseSchedule(value, propertyId)
      if (active) { setSchedule(parsed); setSaved(JSON.stringify(parsed)); setError('') }
    }).catch(err => { if (active) setError(err.message || 'Unable to load viewing availability.') })
    return () => { active = false }
  }, [propertyId, attempt])

  useEffect(() => { onDirtyChange?.(dirty) }, [dirty, onDirtyChange])
  useEffect(() => {
    if (schedule && window.location.hash === '#viewing-availability') {
      document.getElementById('viewing-availability')?.scrollIntoView?.()
    }
  }, [schedule])

  function updateDay(dayOfWeek, update) {
    setSchedule(current => ({ ...current, windows: current.windows.map(row => row.dayOfWeek === dayOfWeek
      ? { ...row, ...update } : row) }))
    setErrors({}); setNotice('')
  }

  async function save(event) {
    event.preventDefault()
    if (saving || disabled) return
    const invalid = validation(schedule)
    setErrors(invalid)
    if (Object.keys(invalid).length) return
    setSaving(true); setError(''); setNotice('')
    try {
      const result = parseSchedule(await saveViewingAvailability(propertyId, {
        ...schedule, windows: schedule.windows.map(row => ({ ...row,
          startTime: row.isEnabled ? `${row.startTime}:00` : null,
          endTime: row.isEnabled ? `${row.endTime}:00` : null }))
      }), propertyId)
      setSchedule(result); setSaved(JSON.stringify(result)); setNotice('Viewing availability saved.')
    } catch (err) { setError(err.message || 'Unable to save viewing availability.') }
    finally { setSaving(false) }
  }

  return <section id="viewing-availability" className="viewing-availability" aria-labelledby="viewing-availability-title">
    <h2 id="viewing-availability-title">Viewing availability</h2>
    <p>Choose when tenants can request a viewing. Requests still need your approval.</p>
    {error && <p role="alert">{error}</p>}
    {!schedule && (error ? <button type="button" onClick={() => { setError(''); setAttempt(a => a + 1) }}>Retry availability</button>
      : <p role="status">Loading viewing availability...</p>)}
    {schedule && <form onSubmit={save}>
      <p>Timezone: {schedule.timeZoneId === 'Asia/Colombo' ? 'Sri Lanka (Asia/Colombo)' : schedule.timeZoneId}</p>
      <label className="viewing-duration">Slot duration
        <select aria-label="Slot duration" value={schedule.slotDurationMinutes} disabled={saving || disabled}
          onChange={event => { setSchedule(s => ({ ...s, slotDurationMinutes: Number(event.target.value) })); setErrors({}); setNotice('') }}>
          {DURATIONS.map(value => <option key={value} value={value}>{value} minutes</option>)}
        </select>
      </label>
      {!schedule.windows.some(w => w.isEnabled) && <p>No weekdays are enabled. Tenants will see no viewing times.</p>}
      <fieldset disabled={saving || disabled}>
        <legend>Available weekdays</legend>
        {WEEKDAYS.map(([day, name]) => {
          const row = schedule.windows.find(w => w.dayOfWeek === day)
          return <div key={day} className="viewing-weekday">
            <label><input type="checkbox" checked={row.isEnabled} aria-label={`${name} enabled`}
              onChange={event => updateDay(day, { isEnabled: event.target.checked, startTime: '', endTime: '' })} />{name}</label>
            {row.isEnabled && <><input type="time" aria-label={`${name} start`} value={row.startTime}
              onChange={event => updateDay(day, { startTime: event.target.value })} /><span>to</span>
              <input type="time" aria-label={`${name} end`} value={row.endTime}
                onChange={event => updateDay(day, { endTime: event.target.value })} /></>}
            {errors[day] && <span role="alert" className="viewing-day-error">{errors[day]}</span>}
          </div>
        })}
      </fieldset>
      {dirty && <p role="status">Unsaved viewing availability changes</p>}
      {notice && <p role="status">{notice}</p>}
      <button className="property-button property-button--primary" type="submit" disabled={saving || disabled || !dirty}>
        {saving ? 'Saving availability...' : 'Save viewing availability'}
      </button>
    </form>}
  </section>
}
