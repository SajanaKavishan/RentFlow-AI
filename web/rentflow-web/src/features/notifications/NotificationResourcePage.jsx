import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useAuth } from '../auth/useAuth.js'
import { USER_ROLES } from '../auth/authModel.js'
import RentalApplicationCard from '../rentalApplications/components/RentalApplicationCard.jsx'
import RentalApplicationStatusBadge from '../rentalApplications/components/RentalApplicationStatusBadge.jsx'
import {
  approveApplication, getApplicationById, markUnderReview, rejectApplication, requestChanges,
} from '../rentalApplications/services/rentalApplicationApiService.js'
import ViewingCard from '../viewings/components/ViewingCard.jsx'
import { approveViewing, getViewingById, rejectViewing } from '../viewings/services/viewingApiService.js'
import { AppCard, PageHeader } from '../../shared/ui/States.jsx'
import { notificationNavigationError } from './notificationNavigation.js'
import '../rentalApplications/rentalApplications.css'
import '../viewings/viewings.css'
import './notifications.css'

function TenantApplicationDetail({ application }) {
  return <AppCard className="notification-resource__card">
    <RentalApplicationStatusBadge status={application.status} />
    <dl className="notification-resource__details">
      <div><dt>Move in date</dt><dd>{application.moveInDate || 'Unavailable'}</dd></div>
      <div><dt>Occupation</dt><dd>{application.occupation || 'Unavailable'}</dd></div>
      <div><dt>Number of occupants</dt><dd>{application.numberOfOccupants ?? 'Unavailable'}</dd></div>
      <div><dt>Monthly income</dt><dd>{application.monthlyIncome ?? 'Unavailable'}</dd></div>
      <div><dt>Your note</dt><dd>{application.tenantNote || 'None provided'}</dd></div>
      <div><dt>Landlord response</dt><dd>{application.landlordResponse || 'No response yet'}</dd></div>
    </dl>
  </AppCard>
}

export default function NotificationResourcePage({ resourceType }) {
  const { id } = useParams()
  const { user } = useAuth()
  const [reload, setReload] = useState(0)
  const [state, setState] = useState({ status: 'loading', resource: null, error: '' })
  const [updating, setUpdating] = useState(false)
  const [actionError, setActionError] = useState('')
  const [notice, setNotice] = useState('')
  const isApplication = resourceType === 'RentalApplication'

  useEffect(() => {
    let active = true
    const load = isApplication ? getApplicationById : getViewingById
    load(id).then((resource) => {
      if (!active) return
      if (!resource || typeof resource.id !== 'string' || resource.id.toLowerCase() !== id.toLowerCase()) {
        setState({ status: 'error', resource: null, error: 'The related record could not be verified.' })
        return
      }
      setState({ status: 'ready', resource, error: '' })
    }).catch((error) => {
      if (active) setState({ status: 'error', resource: null, error: notificationNavigationError(error) })
    })
    return () => { active = false }
  }, [id, isApplication, reload])

  function retry() {
    setState({ status: 'loading', resource: null, error: '' })
    setReload((value) => value + 1)
  }

  async function act(operation, successMessage) {
    if (updating) return false
    setUpdating(true)
    setActionError('')
    setNotice('')
    try {
      const resource = await operation()
      if (!resource || resource.id?.toLowerCase() !== id.toLowerCase()) {
        throw new Error('Invalid resource response')
      }
      setState({ status: 'ready', resource, error: '' })
      setNotice(successMessage)
      return true
    } catch (error) {
      setActionError(notificationNavigationError(error))
      return false
    } finally {
      setUpdating(false)
    }
  }

  return <main className="shared-page notification-resource">
    <PageHeader eyebrow="Notification detail" title={isApplication ? 'Rental application' : 'Viewing request'}>
      <p>Review the related record for your account.</p>
    </PageHeader>
    <Link className="shared-button shared-button--outline notification-resource__back" to="/notifications">Back to notifications</Link>
    {state.status === 'loading' && <div className="notifications-feedback" role="status"><span className="shared-spinner" aria-hidden="true" />Loading related record&hellip;</div>}
    {state.status === 'error' && <div className="notifications-feedback" role="alert"><strong>Related record unavailable</strong><p>{state.error}</p><button className="shared-button" type="button" onClick={retry}>Try again</button></div>}
    {state.status === 'ready' && <>
      {notice && <p role="status" className="shared-notice">{notice}</p>}
      {isApplication && user.role === USER_ROLES.TENANT && <TenantApplicationDetail application={state.resource} />}
      {isApplication && user.role === USER_ROLES.LANDLORD && <RentalApplicationCard
        application={state.resource} isUpdating={updating} actionError={actionError}
        onReview={(resourceId) => act(() => markUnderReview(resourceId), 'Application marked as under review.')}
        onApprove={(resourceId, response) => act(() => approveApplication(resourceId, response), 'Application approved.')}
        onReject={(resourceId, reason) => act(() => rejectApplication(resourceId, reason), 'Application rejected.')}
        onRequestChanges={(resourceId, message) => act(() => requestChanges(resourceId, message), 'Changes requested from the tenant.')}
      />}
      {!isApplication && user.role === USER_ROLES.LANDLORD && <ViewingCard
        viewing={state.resource} isUpdating={updating} actionError={actionError}
        onApprove={(resourceId, response) => act(() => approveViewing(resourceId, response), 'Viewing request approved.')}
        onReject={(resourceId, reason) => act(() => rejectViewing(resourceId, reason), 'Viewing request rejected.')}
      />}
    </>}
  </main>
}
