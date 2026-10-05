import { useCallback, useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { USER_ROLES } from '../../auth/authModel.js'
import { useAuth } from '../../auth/useAuth.js'
import { ErrorState, LoadingState, UnauthorizedState } from '../../../shared/ui/States.jsx'
import Icon from '../../../shared/ui/Icons.jsx'
import ViewingAvailabilityEditor from '../components/ViewingAvailabilityEditor.jsx'
import { getMyProperties, getProperty } from '../services/propertyApiService.js'
import '../properties.css'

const PROPERTY_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const UNSAVED_MESSAGE = 'You have unsaved viewing availability changes. Leave without saving them?'

export default function ViewingAvailabilityPage() {
  const { propertyId } = useParams()
  const { user } = useAuth()
  const [result, setResult] = useState(null)
  const [attempt, setAttempt] = useState(0)
  const [dirtyState, setDirtyState] = useState(null)
  const canManage = user?.role === USER_ROLES.LANDLORD || user?.role === USER_ROLES.ADMIN
  const validId = PROPERTY_ID.test(propertyId ?? '')
  const scope = `${user?.id}:${user?.role}:${propertyId}:${attempt}`
  const current = result?.scope === scope ? result : null
  const dirty = dirtyState?.scope === scope && dirtyState.dirty
  const onDirtyChange = useCallback(dirty => setDirtyState(previous =>
    previous?.scope === scope && previous.dirty === dirty ? previous : { scope, dirty }), [scope])

  useEffect(() => {
    if (!canManage || !validId) return undefined
    let active = true
    async function loadProperty() {
      try {
        let property
        if (user.role === USER_ROLES.ADMIN) {
          property = await getProperty(propertyId)
        } else {
          const properties = await getMyProperties()
          if (!Array.isArray(properties)) throw new Error('Your property portfolio could not be loaded.')
          property = properties.find(item => typeof item?.id === 'string'
            && item.id.toLowerCase() === propertyId.toLowerCase()
            && typeof item.landlordId === 'string'
            && item.landlordId.toLowerCase() === user.id.toLowerCase())
        }
        if (!property || typeof property.id !== 'string'
          || property.id.toLowerCase() !== propertyId.toLowerCase()
          || typeof property.title !== 'string') {
          throw new Error('This property is unavailable or you do not have permission to manage it.')
        }
        if (active) setResult({ scope, property })
      } catch (error) {
        if (active) setResult({ scope, error: error instanceof Error ? error.message : 'Unable to load this property.' })
      }
    }
    loadProperty()
    return () => { active = false }
  }, [canManage, validId, propertyId, user.id, user.role, scope])

  useEffect(() => {
    if (!dirty) return undefined
    const beforeUnload = event => { event.preventDefault(); event.returnValue = '' }
    const beforeNavigation = event => {
      if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
      const link = event.target.closest?.('a[href]')
      if (!link || link.target === '_blank' || link.hasAttribute('download') || link.href === window.location.href) return
      if (!window.confirm(UNSAVED_MESSAGE)) { event.preventDefault(); event.stopPropagation() }
    }
    window.addEventListener('beforeunload', beforeUnload)
    document.addEventListener('click', beforeNavigation, true)
    return () => {
      window.removeEventListener('beforeunload', beforeUnload)
      document.removeEventListener('click', beforeNavigation, true)
    }
  }, [dirty])

  if (!canManage) return <UnauthorizedState />
  if (!validId) return <ErrorState title="Property unavailable" message="Choose a valid property to manage its viewing availability." />
  if (!current) return <LoadingState title="Loading property" />
  if (current.error) return <ErrorState title="Property unavailable" message={current.error} onRetry={() => setAttempt(value => value + 1)} />

  const { property } = current
  return <main className="viewing-availability-page">
    <Link className="viewing-availability-page__back" to={`/properties/${encodeURIComponent(property.id)}`}>
      <Icon name="arrowLeft" size={17} /> Back to property
    </Link>
    <header className="viewing-availability-page__header">
      <h1>Viewing availability</h1>
      <p>Choose when tenants can request a viewing.<br />Requests still need your approval.</p>
    </header>
    <section className="viewing-availability-page__property" aria-label="Property context">
      <span className="viewing-availability-page__property-icon" aria-hidden="true"><Icon name="building" size={24} /></span>
      <div><h2>{property.title}</h2>{property.city && <p>{[property.address, property.city].filter(Boolean).join(', ')}</p>}</div>
    </section>
    <ViewingAvailabilityEditor key={scope} propertyId={property.id}
      onDirtyChange={onDirtyChange} />
  </main>
}
