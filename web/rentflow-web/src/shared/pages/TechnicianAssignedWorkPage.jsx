import { Link } from 'react-router-dom'
import { StatusBadge } from '../ui/States.jsx'
import Icon from '../ui/Icons.jsx'
import './technician-assigned-work.css'

export function AssignedWorkState({ status, error = '', onRetry }) {
  if (status === 'loading') {
    return <div className="assigned-work-state" role="status" aria-busy="true">
      <span className="shared-spinner" aria-hidden="true" />
      <h3>Loading assigned work</h3>
      <p>Please wait while the latest authorized work queue is loaded.</p>
    </div>
  }

  if (status === 'empty') {
    return <div className="assigned-work-state">
      <span className="assigned-work-state__icon"><Icon name="tools" size={28} /></span>
      <h3>No assigned work</h3>
      <p>Authorized maintenance assignments will appear here when work is allocated to your account.</p>
    </div>
  }

  if (status === 'error') {
    return <div className="assigned-work-state assigned-work-state--error" role="alert">
      <span className="assigned-work-state__icon"><Icon name="alert" size={28} /></span>
      <h3>Assigned work could not be loaded</h3>
      <p>{error || 'The assigned-work service is unavailable. Please try again.'}</p>
      {onRetry && <button className="shared-button" type="button" onClick={onRetry}>Try again</button>}
    </div>
  }

  return <div className="assigned-work-state assigned-work-state--integration" role="status">
    <span className="assigned-work-state__icon"><Icon name="tools" size={30} /></span>
    <StatusBadge tone="warning">Integration pending</StatusBadge>
    <h3>Work queue integration required</h3>
    <p>The Maintenance API does not currently provide an authenticated collection of work assigned to the signed-in Technician.</p>
    <p>No maintenance records or totals are shown until that authorized contract is available.</p>
  </div>
}

export default function TechnicianAssignedWorkPage() {
  return <main className="shared-page assigned-work-page">
    <header className="assigned-work-page__header">
      <div>
        <p className="assigned-work-page__eyebrow">Technician workspace</p>
        <h1>Assigned Work</h1>
        <p>Review the availability of your authorized maintenance work area.</p>
      </div>
      <div className="assigned-work-page__header-actions" aria-label="Assigned Work navigation">
        <Link className="shared-button shared-button--outline" to="/dashboard"><Icon name="home" size={18} />Back to dashboard</Link>
        <Link className="shared-button" to="/notifications" aria-label="Open notification inbox"><Icon name="bell" size={18} />Notifications</Link>
      </div>
    </header>

    <div className="assigned-work-page__layout">
      <section className="shared-card assigned-work-area" aria-labelledby="assigned-work-queue-title">
        <div className="assigned-work-area__heading">
          <div><p className="assigned-work-page__eyebrow">Work area</p><h2 id="assigned-work-queue-title">Your work queue</h2></div>
          <span className="assigned-work-area__scope"><Icon name="user" size={17} />Authenticated Technician scope</span>
        </div>
        <AssignedWorkState status="integration-pending" />
      </section>

      <aside className="assigned-work-page__side" aria-label="Assigned Work integration details">
        <section className="shared-card assigned-work-availability" aria-labelledby="assigned-work-availability-title">
          <div className="assigned-work-availability__heading"><span className="assigned-work-state__icon assigned-work-state__icon--small"><Icon name="info" size={21} /></span><div><p className="assigned-work-page__eyebrow">Availability</p><h2 id="assigned-work-availability-title">Workflow status</h2></div></div>
          <dl>
            <div><dt>Assigned-work list</dt><dd><StatusBadge tone="warning">Awaiting API contract</StatusBadge></dd></div>
            <div><dt>Record details</dt><dd>Hidden until an authorized record is available</dd></div>
            <div><dt>Estimate and job actions</dt><dd>Not exposed without a verified assignment workflow</dd></div>
          </dl>
        </section>

        <section className="shared-card assigned-work-tools" aria-labelledby="assigned-work-tools-title">
          <div><p className="assigned-work-page__eyebrow">Shared tools</p><h2 id="assigned-work-tools-title">Account access</h2></div>
          <Link to="/notifications" aria-label="Open notifications from Assigned Work"><span className="assigned-work-state__icon assigned-work-state__icon--small"><Icon name="bell" size={20} /></span><span><strong>Notifications</strong><small>Review updates for your account</small></span><Icon name="arrow" size={17} /></Link>
          <Link to="/profile"><span className="assigned-work-state__icon assigned-work-state__icon--small"><Icon name="user" size={20} /></span><span><strong>Profile</strong><small>View account details and sign out</small></span><Icon name="arrow" size={17} /></Link>
        </section>
      </aside>
    </div>
  </main>
}
