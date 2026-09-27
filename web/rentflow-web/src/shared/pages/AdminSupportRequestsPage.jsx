import { useCallback, useEffect, useRef, useState } from 'react'
import {
  ADMIN_SUPPORT_PAGE_SIZE,
  getAdminSupportTicket,
  getAdminSupportTickets,
  SUPPORT_TICKET_CATEGORIES,
  updateAdminSupportTicketStatus,
} from '../../features/adminSupportTickets/adminSupportTicketsApi.js'
import { ApiError } from '../../core/api/apiClient.js'
import { StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import './admin-support-requests.css'

const statusFilters = [
  ['', 'All'],
  ['Open', 'Open'],
  ['InProgress', 'In Progress'],
  ['Resolved', 'Resolved'],
]
const categoryLabels = {
  TechnicalIssue: 'Technical issue',
  AccountLogin: 'Account or login',
  PropertyApplication: 'Property or application',
  Payment: 'Payment',
  Other: 'Other',
}

function statusLabel(status) {
  return status === 'InProgress' ? 'In Progress' : status
}

function statusTone(status) {
  if (status === 'Resolved') return 'success'
  if (status === 'InProgress') return 'warning'
  return 'neutral'
}

function createdDate(value) {
  return new Intl.DateTimeFormat('en-US', {
    year: 'numeric', month: 'short', day: 'numeric',
  }).format(new Date(value))
}

function errorMessage(error, fallback) {
  if (error instanceof ApiError && error.statusCode === 401) return 'Your Admin session is no longer valid. Sign in again.'
  if (error instanceof ApiError && error.statusCode === 403) return 'Your account is no longer authorized to manage support requests.'
  return error?.message || fallback
}

function transitionButtons(status) {
  if (status === 'Open') return [
    ['InProgress', 'Mark In Progress'],
    ['Resolved', 'Resolve'],
  ]
  if (status === 'InProgress') return [['Resolved', 'Resolve']]
  return []
}

export default function AdminSupportRequestsPage() {
  const [filters, setFilters] = useState({ status: '', category: '', search: '' })
  const [searchDraft, setSearchDraft] = useState('')
  const [page, setPage] = useState(1)
  const [refresh, setRefresh] = useState(0)
  const [listState, setListState] = useState({ requestKey: '', status: 'loading', data: null, error: '' })
  const [detailState, setDetailState] = useState(null)
  const [updating, setUpdating] = useState(null)
  const [actionError, setActionError] = useState(null)
  const [actionNotice, setActionNotice] = useState('')
  const listRequest = useRef(0)
  const detailRequest = useRef(0)
  const detailDialogRef = useRef(null)
  const closeDetailRef = useRef(null)
  const viewButtonRef = useRef(null)

  const requestKey = JSON.stringify([page, filters.status, filters.category, filters.search, refresh])
  const visibleList = listState.requestKey === requestKey
    ? listState
    : { status: 'loading', data: null, error: '' }

  useEffect(() => {
    const request = ++listRequest.current
    const requestCounter = listRequest
    const controller = new AbortController()
    getAdminSupportTickets({
      page,
      pageSize: ADMIN_SUPPORT_PAGE_SIZE,
      status: filters.status,
      category: filters.category,
      search: filters.search,
      signal: controller.signal,
    }).then((data) => {
      if (request === listRequest.current) {
        setListState({ requestKey, status: 'ready', data, error: '' })
      }
    }).catch((error) => {
      if (request === listRequest.current && error?.name !== 'AbortError') {
        setListState({
          requestKey,
          status: 'error',
          data: null,
          error: errorMessage(error, 'Support requests could not be loaded.'),
        })
      }
    })
    return () => {
      controller.abort()
      if (request === requestCounter.current) requestCounter.current++
    }
  }, [page, filters, refresh, requestKey])

  const closeDetail = useCallback(() => {
    detailRequest.current++
    setDetailState(null)
    window.requestAnimationFrame(() => viewButtonRef.current?.focus())
  }, [])

  useEffect(() => {
    if (!detailState) return undefined
    const onKeyDown = (event) => {
      if (event.key === 'Escape' && !updating) closeDetail()
      if (event.key !== 'Tab') return
      const focusable = Array.from(detailDialogRef.current?.querySelectorAll('button:not(:disabled)') || [])
      if (!focusable.length) return
      const first = focusable[0]
      const last = focusable[focusable.length - 1]
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus() }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus() }
    }
    document.addEventListener('keydown', onKeyDown)
    return () => document.removeEventListener('keydown', onKeyDown)
  }, [detailState, updating, closeDetail])

  function updateFilter(name, value) {
    setPage(1)
    setActionError(null)
    setFilters((current) => ({ ...current, [name]: value }))
  }

  function submitSearch(event) {
    event.preventDefault()
    updateFilter('search', searchDraft.trim())
  }

  function openDetail(ticketId, trigger) {
    viewButtonRef.current = trigger
    loadDetail(ticketId)
  }

  function loadDetail(ticketId) {
    const request = ++detailRequest.current
    setDetailState({ id: ticketId, status: 'loading', ticket: null, error: '' })
    getAdminSupportTicket(ticketId).then((ticket) => {
      if (request === detailRequest.current) {
        setDetailState({ id: ticketId, status: 'ready', ticket, error: '' })
        window.requestAnimationFrame(() => closeDetailRef.current?.focus())
      }
    }).catch((error) => {
      if (request === detailRequest.current) setDetailState({
        id: ticketId,
        status: 'error',
        ticket: null,
        error: errorMessage(error, 'The support request could not be loaded.'),
      })
    })
  }

  async function updateStatus(ticketId, nextStatus) {
    setUpdating({ ticketId, nextStatus })
    setActionError(null)
    setActionNotice('')
    try {
      const confirmed = await updateAdminSupportTicketStatus(ticketId, nextStatus)
      setListState((current) => current.data ? {
        ...current,
        data: {
          ...current.data,
          items: current.data.items.map((ticket) => ticket.id === confirmed.id
            ? { ...ticket, status: confirmed.status }
            : ticket),
        },
      } : current)
      setDetailState((current) => current?.ticket?.id === confirmed.id ? {
        ...current,
        ticket: { ...current.ticket, status: confirmed.status, updatedAt: confirmed.updatedAt },
      } : current)
      setActionNotice(`Support request marked ${statusLabel(confirmed.status)}.`)
    } catch (error) {
      setActionError({
        ticketId,
        message: errorMessage(error, 'The support request status could not be updated.'),
      })
    } finally {
      setUpdating(null)
    }
  }

  const detailTicket = detailState?.ticket

  return <main className="shared-page admin-support-page">
    <header className="admin-support-page__header">
      <div><p>Administration</p><h1>Support Requests</h1><span>Review submitted requests and move them through the supported workflow.</span></div>
    </header>

    <section className="shared-card admin-support-directory" aria-labelledby="admin-support-list-title">
      <div className="admin-support-directory__heading">
        <div><h2 id="admin-support-list-title">Submitted requests</h2><p>{visibleList.status === 'ready' ? `${visibleList.data.pagination.totalCount} matching requests` : 'Authorized support queue'}</p></div>
      </div>
      <div className="admin-support-directory__controls">
        <div className="admin-support-status-filters" aria-label="Filter support requests by status">
          {statusFilters.map(([value, label]) => <button key={label} type="button" className={filters.status === value ? 'is-active' : ''} aria-pressed={filters.status === value} onClick={() => updateFilter('status', value)}>{label}</button>)}
        </div>
        <form role="search" aria-label="Search support requests" onSubmit={submitSearch}>
          <label htmlFor="adminSupportSearch">Search</label>
          <input id="adminSupportSearch" type="search" maxLength="320" placeholder="Subject, requester name, or email" value={searchDraft} onChange={(event) => setSearchDraft(event.target.value)} />
          <button className="shared-button shared-button--outline" type="submit">Search</button>
        </form>
        <label className="admin-support-category-filter" htmlFor="adminSupportCategory">Category
          <select id="adminSupportCategory" value={filters.category} onChange={(event) => updateFilter('category', event.target.value)}>
            <option value="">All categories</option>
            {SUPPORT_TICKET_CATEGORIES.map((category) => <option key={category} value={category}>{categoryLabels[category]}</option>)}
          </select>
        </label>
      </div>

      {visibleList.status === 'loading' && <div className="admin-support-state" role="status"><span className="shared-spinner" aria-hidden="true" /><h2>Loading support requests</h2></div>}
      {visibleList.status === 'error' && <div className="admin-support-state" role="alert"><Icon name="alert" size={25} /><h2>Support requests unavailable</h2><p>{visibleList.error}</p><button className="shared-button" type="button" onClick={() => setRefresh((current) => current + 1)}>Try again</button></div>}
      {visibleList.status === 'ready' && visibleList.data.items.length === 0 && <div className="admin-support-state"><Icon name="search" size={25} /><h2>No support requests found</h2><p>Try another filter or search.</p></div>}
      {visibleList.status === 'ready' && visibleList.data.items.length > 0 && <>
        {actionNotice && <p className="admin-support-action-notice" role="status">{actionNotice}</p>}
        <div className="admin-support-table-wrap"><table className="admin-support-table">
          <thead><tr><th>Reference</th><th>Request</th><th>Requester</th><th>Created</th><th>Status</th><th><span className="admin-support-visually-hidden">Actions</span></th></tr></thead>
          <tbody>{visibleList.data.items.map((ticket) => {
            const isUpdating = updating?.ticketId === ticket.id
            return <tr key={ticket.id}>
              <td data-label="Reference"><code>{ticket.id.slice(0, 8)}</code></td>
              <td data-label="Request"><div className="admin-support-request"><strong>{ticket.subject}</strong><span>{categoryLabels[ticket.category]}</span></div></td>
              <td data-label="Requester"><div className="admin-support-requester"><strong>{ticket.requesterFullName}</strong><span>{ticket.requesterEmail}</span></div></td>
              <td data-label="Created">{createdDate(ticket.createdAt)}</td>
              <td data-label="Status"><StatusBadge tone={statusTone(ticket.status)}>{statusLabel(ticket.status)}</StatusBadge></td>
              <td data-label="Actions"><div className="admin-support-actions">
                <button className="shared-button shared-button--outline" type="button" onClick={(event) => openDetail(ticket.id, event.currentTarget)}>View</button>
                {transitionButtons(ticket.status).map(([next, label]) => <button key={next} className="shared-button" type="button" disabled={isUpdating} onClick={() => updateStatus(ticket.id, next)}>{isUpdating && updating.nextStatus === next ? 'Updating…' : label}</button>)}
              </div>{actionError?.ticketId === ticket.id && <p className="admin-support-action-error" role="alert">{actionError.message}</p>}</td>
            </tr>
          })}</tbody>
        </table></div>
        <div className="admin-support-pagination">
          <p>Page {visibleList.data.pagination.page} of {Math.max(visibleList.data.pagination.totalPages, 1)}</p>
          <div><button className="shared-button shared-button--outline" type="button" disabled={!visibleList.data.pagination.hasPreviousPage} onClick={() => setPage((current) => current - 1)}>Previous</button><button className="shared-button shared-button--outline" type="button" disabled={!visibleList.data.pagination.hasNextPage} onClick={() => setPage((current) => current + 1)}>Next</button></div>
        </div>
      </>}
    </section>

    {detailState && <div className="admin-support-dialog-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget && !updating) closeDetail() }}>
      <section ref={detailDialogRef} className="admin-support-dialog" role="dialog" aria-modal="true" aria-labelledby="admin-support-detail-title">
        <header><div><p>Support request</p><h2 id="admin-support-detail-title">{detailTicket?.subject || 'Request details'}</h2></div><button ref={closeDetailRef} type="button" aria-label="Close support request details" disabled={Boolean(updating)} onClick={closeDetail}><Icon name="close" /></button></header>
        {detailState.status === 'loading' && <div className="admin-support-dialog__state" role="status"><span className="shared-spinner" aria-hidden="true" />Loading request details…</div>}
        {detailState.status === 'error' && <div className="admin-support-dialog__state" role="alert"><p>{detailState.error}</p><button className="shared-button" type="button" onClick={() => loadDetail(detailState.id)}>Try again</button></div>}
        {detailTicket && <div className="admin-support-detail">
          <dl><div><dt>Reference</dt><dd><code>{detailTicket.id}</code></dd></div><div><dt>Status</dt><dd><StatusBadge tone={statusTone(detailTicket.status)}>{statusLabel(detailTicket.status)}</StatusBadge></dd></div><div><dt>Category</dt><dd>{categoryLabels[detailTicket.category]}</dd></div><div><dt>Created</dt><dd>{createdDate(detailTicket.createdAt)}</dd></div><div><dt>Requester</dt><dd>{detailTicket.requesterFullName}<span>{detailTicket.requesterEmail}</span></dd></div></dl>
          <section aria-labelledby="admin-support-message-title"><h3 id="admin-support-message-title">Message</h3><p>{detailTicket.message}</p></section>
          {actionError?.ticketId === detailTicket.id && <p className="admin-support-action-error" role="alert">{actionError.message}</p>}
          <div className="admin-support-detail__actions">{transitionButtons(detailTicket.status).map(([next, label]) => <button key={next} className="shared-button" type="button" disabled={Boolean(updating)} onClick={() => updateStatus(detailTicket.id, next)}>{updating?.nextStatus === next ? 'Updating…' : label}</button>)}</div>
        </div>}
      </section>
    </div>}
  </main>
}
