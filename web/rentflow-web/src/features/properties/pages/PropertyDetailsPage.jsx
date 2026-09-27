import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { USER_ROLES } from '../../auth/authModel.js'
import { useAuth } from '../../auth/useAuth.js'
import Icon from '../../../shared/ui/Icons.jsx'
import PropertyImageGallery from '../components/PropertyImageGallery.jsx'
import PropertyLocationMap from '../components/PropertyLocationMap.jsx'
import {
  deleteProperty,
  getProperty,
  updateProperty,
} from '../services/propertyApiService.js'
import '../properties.css'

const MANAGE_PROPERTIES_PATH = '/modules/manage-properties'

export default function PropertyDetailsPage() {
  const { propertyId } = useParams()
  const navigate = useNavigate()
  const { user } = useAuth()
  const [property, setProperty] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [action, setAction] = useState('')
  const [toast, setToast] = useState(null)

  const isOwner = user?.role === USER_ROLES.LANDLORD
    && String(user.id).toLowerCase() === String(property?.landlordId).toLowerCase()
  const backPath = user?.role === USER_ROLES.LANDLORD
    ? MANAGE_PROPERTIES_PATH
    : '/modules/properties'

  useEffect(() => {
    let active = true

    async function loadProperty() {
      setLoading(true)
      setError('')

      try {
        const result = await getProperty(propertyId)
        if (active) setProperty(result)
      } catch (err) {
        if (active) setError(err.message)
      } finally {
        if (active) setLoading(false)
      }
    }

    loadProperty()
    return () => { active = false }
  }, [propertyId])

  useEffect(() => {
    if (!toast) return undefined
    const timer = window.setTimeout(() => setToast(null), 3000)
    return () => window.clearTimeout(timer)
  }, [toast])

  const showToast = (tone, message) => setToast({ tone, message })

  async function handleAvailability() {
    setAction('availability')

    try {
      const updatedProperty = await updateProperty(property.id, {
        title: property.title,
        description: property.description,
        address: property.address,
        city: property.city,
        monthlyRent: Number(property.monthlyRent),
        bedrooms: Number(property.bedrooms),
        bathrooms: Number(property.bathrooms),
        area: property.area ?? null,
        areaUnit: property.areaUnit ?? null,
        isAvailable: !property.isAvailable,
        amenities: property.amenities || [],
      })

      setProperty(updatedProperty)
      showToast(
        'success',
        updatedProperty.isAvailable
          ? `${updatedProperty.title} is now available.`
          : `${updatedProperty.title} is now unavailable.`,
      )
    } catch (err) {
      showToast(
        'error',
        `Could not update availability for ${property.title}. ${err.message || 'Please try again.'}`,
      )
    } finally {
      setAction('')
    }
  }

  async function handleDelete() {
    const confirmed = window.confirm(
      `Are you sure you want to permanently delete ${property.title}?`,
    )
    if (!confirmed) return

    setAction('delete')

    try {
      await deleteProperty(property.id)
      navigate(MANAGE_PROPERTIES_PATH, {
        replace: true,
        state: { propertyMessage: `${property.title} was deleted successfully.` },
      })
    } catch (err) {
      showToast(
        'error',
        `Could not delete ${property.title}. ${err.message || 'Please try again.'}`,
      )
      setAction('')
    }
  }

  if (loading) {
    return (
      <main className="property-details-page">
        <div className="property-details-state" role="status">
          <span className="property-spinner" aria-hidden="true" />
          <h1>Loading property...</h1>
          <p>Preparing the full property details.</p>
        </div>
      </main>
    )
  }

  if (error || !property) {
    return (
      <main className="property-details-page">
        <Link className="property-details-back" to={backPath}>
          <Icon name="arrowLeft" size={16} /> Back to properties
        </Link>
        <div className="property-details-state property-details-state--error" role="alert">
          <Icon name="alert" size={28} />
          <h1>Property unavailable</h1>
          <p>{error || 'This property could not be found.'}</p>
        </div>
      </main>
    )
  }

  return (
    <main className="property-details-page">
      {toast && (
        <div
          className={`property-toast property-toast--${toast.tone}`}
          role={toast.tone === 'error' ? 'alert' : 'status'}
          aria-live="polite"
          aria-atomic="true"
        >
          <span className="property-toast__mark" aria-hidden="true">
            {toast.tone === 'success' ? '✓' : '×'}
          </span>
          <p>{toast.message}</p>
        </div>
      )}

      <Link className="property-details-back" to={backPath}>
        <Icon name="arrowLeft" size={16} /> Back to properties
      </Link>

      <header className="property-details-header">
        <div>
          <span className={`property-details-status ${property.isAvailable ? 'is-available' : 'is-unavailable'}`}>
            {property.isAvailable ? 'Available' : 'Unavailable'}
          </span>
          <h1>{property.title}</h1>
          <p><Icon name="pin" size={17} /> {[property.address, property.city].filter(Boolean).join(', ')}</p>
        </div>
        <div className="property-details-rent">
          <strong>Rs. {Number(property.monthlyRent).toLocaleString()}</strong>
          <span>per month</span>
        </div>
      </header>

      <section className="property-details-gallery" aria-label="Property photos">
        <PropertyImageGallery propertyId={property.id} alt={property.title} variant="details" />
      </section>

      <div className={`property-details-layout${isOwner ? '' : ' property-details-layout--public'}`}>
        <div className="property-details-main">
          <dl className="property-details-facts">
            <div>
              <Icon name="bed" size={22} />
              <dt>Bedrooms</dt>
              <dd>{property.bedrooms}</dd>
            </div>
            <div>
              <Icon name="bath" size={22} />
              <dt>Bathrooms</dt>
              <dd>{property.bathrooms}</dd>
            </div>
            <div>
              <Icon name={property.isAvailable ? 'eye' : 'eyeOff'} size={22} />
              <dt>Availability</dt>
              <dd>{property.isAvailable ? 'Available' : 'Unavailable'}</dd>
            </div>
          </dl>

          <section className="property-details-section">
            <span className="property-section-number">About this property</span>
            <h2>Property description</h2>
            <p>{property.description}</p>
          </section>

          <section className="property-details-section">
            <span className="property-section-number">Included features</span>
            <h2>Amenities</h2>
            {property.amenities?.length > 0 ? (
              <ul className="property-details-amenities">
                {property.amenities.map((amenity) => (
                  <li key={amenity}>✓ {amenity}</li>
                ))}
              </ul>
            ) : (
              <p>No amenities have been added yet.</p>
            )}
          </section>

          <PropertyLocationMap address={property.address} city={property.city} />
        </div>

        {isOwner && (
          <aside className="property-details-management" aria-label="Manage property">
            <div>
              <span className="property-section-number">Landlord tools</span>
              <h2>Manage this property</h2>
              <p>Review activity or update this listing.</p>
            </div>

            <div className="property-details-workflows">
              <Link to={`/properties/${encodeURIComponent(property.id)}/viewing-requests`}>
                <Icon name="calendar" size={19} />
                <span>Viewing Requests</span>
                <Icon name="arrow" size={16} />
              </Link>
              <Link to={`/properties/${encodeURIComponent(property.id)}/rental-applications`}>
                <Icon name="document" size={19} />
                <span>Rental Applications</span>
                <Icon name="arrow" size={16} />
              </Link>
            </div>

            <div className="property-details-actions">
              <Link to={`/properties/${encodeURIComponent(property.id)}/edit`}>
                <Icon name="edit" size={17} /> Edit
              </Link>
              <button type="button" onClick={handleAvailability} disabled={Boolean(action)}>
                <Icon name={property.isAvailable ? 'eyeOff' : 'eye'} size={17} />
                {action === 'availability'
                  ? 'Updating...'
                  : property.isAvailable ? 'Mark unavailable' : 'Mark available'}
              </button>
              <button
                type="button"
                className="is-danger"
                onClick={handleDelete}
                disabled={Boolean(action)}
              >
                <Icon name="trash" size={17} />
                {action === 'delete' ? 'Deleting...' : 'Delete'}
              </button>
            </div>
          </aside>
        )}
      </div>
    </main>
  )
}
