import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import PropertySelectionState from '../../../shared/property/PropertySelectionState.jsx'
import usePropertyContext from '../../../shared/property/usePropertyContext.js'
import { useOwnedPropertySelection } from '../../../shared/property/useOwnedProperties.js'
import Icon from '../../../shared/ui/Icons.jsx'
import ApplicationDecisionSection from '../components/ApplicationDecisionSection.jsx'
import ApplicationValidationSection from '../components/ApplicationValidationSection.jsx'
import RentalApplicationStatusBadge from '../components/RentalApplicationStatusBadge.jsx'
import {
  approveApplication,
  getApplicationById,
  rejectApplication,
  RENTAL_APPLICATION_STATUS,
  RentalApplicationApiError,
  requestChanges,
} from '../services/rentalApplicationApiService.js'
import '../rentalApplications.css'
import './rental-application-management.css'
import './application-validation-report.css'

const dateTimeFormatter = new Intl.DateTimeFormat(undefined, {
  dateStyle: 'medium',
  timeStyle: 'short',
})

function formatDateTime(value) {
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? 'Unavailable' : dateTimeFormatter.format(date)
}

function safeErrorMessage(error, fallback) {
  return error instanceof RentalApplicationApiError ? error.message : fallback
}

function validApplication(application, applicationId, propertyId) {
  return application && typeof application.id === 'string'
    && application.id.toLowerCase() === applicationId.toLowerCase()
    && typeof application.propertyId === 'string'
    && application.propertyId.toLowerCase() === propertyId.toLowerCase()
    && typeof application.tenantId === 'string'
    && Number.isInteger(application.status)
}

export default function ApplicationValidationReportPage() {
  const { applicationId } = useParams()
  const { propertyId } = usePropertyContext()
  const selection = useOwnedPropertySelection(propertyId)
  const [state, setState] = useState({
    status: 'loading', propertyId: null, applicationId: null, application: null, error: '',
  })
  const [isUpdating, setIsUpdating] = useState(false)
  const [actionError, setActionError] = useState('')
  const [notice, setNotice] = useState('')
  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => {
    if (!propertyId || !applicationId || selection.status !== 'selected') return undefined
    let active = true
    getApplicationById(applicationId)
      .then((application) => {
        if (!active) return
        if (!validApplication(application, applicationId, propertyId)) {
          throw new TypeError('Invalid application response')
        }
        setState({ status: 'success', propertyId, applicationId, application, error: '' })
      })
      .catch((error) => {
        if (active) setState({
          status: 'error',
          propertyId,
          applicationId,
          application: null,
          error: safeErrorMessage(error, 'Unable to load this application. Please try again.'),
        })
      })
    return () => { active = false }
  }, [applicationId, propertyId, reloadKey, selection.status])

  async function updateApplication(operation, successMessage) {
    if (isUpdating) return false
    setIsUpdating(true)
    setActionError('')
    setNotice('')
    try {
      const application = await operation()
      if (!validApplication(application, applicationId, propertyId)) {
        throw new TypeError('Invalid application response')
      }
      setState({ status: 'success', propertyId, applicationId, application, error: '' })
      setNotice(successMessage)
      return true
    } catch (error) {
      setActionError(safeErrorMessage(error, 'Unable to update this rental application. Please try again.'))
      return false
    } finally {
      setIsUpdating(false)
    }
  }

  const pageStatus = state.propertyId === propertyId && state.applicationId === applicationId
    ? state.status : 'loading'
  const application = pageStatus === 'success' ? state.application : null
  const canAct = application && [
    RENTAL_APPLICATION_STATUS.SUBMITTED,
    RENTAL_APPLICATION_STATUS.UNDER_REVIEW,
  ].includes(application.status)
  const applicationsPath = propertyId
    ? `/properties/${encodeURIComponent(propertyId)}/rental-applications`
    : '/rental-applications'

  if (selection.status !== 'selected') {
    return <main className="applications-page"><PropertySelectionState className="applications-state" destination="rental-applications"
      selectedPropertyId={selection.status === 'unauthorized' ? propertyId : null} /></main>
  }

  if (pageStatus === 'loading') {
    return <main className="validation-report-page" aria-busy="true">
      <section className="applications-state" aria-live="polite">
        <span className="applications-spinner" aria-hidden="true" />
        <h2>Loading validation report</h2>
        <p>Please wait while we fetch the authorized application.</p>
      </section>
    </main>
  }

  if (pageStatus === 'error') {
    return <main className="validation-report-page">
      <Link className="validation-report-page__back" to={applicationsPath}><Icon name="arrowLeft" size={17} />Back to Applications</Link>
      <section className="applications-state applications-state--error" role="alert">
        <div className="applications-state__icon" aria-hidden="true">!</div>
        <h2>We could not load the validation report</h2>
        <p>{state.error}</p>
        <button type="button" className="application-button application-button--primary"
          onClick={() => {
            setState({ status: 'loading', propertyId, applicationId, application: null, error: '' })
            setReloadKey((value) => value + 1)
          }}>Try again</button>
      </section>
    </main>
  }

  return <main className="validation-report-page">
    <Link className="validation-report-page__back" to={applicationsPath}><Icon name="arrowLeft" size={17} />Back to Applications</Link>

    <header className="validation-report-page__header">
      <div>
        <p className="validation-report-page__eyebrow">Application review</p>
        <h1>AI Validation Report</h1>
        <p>Application <code>{application.id}</code></p>
      </div>
      <RentalApplicationStatusBadge status={application.status} />
    </header>

    <dl className="validation-report-page__references">
      <div><dt>Property</dt><dd>{selection.property
        ? <><strong>{selection.property.title}</strong><span>{[selection.property.address, selection.property.city].filter(Boolean).join(', ')}</span></>
        : <code>{application.propertyId}</code>}</dd></div>
      <div><dt>Tenant reference</dt><dd><code>{application.tenantId}</code></dd></div>
      <div><dt>Submitted</dt><dd>{application.submittedAt ? formatDateTime(application.submittedAt) : 'Not submitted'}</dd></div>
      <div><dt>Last updated</dt><dd>{formatDateTime(application.updatedAt || application.createdAt)}</dd></div>
    </dl>

    {notice && <p className="applications-notice" role="status">{notice}</p>}

    <ApplicationValidationSection key={application.updatedAt || application.createdAt}
      applicationId={application.id}
      applicationUpdatedAt={application.updatedAt || application.submittedAt || application.createdAt}
      canRun={canAct} />

    <aside className="validation-report-page__advisory">
      <Icon name="shield" size={20} />
      <p><strong>AI findings are advisory.</strong> They support the review process and do not approve or reject an application. Final rental decisions remain human-controlled.</p>
    </aside>

    {canAct && <ApplicationDecisionSection application={application} isUpdating={isUpdating}
      actionError={actionError}
      onApprove={(id, response) => updateApplication(() => approveApplication(id, response), 'Application approved.')}
      onReject={(id, reason) => updateApplication(() => rejectApplication(id, reason), 'Application rejected.')}
      onRequestChanges={(id, message) => updateApplication(() => requestChanges(id, message), 'More information requested from the tenant.')} />}
  </main>
}
