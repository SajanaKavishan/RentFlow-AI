import { jobDate } from './technicianWorkPresentation.js'
import { Link } from 'react-router-dom'
import Icon from '../ui/Icons.jsx'
import { MAINTENANCE_CATEGORY, MAINTENANCE_PRIORITY, MAINTENANCE_STATUS, maintenanceEnumLabel } from '../../features/maintenance/services/maintenanceEnums.js'

export default function TechnicianJobCard({ request, children, preview = false }) {
  const completed = request.status === 'Completed'
  const location = [request.propertyTitle, request.propertyAddress, request.propertyCity].filter(Boolean).join(' · ')
  const reference = request.referenceCode?.trim()
  const requester = request.requesterName?.trim()
  const completionDate = completed ? jobDate(request.completedAt) : null
  return <article className={`technician-job${request.priority === 'Emergency' ? ' technician-job--emergency' : ''}`}>
    <div className="technician-job__header">
      <span className={`technician-job__icon${completed ? ' technician-job__icon--complete' : ''}`}><Icon name={completed ? 'check' : 'tools'} size={24} /></span>
      <div className="technician-job__identity">
        <h3>{request.title}</h3>
        {location && <p className="technician-job__location"><Icon name="location" size={15} />{location}</p>}
        {reference && <p className="technician-job__reference">{reference}</p>}
        {requester && <p className="technician-job__requester">Requested by {requester}</p>}
      </div>
      <div className="technician-job__badges">
        <span className={`technician-badge technician-badge--${request.status}`}>{maintenanceEnumLabel(request.status, MAINTENANCE_STATUS)}</span>
        <span className={`technician-badge technician-badge--${request.priority}`}>{maintenanceEnumLabel(request.priority, MAINTENANCE_PRIORITY)}</span>
      </div>
    </div>
    <dl className="technician-job__meta">
      <div><dt>Category</dt><dd>{request.category != null ? maintenanceEnumLabel(request.category, MAINTENANCE_CATEGORY) : 'Unavailable'}</dd></div>
      <div><dt><Icon name="calendar" size={14} />Completed</dt><dd>{completionDate || 'Completion date unavailable'}</dd></div>
    </dl>
    {request.description && <p className="technician-job__description">{request.description}</p>}
    {(request.finalWorkNote || request.workNote || request.assignmentNotes) && <p className="technician-job__note"><span>{request.finalWorkNote || request.workNote ? 'Work note: ' : 'Assignment note: '}</span>{request.finalWorkNote || request.workNote || request.assignmentNotes}</p>}
    {preview && <Link className="shared-button shared-button--outline" to="/modules/assigned-work">View work <Icon name="arrow" size={16} /></Link>}
    {children}
  </article>
}
