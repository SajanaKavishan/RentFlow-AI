import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../../auth/useAuth.js'
import { AppCard, PageHeader } from '../../../shared/ui/States.jsx'
import Icon from '../../../shared/ui/Icons.jsx'
import RentalApplicationStatusBadge from '../components/RentalApplicationStatusBadge.jsx'
import { APPLICATION_STATUS_DETAILS } from '../components/applicationStatus.js'
import {
  getMyApplications,
  RENTAL_APPLICATION_STATUS,
  RentalApplicationApiError,
} from '../services/rentalApplicationApiService.js'
import '../rentalApplications.css'
import './my-applications.css'

const statusOptions = [['All statuses', 'all'],
  ...Object.entries(APPLICATION_STATUS_DETAILS).map(([status, details]) => [details.label, status])]
const dateFormatter = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' })

function validDate(value) {
  return typeof value === 'string' && Number.isFinite(Date.parse(value))
}

function validateApplications(applications, tenantId) {
  if (!Array.isArray(applications) || applications.some((item) =>
    !item || typeof item.id !== 'string' || !item.id.trim()
    || typeof item.propertyId !== 'string' || !item.propertyId.trim()
    || typeof item.tenantId !== 'string' || item.tenantId.toLowerCase() !== tenantId.toLowerCase()
    || !Object.values(RENTAL_APPLICATION_STATUS).includes(item.status)
    || !validDate(item.createdAt)
    || (item.submittedAt != null && !validDate(item.submittedAt))
    || (item.landlordResponse != null && typeof item.landlordResponse !== 'string')
  )) throw new TypeError('Invalid tenant application response')
  return [...applications].sort((a, b) =>
    Date.parse(b.submittedAt || b.createdAt) - Date.parse(a.submittedAt || a.createdAt))
}

export default function MyApplicationsPage() {
  const { user } = useAuth()
  const [attempt, setAttempt] = useState(0)
  const [filter, setFilter] = useState('all')
  const [state, setState] = useState({ status: 'loading', applications: [], error: '' })

  useEffect(() => {
    let active = true
    getMyApplications().then((applications) => {
      if (active) setState({ status: 'ready', applications: validateApplications(applications, user.id), error: '' })
    }).catch((error) => {
      if (active) setState({ status: 'error', applications: [], error: error instanceof RentalApplicationApiError
        ? error.message : 'Your applications could not be loaded. Please try again.' })
    })
    return () => { active = false }
  }, [attempt, user.id])

  function reload() {
    setState({ status: 'loading', applications: [], error: '' })
    setAttempt((value) => value + 1)
  }

  const visibleApplications = filter === 'all' ? state.applications
    : state.applications.filter((item) => item.status === Number(filter))

  return <main className="shared-page my-applications-page" aria-busy={state.status === 'loading'}>
    <div className="my-applications-page__heading">
      <PageHeader eyebrow="Your rental journey" title="My Applications">
        <p>Track your applications and landlord feedback. Use the mobile app to create or update an application.</p>
      </PageHeader>
      <button className="shared-button shared-button--outline" type="button" onClick={reload} disabled={state.status === 'loading'}><Icon name="refresh" size={18} />Refresh</button>
    </div>

    {state.status === 'loading' && <div className="my-applications-state" role="status"><span className="shared-spinner" aria-hidden="true" />Loading your applications&hellip;</div>}
    {state.status === 'error' && <div className="my-applications-state" role="alert"><h2>Applications could not be loaded</h2><p>{state.error}</p><button className="shared-button" type="button" onClick={reload}>Try again</button></div>}
    {state.status === 'ready' && <>
      {state.applications.length === 0
        ? <AppCard className="my-applications-state"><Icon name="document" size={28} /><h2>No applications yet</h2><p>Applications you create in the mobile app will appear here.</p></AppCard>
        : <>
          <div className="my-applications-toolbar">
            <label htmlFor="application-status-filter">Status</label>
            <select id="application-status-filter" value={filter} onChange={(event) => setFilter(event.target.value)}>
              {statusOptions.map(([label, value]) => <option key={value} value={value}>{label}</option>)}
            </select>
            <span role="status">{visibleApplications.length} {visibleApplications.length === 1 ? 'application' : 'applications'}</span>
          </div>
          {visibleApplications.length === 0
            ? <AppCard className="my-applications-state"><Icon name="search" size={28} /><h2>No applications with this status</h2><p>Choose another status to see your applications.</p></AppCard>
            : <section className="my-applications-list" aria-label="Your rental applications">
              {visibleApplications.map((application) => <AppCard key={application.id} className="my-application-card">
                <div className="my-application-card__top"><div><p className="my-application-card__eyebrow">Property reference</p><h2><code>{application.propertyId}</code></h2></div><RentalApplicationStatusBadge status={application.status} /></div>
                <dl className="my-application-card__details">
                  <div><dt>Submitted</dt><dd>{application.submittedAt
                    ? <time dateTime={application.submittedAt}>{dateFormatter.format(new Date(application.submittedAt))}</time>
                    : 'Not submitted'}</dd></div>
                </dl>
                {application.landlordResponse?.trim() && <div className="my-application-card__response"><h3>Landlord feedback</h3><p>{application.landlordResponse}</p></div>}
                <Link className="shared-button shared-button--outline my-application-card__link" to={`/notifications/rental-application/${encodeURIComponent(application.id)}`}>View application <Icon name="arrow" size={18} /></Link>
              </AppCard>)}
            </section>}
        </>}
    </>}
  </main>
}
