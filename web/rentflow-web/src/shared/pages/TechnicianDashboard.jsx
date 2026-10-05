import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { getTechnicianMaintenanceRequests } from '../../features/maintenance/services/maintenanceApiService.js'
import { MAINTENANCE_CATEGORY, MAINTENANCE_PRIORITY, MAINTENANCE_STATUS, maintenanceEnumLabel } from '../../features/maintenance/services/maintenanceEnums.js'
import { StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import { activeTechnicianWork, technicianSummary } from './technicianWorkPresentation.js'
import './role-dashboard.css'

const statusToneMap = {
  Submitted: 'warning',
  Triaged: 'warning',
  Assigned: 'warning',
  EstimatePending: 'warning',
  EstimateSubmitted: 'warning',
  AwaitingLandlordApproval: 'warning',
  Approved: 'success',
  InProgress: 'neutral',
}

const accessLabel = (value) => ({
  Morning: 'Morning (8-12)',
  Afternoon: 'Afternoon (12-5)',
  Evening: 'Evening (5-8)',
}[value] || null)

export default function TechnicianDashboard({ user }) {
  const [summary, setSummary] = useState(null)
  const [workRequests, setWorkRequests] = useState(null)
  const [workError, setWorkError] = useState('')

  useEffect(() => {
    let active = true
    getTechnicianMaintenanceRequests(user.id)
      .then((requests) => {
        if (active) {
          setSummary(technicianSummary(requests))
          setWorkRequests(requests)
          setWorkError('')
        }
      })
      .catch((error) => {
        if (active) {
          setSummary({})
          setWorkRequests([])
          setWorkError(error.message || 'Unable to load assigned work.')
        }
      })
    return () => { active = false }
  }, [user.id])

  const activeWork = activeTechnicianWork(workRequests || []).slice(0, 3)

  return <main className="shared-page role-dashboard technician-dashboard">
    <header className="role-dashboard__header">
      <div>
        <h1>Welcome, {user.fullName.trim() || 'there'}</h1>
        <p>Use your shared account tools now. Assigned maintenance work is connected to your authenticated technician queue.</p>
      </div>
    </header>

    <section className="technician-summary" aria-label="Work summary">
      <article className="technician-summary__card">
        <strong>{summary?.today ?? '—'}</strong>
        <span>Today's jobs</span>
      </article>
      <article className="technician-summary__card technician-summary__card--progress">
        <strong>{summary?.progress ?? '—'}</strong>
        <span>In progress</span>
      </article>
      <article className="technician-summary__card technician-summary__card--completed">
        <strong>{summary?.completed ?? '—'}</strong>
        <span>Completed this week</span>
      </article>
    </section>

    <div className="technician-dashboard__workspace">
      <section className="shared-card technician-work" aria-labelledby="technician-work-title">
        <div className="role-dashboard__section-title">
          <div><p className="role-dashboard__eyebrow">Technician queue</p><h2 id="technician-work-title">Assigned Work</h2></div>
          <Link className="role-dashboard__text-link" to="/modules/assigned-work">View all <Icon name="arrow" size={16} /></Link>
        </div>
        {workError && <p className="technician-work__error" role="alert">{workError}</p>}
        {workRequests === null && <p className="technician-work__empty">Loading assigned work...</p>}
        {workRequests !== null && !workError && activeWork.length === 0 && (
          <p className="technician-work__empty">No active assigned work.</p>
        )}
        {activeWork.length > 0 && (
          <div className="technician-work__list">
            {activeWork.map((request) => {
              const access = accessLabel(request.preferredAccessWindow)
              return <article className="technician-work__job" key={request.id}>
                <div className="technician-work__job-header">
                  <div>
                    <p className="technician-work__reference">{request.referenceCode || 'Reference unavailable'}</p>
                    <h3>{request.title}</h3>
                  </div>
                  <div className="technician-work__badges">
                    <StatusBadge tone={statusToneMap[request.status] ?? 'warning'}>{maintenanceEnumLabel(request.status, MAINTENANCE_STATUS)}</StatusBadge>
                    <StatusBadge tone={request.priority === 'Emergency' ? 'danger' : 'info'}>{maintenanceEnumLabel(request.priority, MAINTENANCE_PRIORITY)}</StatusBadge>
                  </div>
                </div>
                <dl className="technician-work__meta">
                  <div><dt>Property</dt><dd>{request.propertyTitle || 'Property unavailable'}</dd></div>
                  <div><dt>Category</dt><dd>{maintenanceEnumLabel(request.category, MAINTENANCE_CATEGORY)}</dd></div>
                  {access && <div><dt>Preferred access</dt><dd>{access}</dd></div>}
                </dl>
                <Link className="shared-button shared-button--outline technician-work__details" to="/modules/assigned-work">View details</Link>
              </article>
            })}
          </div>
        )}
      </section>
    </div>

  </main>
}
