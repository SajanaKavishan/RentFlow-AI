import { useState } from 'react'
import { Link } from 'react-router-dom'
import Icon from '../../../shared/ui/Icons.jsx'
import { RENTAL_APPLICATION_STATUS } from '../services/rentalApplicationApiService.js'
import RentalApplicationCard from './RentalApplicationCard.jsx'
import RentalApplicationStatusBadge from './RentalApplicationStatusBadge.jsx'

const dateFormatter = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' })
const dateTimeFormatter = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' })
const incomeFormatter = new Intl.NumberFormat(undefined, {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
})

function displayDate(value) {
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? 'Date unavailable' : dateTimeFormatter.format(date)
}

function displayDateOnly(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value || '')
  if (!match) return 'Date unavailable'
  const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
  return Number.isNaN(date.getTime()) ? 'Date unavailable' : dateFormatter.format(date)
}

function displayIncome(value) {
  const income = Number(value)
  return Number.isFinite(income) ? incomeFormatter.format(income) : 'Unavailable'
}

export default function RentalApplicationListCard({
  application, property, isUpdating, actionError, onReview, onApprove, onReject, onRequestChanges,
}) {
  const [detailsExpanded, setDetailsExpanded] = useState(false)
  const detailsPanelId = `application-details-${application.id}`
  const validationPath = `/properties/${encodeURIComponent(application.propertyId)}/rental-applications/${encodeURIComponent(application.id)}/validation`

  return <article className="application-list-card">
    <div className="application-list-card__top">
      <span className="application-list-card__avatar" aria-hidden="true"><Icon name="user" size={22} /></span>
      <div className="application-list-card__identity">
        <p className="application-list-card__eyebrow">Application reference</p>
        <h2>{application.id}</h2>
        <p className="application-list-card__tenant">Tenant reference <code>{application.tenantId}</code></p>
        {property
          ? <p>Property <strong>{property.title}</strong><span className="application-list-card__property-location">{[property.address, property.city].filter(Boolean).join(', ')}</span></p>
          : <p>Property reference <code>{application.propertyId}</code></p>}
      </div>
      <RentalApplicationStatusBadge status={application.status} />
    </div>

    <dl className="application-list-card__facts">
      <div><dt>Move-in</dt><dd>{application.moveInDate ? displayDateOnly(application.moveInDate) : 'Unavailable'}</dd></div>
      <div><dt>Monthly income</dt><dd>{displayIncome(application.monthlyIncome)}</dd></div>
      <div><dt>Occupation</dt><dd>{application.occupation?.trim() || 'Not provided'}</dd></div>
      <div><dt>Occupants</dt><dd>{application.numberOfOccupants ?? 'Unavailable'}</dd></div>
    </dl>

    <div className="application-list-card__footer">
      <div className="application-list-card__actions">
        {application.status === RENTAL_APPLICATION_STATUS.SUBMITTED && <button
          type="button" className="application-button application-button--primary"
          onClick={() => onReview(application.id)} disabled={isUpdating}
        >{isUpdating ? 'Saving...' : 'Start review'}</button>}
        <button type="button" className="application-button application-button--quiet"
          aria-expanded={detailsExpanded} aria-controls={detailsPanelId}
          onClick={() => setDetailsExpanded((current) => !current)}
        ><Icon name="search" size={17} />{detailsExpanded ? 'Hide details' : 'Details'}</button>
        <Link className="application-button application-button--validation" to={validationPath}
          aria-label={`AI Validation for application ${application.id}`}>
          <Icon name="trend" size={17} />AI Validation
        </Link>
      </div>
      {(application.submittedAt || application.updatedAt) && <dl className="application-list-card__timeline">
        {application.submittedAt && <div><dt>Submitted</dt><dd><time dateTime={application.submittedAt}>{displayDate(application.submittedAt)}</time></dd></div>}
        {application.updatedAt && <div><dt>Updated</dt><dd><time dateTime={application.updatedAt}>{displayDate(application.updatedAt)}</time></dd></div>}
      </dl>}
    </div>
    {actionError && <p className="application-list-card__error" role="alert">{actionError}</p>}
    {detailsExpanded && <div id={detailsPanelId} className="application-list-card__detail">
      <RentalApplicationCard application={application} isUpdating={isUpdating} actionError={actionError}
        onReview={onReview} onApprove={onApprove} onReject={onReject} onRequestChanges={onRequestChanges} />
    </div>}
  </article>
}
