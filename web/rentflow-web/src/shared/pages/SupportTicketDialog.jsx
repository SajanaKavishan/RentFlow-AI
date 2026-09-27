import { useEffect, useRef, useState } from 'react'
import { SUPPORT_CATEGORIES } from '../../features/supportTickets/supportTicketsApi.js'
import Icon from '../ui/Icons.jsx'

const initialForm = { category: '', subject: '', message: '' }

function validate(form) {
  if (!SUPPORT_CATEGORIES.some(({ value }) => value === form.category)) return 'Select a support category.'
  const subjectLength = form.subject.trim().length
  if (subjectLength === 0) return 'Enter a subject.'
  if (subjectLength > 200) return 'Subject must be 200 characters or fewer.'
  const messageLength = form.message.trim().length
  if (messageLength === 0) return 'Enter a message.'
  if (messageLength > 4000) return 'Message must be 4,000 characters or fewer.'
  return ''
}

export default function SupportTicketDialog({ createTicket, onClose, onCreated }) {
  const [form, setForm] = useState(initialForm)
  const [state, setState] = useState({ type: 'idle', message: '' })
  const categoryRef = useRef(null)
  const dialogRef = useRef(null)
  const isSubmitting = state.type === 'submitting'

  useEffect(() => { categoryRef.current?.focus() }, [])

  useEffect(() => {
    const handleKeyDown = (event) => {
      if (event.key === 'Escape' && !isSubmitting) onClose()
      if (event.key !== 'Tab') return
      const focusable = Array.from(dialogRef.current?.querySelectorAll(
        'button:not(:disabled), input:not(:disabled), select:not(:disabled), textarea:not(:disabled)',
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
    if (state.type === 'error') setState({ type: 'idle', message: '' })
  }

  async function submit(event) {
    event.preventDefault()
    const error = validate(form)
    if (error) {
      setState({ type: 'error', message: error })
      return
    }

    setState({ type: 'submitting', message: '' })
    try {
      const ticket = await createTicket({
        category: form.category,
        subject: form.subject.trim(),
        message: form.message.trim(),
      })
      onCreated(ticket)
      setForm(initialForm)
      setState({ type: 'success', message: 'Your support request has been created.' })
    } catch (error) {
      setState({ type: 'error', message: error?.message || 'Your support request could not be submitted.' })
    }
  }

  return <div className="profile-dialog-backdrop" onMouseDown={(event) => {
    if (event.target === event.currentTarget && !isSubmitting) onClose()
  }}>
    <section ref={dialogRef} className="profile-dialog" role="dialog" aria-modal="true" aria-labelledby="support-ticket-title" aria-describedby="support-ticket-description">
      <header className="profile-dialog__header">
        <div><p>Account support</p><h2 id="support-ticket-title">Contact support</h2></div>
        <button type="button" className="profile-dialog__close" aria-label="Close contact support dialog" disabled={isSubmitting} onClick={onClose}><Icon name="close" /></button>
      </header>
      {state.type === 'success' ? <div className="profile-dialog__success" role="status">
        <span aria-hidden="true">✓</span>
        <h3>Request submitted</h3>
        <p>{state.message}</p>
        <button className="shared-button" type="button" onClick={onClose}>Done</button>
      </div> : <form className="support-ticket-form" onSubmit={submit} noValidate>
        <p id="support-ticket-description">Tell us what you need help with. Your request will appear in the list below.</p>
        <label htmlFor="supportCategory">Category</label>
        <select ref={categoryRef} id="supportCategory" value={form.category} disabled={isSubmitting} required onChange={update('category')}>
          <option value="">Select a category</option>
          {SUPPORT_CATEGORIES.map(({ value, label }) => <option key={value} value={value}>{label}</option>)}
        </select>
        <label htmlFor="supportSubject">Subject</label>
        <input id="supportSubject" value={form.subject} maxLength="200" disabled={isSubmitting} required onChange={update('subject')} />
        <label htmlFor="supportMessage">Message</label>
        <textarea id="supportMessage" value={form.message} maxLength="4000" rows="6" disabled={isSubmitting} required onChange={update('message')} />
        {state.type === 'error' && <div className="support-ticket-error" role="alert">{state.message}</div>}
        <div className="profile-dialog__actions">
          <button className="shared-button shared-button--outline" type="button" disabled={isSubmitting} onClick={onClose}>Cancel</button>
          <button className="shared-button" type="submit" disabled={isSubmitting}>{isSubmitting ? 'Submitting…' : 'Submit request'}</button>
        </div>
      </form>}
    </section>
  </div>
}
