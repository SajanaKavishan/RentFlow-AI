import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import Icon from '../../../shared/ui/Icons.jsx'
import { getProperty } from '../services/propertyApiService.js'
import './property-workflow-handoff.css'
import { useApplicationEligibility } from '../../rentalApplications/useApplicationEligibility.js'

const WORKFLOW_COPY = {
  viewing: {
    noun: 'viewing request',
    plural: 'viewing requests',
    action: 'book a viewing',
  },
  application: {
    noun: 'application',
    plural: 'applications',
    action: 'create an application',
  },
}

export default function PropertyWorkflowHandoff({ propertyId, workflow, existingCount = 0, refreshVersion = 0 }) {
  const copy = WORKFLOW_COPY[workflow]
  const eligibility = useApplicationEligibility(propertyId, workflow === 'application', refreshVersion)
  const [loadedState, setLoadedState] = useState({ propertyId: null, status: 'loading', property: null })
  const state = loadedState.propertyId === propertyId
    ? loadedState
    : { status: 'loading', property: null }

  useEffect(() => {
    let active = true
    getProperty(propertyId)
      .then((property) => {
        if (active) setLoadedState({ propertyId, status: 'ready', property })
      })
      .catch(() => {
        if (active) setLoadedState({ propertyId, status: 'error', property: null })
      })
    return () => { active = false }
  }, [propertyId])

  if (!copy) return null

  return (
    <section className="property-workflow-handoff" aria-labelledby={`${workflow}-property-context`}>
      <div className="property-workflow-handoff__icon" aria-hidden="true">
        <Icon name={workflow === 'viewing' ? 'calendar' : 'document'} size={21} />
      </div>
      <div className="property-workflow-handoff__content">
        <p className="property-workflow-handoff__eyebrow">Selected property</p>
        {state.status === 'loading' && (
          <h2 id={`${workflow}-property-context`} role="status">Loading property context&hellip;</h2>
        )}
        {state.status === 'error' && (
          <>
            <h2 id={`${workflow}-property-context`}>Selected property unavailable</h2>
            <p>The link may be outdated. Your existing {copy.plural} are still available below.</p>
          </>
        )}
        {state.status === 'ready' && (
          <>
            <h2 id={`${workflow}-property-context`}>{state.property.title}</h2>
            <p>{[state.property.address, state.property.city].filter(Boolean).join(', ') || 'Location not specified'}</p>
            <p className="property-workflow-handoff__note">
              {workflow === 'application'
                ? eligibility.loading ? 'Checking application eligibility…'
                  : eligibility.error || (eligibility.data?.existingApplicationId
                    ? 'Your existing application remains available. Use the mobile app to continue editing a draft.'
                    : eligibility.data?.canApply ? 'This property is ready to apply. Continue in the RentFlow mobile app to create an application.'
                      : eligibility.data?.reason || 'Complete a viewing before applying for this property.')
                : !state.property.isAvailable
                ? `This property is currently unavailable. Existing ${copy.plural} remain available below.`
                : existingCount > 0
                  ? `You already have ${existingCount === 1 ? `a ${copy.noun}` : `${existingCount} ${copy.plural}`} for this property. Review ${existingCount === 1 ? 'it' : 'them'} below; new actions are completed in the mobile app.`
                  : `This property is selected. Continue in the RentFlow mobile app to ${copy.action}.`}
            </p>
            {workflow === 'application' && eligibility.data?.existingApplicationId && <Link to={`/notifications/rental-application/${encodeURIComponent(eligibility.data.existingApplicationId)}`}>View application</Link>}
          </>
        )}
      </div>
      <Link className="property-workflow-handoff__back" to={`/properties/${encodeURIComponent(propertyId)}`}>
        Back to property <Icon name="arrow" size={16} />
      </Link>
    </section>
  )
}
