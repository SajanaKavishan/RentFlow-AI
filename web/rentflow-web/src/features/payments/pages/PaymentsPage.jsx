import { useEffect, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useLandlordActions } from '../../../shared/layout/LandlordActionsContext.js'
import { ApiError } from '../../../core/api/apiClient.js'
import { AppCard, PageHeader, StatusBadge } from '../../../shared/ui/States.jsx'
import { changePaymentStatus, getLandlordPayments, getPayment } from '../services/paymentApiService.js'
import '../payments.css'

const statuses = ['Pending', 'Completed', 'Failed']
const missing = '—'

function safeError(error, fallback) {
  if (!(error instanceof ApiError)) return fallback
  if (error.statusCode === 401) return 'Your session has expired. Please sign in again.'
  if (error.statusCode === 403) return 'You do not have permission to access this resource.'
  if (error.statusCode === 404) return 'This payment could not be found.'
  if (error.statusCode === 409) return 'This payment can no longer be updated. Refresh and try again.'
  if (error.statusCode === 400) return error.message
  return fallback
}

function amount(value) {
  return value == null || !Number.isFinite(Number(value))
    ? missing
    : new Intl.NumberFormat(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(value)
}

function dateTime(value) {
  if (!value) return missing
  const parsed = new Date(value)
  return Number.isNaN(parsed.getTime()) ? missing : parsed.toLocaleString()
}

function statusLabel(status) { return statuses[status] ?? 'Unknown' }

function PaymentDetails({ payment, acting, actionError, onAction }) {
  return <AppCard className="payments-details">
    <div className="payments-heading"><h2>Payment details</h2><StatusBadge tone={payment.status === 1 ? 'success' : payment.status === 2 ? 'warning' : 'progress'}>{statusLabel(payment.status)}</StatusBadge></div>
    <dl className="payments-facts">
      <div><dt>Payment ID</dt><dd>{payment.id}</dd></div>
      <div><dt>Schedule item ID</dt><dd>{payment.rentScheduleItemId}</dd></div>
      <div><dt>Tenant ID</dt><dd>{payment.tenantId}</dd></div>
      <div><dt>Amount</dt><dd>{amount(payment.amount)}</dd></div>
      <div><dt>Payment method</dt><dd>{payment.paymentMethod || missing}</dd></div>
      <div><dt>Transaction reference</dt><dd>{payment.transactionReference || missing}</dd></div>
      <div><dt>Paid at</dt><dd>{dateTime(payment.paidAt)}</dd></div>
      <div><dt>Created</dt><dd>{dateTime(payment.createdAt)}</dd></div>
      <div><dt>Updated</dt><dd>{dateTime(payment.updatedAt)}</dd></div>
    </dl>
    {payment.status === 0 && payment.provider !== 1 && <div className="payments-actions">
      <button className="shared-button" type="button" disabled={Boolean(acting)} onClick={() => onAction('complete')}>{acting === 'complete' ? 'Completing…' : 'Complete payment'}</button>
      <button className="shared-button shared-button--outline shared-button--danger" type="button" disabled={Boolean(acting)} onClick={() => onAction('fail')}>{acting === 'fail' ? 'Failing…' : 'Mark as failed'}</button>
    </div>}
    {actionError && <p className="shared-notice shared-notice--error" role="alert">{actionError}</p>}
  </AppCard>
}

export default function PaymentsPage() {
  const actionSummary = useLandlordActions()
  const [searchParams] = useSearchParams()
  const requestedPaymentId = searchParams.get('paymentId')
  const [listState, setListState] = useState({ status: 'loading', items: [], error: '' })
  const [listReload, setListReload] = useState(0)
  const [detailState, setDetailState] = useState({ status: 'idle', payment: null, error: '' })
  const [acting, setActing] = useState('')
  const [actionError, setActionError] = useState('')
  const [notice, setNotice] = useState('')
  const detailRequest = useRef(0)
  const actionInFlight = useRef(false)

  useEffect(() => {
    if (!requestedPaymentId) return undefined
    let active = true
    const request = ++detailRequest.current
    getPayment(requestedPaymentId).then((payment) => {
      if (active && request === detailRequest.current) setDetailState({ status: 'ready', payment, error: '' })
    }).catch((error) => {
      if (active && request === detailRequest.current) setDetailState({ status: 'error', payment: null, error: safeError(error, 'Unable to load payment details.') })
    })
    return () => { active = false }
  }, [requestedPaymentId])

  useEffect(() => {
    let active = true
    getLandlordPayments().then((items) => {
      if (active) setListState({ status: 'ready', items, error: '' })
    }).catch((error) => {
      if (active) setListState({ status: 'error', items: [], error: safeError(error, 'Unable to load payments.') })
    })
    return () => { active = false }
  }, [listReload])

  function refreshList() {
    actionSummary?.refresh()
    setListState((current) => ({ ...current, status: 'loading' }))
    setListReload((value) => value + 1)
  }

  async function openPayment(id) {
    if (actionInFlight.current) return
    const request = ++detailRequest.current
    setDetailState({ status: 'loading', payment: null, error: '' })
    setActionError('')
    setNotice('')
    try {
      const payment = await getPayment(id)
      if (request === detailRequest.current) setDetailState({ status: 'ready', payment, error: '' })
    } catch (error) {
      if (request === detailRequest.current) setDetailState({ status: 'error', payment: null, error: safeError(error, 'Unable to load payment details.') })
    }
  }

  async function changeStatus(action) {
    const payment = detailState.payment
    if (actionInFlight.current || detailState.status !== 'ready' || payment.status !== 0 || payment.provider === 1 || !['complete', 'fail'].includes(action)) return
    actionInFlight.current = true
    setActing(action)
    setActionError('')
    setNotice('')
    let updated
    try {
      updated = await changePaymentStatus(payment.id, action)
    } catch (error) {
      setActionError(safeError(error, 'Unable to update the payment.'))
      setActing('')
      actionInFlight.current = false
      return
    }

    setNotice(action === 'complete' ? 'Payment completed successfully.' : 'Payment marked as failed.')
    refreshList()
    setDetailState({ status: 'loading', payment: null, error: '' })
    try {
      const refreshed = await getPayment(payment.id)
      setDetailState({ status: 'ready', payment: refreshed, error: '' })
    } catch {
      setDetailState({ status: 'ready', payment: updated, error: '' })
      setActionError('Payment updated, but its details could not be refreshed. Try again later.')
    } finally {
      setActing('')
      actionInFlight.current = false
    }
  }

  return <main className="shared-page payments-page">
    <PageHeader eyebrow="Rental management" title="Payments"><p>Review payments recorded for your rentals and resolve pending payments.</p></PageHeader>
    {notice && <p className="shared-notice" role="status">{notice}</p>}
    <AppCard>
      <div className="payments-heading"><h2>Payment history</h2></div>
      {listState.status === 'loading' && <p role="status">Loading payments…</p>}
      {listState.status === 'error' && <div role="alert"><p>{listState.error}</p><button className="shared-button shared-button--outline" type="button" onClick={refreshList}>Try again</button></div>}
      {listState.status === 'ready' && (listState.items.length === 0 ? <p>No payments have been recorded for your rentals.</p> : <div className="payments-table-wrap"><table className="payments-table"><thead><tr><th scope="col">Created</th><th scope="col">Tenant ID</th><th scope="col">Amount</th><th scope="col">Method</th><th scope="col">Status</th><th scope="col">Details</th></tr></thead><tbody>{listState.items.map((payment) => <tr key={payment.id}><td>{dateTime(payment.createdAt)}</td><td>{payment.tenantId}</td><td>{amount(payment.amount)}</td><td>{payment.paymentMethod || missing}</td><td><StatusBadge tone={payment.status === 1 ? 'success' : payment.status === 2 ? 'warning' : 'progress'}>{statusLabel(payment.status)}</StatusBadge></td><td><button className="shared-button shared-button--outline" type="button" disabled={Boolean(acting)} onClick={() => openPayment(payment.id)}>View details</button></td></tr>)}</tbody></table></div>)}
    </AppCard>
    {detailState.status === 'loading' && <AppCard><p role="status">Loading payment details…</p></AppCard>}
    {detailState.status === 'error' && <AppCard><p role="alert">{detailState.error}</p></AppCard>}
    {detailState.status === 'ready' && <PaymentDetails payment={detailState.payment} acting={acting} actionError={actionError} onAction={changeStatus} />}
  </main>
}
