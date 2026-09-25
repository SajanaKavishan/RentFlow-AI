import { useEffect, useRef, useState } from 'react'
import { createSupportTicket, getMySupportTickets, SUPPORT_CATEGORIES } from '../../features/supportTickets/supportTicketsApi.js'
import Icon from '../ui/Icons.jsx'
import SupportTicketDialog from './SupportTicketDialog.jsx'

const categoryLabels = Object.fromEntries(SUPPORT_CATEGORIES.map(({ value, label }) => [value, label]))

function formatCreatedAt(value) {
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(value))
}

export default function SupportRequestsSection() {
  const [tickets, setTickets] = useState([])
  const [loadState, setLoadState] = useState({ type: 'loading', message: '' })
  const [loadAttempt, setLoadAttempt] = useState(0)
  const [dialogOpen, setDialogOpen] = useState(false)
  const contactButtonRef = useRef(null)

  useEffect(() => {
    let active = true
    getMySupportTickets().then((response) => {
      if (!active) return
      setTickets((current) => {
        const loadedIds = new Set(response.map(({ id }) => id))
        return [...current.filter(({ id }) => !loadedIds.has(id)), ...response]
      })
      setLoadState({ type: 'ready', message: '' })
    }).catch((error) => {
      if (!active) return
      setLoadState({ type: 'error', message: error?.message || 'Your support requests could not be loaded.' })
    })
    return () => { active = false }
  }, [loadAttempt])

  const closeDialog = () => {
    setDialogOpen(false)
    window.requestAnimationFrame(() => contactButtonRef.current?.focus())
  }

  return <>
    <button ref={contactButtonRef} className="profile-action profile-action--available" type="button" onClick={() => setDialogOpen(true)}>
      <span className="profile-action__icon"><Icon name="info" size={20} /></span>
      <span className="profile-action__copy"><strong>Contact support</strong><small>Create a support request and track its status.</small></span>
      <Icon name="arrow" size={18} />
    </button>
    <div className="support-requests" aria-labelledby="support-requests-title">
      <div className="support-requests__header"><h3 id="support-requests-title">My support requests</h3></div>
      {loadState.type === 'loading' && <p className="support-requests__state" aria-live="polite">Loading support requests…</p>}
      {loadState.type === 'error' && <div className="support-requests__state" role="alert"><p>{loadState.message}</p><button className="shared-button shared-button--outline" type="button" onClick={() => {
        setLoadState({ type: 'loading', message: '' })
        setLoadAttempt((current) => current + 1)
      }}>Retry</button></div>}
      {loadState.type === 'ready' && tickets.length === 0 && <p className="support-requests__state">No support requests yet.</p>}
      {loadState.type === 'ready' && tickets.length > 0 && <ul className="support-requests__list">
        {tickets.map((ticket) => <li key={ticket.id}>
          <div><strong>{ticket.subject}</strong><span>{categoryLabels[ticket.category] || ticket.category} · {formatCreatedAt(ticket.createdAt)}</span></div>
          <span className="support-requests__status">{ticket.status}</span>
        </li>)}
      </ul>}
    </div>
    {dialogOpen && <SupportTicketDialog
      createTicket={createSupportTicket}
      onClose={closeDialog}
      onCreated={(ticket) => {
        setTickets((current) => [ticket, ...current.filter(({ id }) => id !== ticket.id)])
        setLoadState({ type: 'ready', message: '' })
      }}
    />}
  </>
}
