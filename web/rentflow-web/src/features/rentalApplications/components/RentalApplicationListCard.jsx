import { useEffect, useRef, useState } from 'react'
import Icon from '../../../shared/ui/Icons.jsx'
import { RENTAL_APPLICATION_STATUS } from '../services/rentalApplicationApiService.js'
import RentalApplicationCard from './RentalApplicationCard.jsx'
import RentalApplicationStatusBadge from './RentalApplicationStatusBadge.jsx'

const dateFormatter = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' })

function displayDate(value) {
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? 'Date unavailable' : dateFormatter.format(date)
}

function displayDateOnly(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value || '')
  if (!match) return 'Date unavailable'
  const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
  return Number.isNaN(date.getTime()) ? 'Date unavailable' : dateFormatter.format(date)
}

export default function RentalApplicationListCard({
  application, isUpdating, actionError, onReview, onApprove, onReject, onRequestChanges,
}) {
  const [detailMode, setDetailMode] = useState(null)
  const detailRef = useRef(null)
  const isExpanded = detailMode !== null
  const detailsPanelId = `application-details-${application.id}`
  const validationPanelId = `application-validation-${application.id}`

  useEffect(() => {
    if (detailMode !== 'validation') return
    const validation = detailRef.current?.querySelector('[aria-label="Application validation"]')
    validation?.focus()
    validation?.scrollIntoView?.({ block: 'start' })
  }, [detailMode])

  return <article className="application-list-card">
    <div className="application-list-card__top">
      <span className="application-list-card__avatar" aria-hidden="true"><Icon name="user" size={22} /></span>
      <div className="application-list-card__identity">
        <p className="application-list-card__eyebrow">Tenant reference</p>
        <h2>{application.tenantId}</h2>
        <p>Property reference <code>{application.propertyId}</code></p>
      </div>
      <RentalApplicationStatusBadge status={application.status} />
    </div>

    <dl className="application-list-card__facts">
      <div><dt>Move-in</dt><dd>{application.moveInDate ? displayDateOnly(application.moveInDate) : 'Unavailable'}</dd></div>
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
          aria-expanded={detailMode === 'details'} aria-controls={detailsPanelId}
          onClick={() => setDetailMode(detailMode === 'details' ? null : 'details')}
        ><Icon name="search" size={17} />{detailMode === 'details' ? 'Hide details' : 'Details'}</button>
        <button type="button" className="application-button application-button--quiet"
          aria-expanded={detailMode === 'validation'} aria-controls={validationPanelId}
          onClick={() => setDetailMode('validation')}
        ><Icon name="trend" size={17} />AI Validation</button>
      </div>
      {application.submittedAt && <p className="application-list-card__submitted">Submitted <time dateTime={application.submittedAt}>{displayDate(application.submittedAt)}</time></p>}
    </div>
    {actionError && <p className="application-list-card__error" role="alert">{actionError}</p>}
    {isExpanded && <div ref={detailRef} id={detailMode === 'validation' ? validationPanelId : detailsPanelId} className="application-list-card__detail">
      <RentalApplicationCard application={application} isUpdating={isUpdating} actionError={actionError}
        onReview={onReview} onApprove={onApprove} onReject={onReject} onRequestChanges={onRequestChanges} />
    </div>}
  </article>
}
