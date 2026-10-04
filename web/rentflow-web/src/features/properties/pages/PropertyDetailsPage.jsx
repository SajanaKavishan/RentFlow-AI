import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { USER_ROLES } from '../../auth/authModel.js'
import { useAuth } from '../../auth/useAuth.js'
import Icon from '../../../shared/ui/Icons.jsx'
import PropertyImageGallery from '../components/PropertyImageGallery.jsx'
import PropertyLocationMap from '../components/PropertyLocationMap.jsx'
import PublicLandlordAvatar from '../components/PublicLandlordAvatar.jsx'
import LandlordContact from '../components/LandlordContact.jsx'
import ViewingReviews from '../components/ViewingReviews.jsx'
import { formatPropertyArea } from '../propertyArea.js'
import {
  UTILITY_CATALOG,
  getAmenityPresentation,
  getPropertyAmenityDetails,
} from '../propertyListingCatalog.js'
import {
  deleteProperty,
  getMyProperties,
  getProperty,
  getPublicLandlordSummary,
  getSavedPropertyMatches,
  updateProperty,
} from '../services/propertyApiService.js'
import { getMyViewings } from '../../viewings/services/viewingApiService.js'
import {
  getMyApplications,
  RENTAL_APPLICATION_STATUS,
} from '../../rentalApplications/services/rentalApplicationApiService.js'
import '../properties.css'
import { useApplicationEligibility } from '../../rentalApplications/useApplicationEligibility.js'

const MANAGE_PROPERTIES_PATH = '/modules/manage-properties'
const ACTIVE_APPLICATION_STATUSES = new Set([
  RENTAL_APPLICATION_STATUS.DRAFT,
  RENTAL_APPLICATION_STATUS.SUBMITTED,
  RENTAL_APPLICATION_STATUS.UNDER_REVIEW,
  RENTAL_APPLICATION_STATUS.CHANGES_REQUESTED,
])

function formatAvailableFrom(value) {
  if (!value) return null
  const date = new Date(`${value}T00:00:00`)
  if (Number.isNaN(date.getTime())) return null
  return date.toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
}

function formatPetPolicy(property) {
  if (!property?.petPolicy) return null
  if (property.petPolicy === 'NotAllowed') return 'Not allowed'
  if (property.petPolicyNotes?.trim()) return property.petPolicyNotes.trim()
  return property.petPolicy === 'Conditional' ? 'Conditional' : 'Allowed'
}

function formatUtilities(includedUtilities) {
  if (!Array.isArray(includedUtilities)) return null
  if (includedUtilities.length === 0) return 'None advertised as included'
  const labels = new Map(UTILITY_CATALOG.map((item) => [item.key, item.label]))
  return includedUtilities.map((key) => labels.get(key) || key).join(', ')
}

export default function PropertyDetailsPage() {
  const { propertyId } = useParams()
  const navigate = useNavigate()
  const { user } = useAuth()
  const [property, setProperty] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [action, setAction] = useState('')
  const [toast, setToast] = useState(null)
  const [matchResult, setMatchResult] = useState({ propertyId: null, score: null, reasons: [] })
  const [loadedLandlordState, setLandlordState] = useState({ propertyId: null, status: 'loading', summary: null })
  const [loadedWorkflowState, setWorkflowState] = useState({
    propertyId: null,
    viewings: 0,
    applications: 0,
    activeApplication: false,
  })
  const landlordState = loadedLandlordState.propertyId === propertyId
    ? loadedLandlordState
    : { status: 'loading', summary: null }
  const workflowState = loadedWorkflowState.propertyId === propertyId
    ? loadedWorkflowState
    : { viewings: 0, applications: 0, activeApplication: false }

  const isOwner = user?.role === USER_ROLES.LANDLORD
    && String(user.id).toLowerCase() === String(property?.landlordId).toLowerCase()
  const isTenant = user?.role === USER_ROLES.TENANT
  const eligibility = useApplicationEligibility(propertyId, isTenant && Boolean(property))
  const canOpenApplication = !eligibility.loading && (eligibility.data?.canApply === true || Boolean(eligibility.data?.existingApplicationId))
  const matchScore = matchResult.propertyId === propertyId ? matchResult.score : null
  const matchReasons = matchResult.propertyId === propertyId ? matchResult.reasons : []
  const backPath = user?.role === USER_ROLES.LANDLORD
    ? MANAGE_PROPERTIES_PATH
    : '/modules/properties'
  const availableFromLabel = formatAvailableFrom(property?.availableFrom)
  const petPolicyLabel = formatPetPolicy(property)
  const utilitiesLabel = formatUtilities(property?.includedUtilities)
  const amenityDetails = getPropertyAmenityDetails(property)

  useEffect(() => {
    let active = true

    async function loadProperty() {
      setLoading(true)
      setError('')
      setProperty(null)

      try {
        let result
        if (user?.role === USER_ROLES.LANDLORD) {
          const properties = await getMyProperties()
          if (!Array.isArray(properties)) {
            throw new TypeError('Invalid owned property response')
          }
          result = properties.find((item) =>
            typeof item?.id === 'string'
            && item.id.toLowerCase() === propertyId.toLowerCase()
            && typeof item.landlordId === 'string'
            && item.landlordId.toLowerCase() === user.id.toLowerCase())
          if (!result) {
            throw new Error('This property is not in your authenticated property portfolio.')
          }
        } else {
          result = await getProperty(propertyId)
        }
        if (active) setProperty(result)
      } catch (err) {
        if (active) setError(err.message)
      } finally {
        if (active) setLoading(false)
      }
    }

    loadProperty()
    return () => { active = false }
  }, [propertyId, user?.id, user?.role])

  useEffect(() => {
    let active = true

    if (!isTenant) return () => { active = false }

    getSavedPropertyMatches()
      .then((result) => {
        const match = Array.isArray(result?.matches)
          ? result.matches.find((item) => (
            String(item?.propertyId).toLowerCase() === String(propertyId).toLowerCase()
          ))
          : null
        if (active && Number.isFinite(Number(match?.matchScore))) {
          const reasons = Array.isArray(match.matchReasons)
            ? [...new Set(match.matchReasons
              .filter((reason) => typeof reason === 'string' && reason.trim())
              .map((reason) => reason.trim()))]
            : []
          setMatchResult({ propertyId, score: Number(match.matchScore), reasons })
        }
      })
      .catch(() => {
        // Matching is optional on the details page; the listing remains fully usable.
      })

    return () => { active = false }
  }, [isTenant, propertyId])

  useEffect(() => {
    let active = true

    if (!isTenant) return () => { active = false }

    getPublicLandlordSummary(propertyId)
      .then((summary) => {
        if (!summary
          || typeof summary.displayName !== 'string'
          || !summary.displayName.trim()
          || !Number.isInteger(summary.memberSinceYear)
          || typeof summary.hasProfileImage !== 'boolean') {
          throw new TypeError('Invalid public landlord summary')
        }
        if (active) setLandlordState({ propertyId, status: 'ready', summary })
      })
      .catch(() => {
        if (active) setLandlordState({ propertyId, status: 'error', summary: null })
      })

    return () => { active = false }
  }, [isTenant, propertyId])

  useEffect(() => {
    let active = true
    if (!isTenant || !property) return () => { active = false }

    Promise.allSettled([getMyViewings(), getMyApplications()]).then(([viewingsResult, applicationsResult]) => {
      if (!active) return
      const sameProperty = (item) => String(item?.propertyId).toLowerCase() === String(property.id).toLowerCase()
      const viewings = viewingsResult.status === 'fulfilled' && Array.isArray(viewingsResult.value)
        ? viewingsResult.value.filter(sameProperty).length
        : 0
      const applications = applicationsResult.status === 'fulfilled' && Array.isArray(applicationsResult.value)
        ? applicationsResult.value.filter(sameProperty)
        : []
      const activeApplication = applicationsResult.status === 'fulfilled'
        && applications.some((item) => ACTIVE_APPLICATION_STATUSES.has(item.status))
      setWorkflowState({
        propertyId: property.id,
        viewings,
        applications: applications.length,
        activeApplication,
      })
    })

    return () => { active = false }
  }, [isTenant, property])

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
        latitude: property.latitude ?? null,
        longitude: property.longitude ?? null,
        googlePlaceId: property.googlePlaceId ?? null,
        monthlyRent: Number(property.monthlyRent),
        bedrooms: Number(property.bedrooms),
        bathrooms: Number(property.bathrooms),
        area: property.area ?? null,
        areaUnit: property.areaUnit ?? null,
        areaType: property.areaType ?? null,
        availableFrom: property.availableFrom ?? null,
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

      <div className="property-details-layout">
        <div className="property-details-main">
          <section className="property-details-gallery" aria-label="Property photos">
            <PropertyImageGallery
              propertyId={property.id}
              alt={property.title}
              variant="details"
              matchScore={matchScore}
            />
          </section>

          <header className="property-details-header">
            <h1>{property.title}</h1>
            <p>
              <Icon name="pin" size={17} />
              {[property.address, property.city].filter(Boolean).join(', ') || 'Location not specified'}
            </p>
            <dl className="property-details-facts" aria-label="Property highlights">
              <div>
                <Icon name="bed" size={18} />
                <dt className="sr-only">Bedrooms</dt>
                <dd>{property.bedrooms} {property.bedrooms === 1 ? 'Bedroom' : 'Bedrooms'}</dd>
              </div>
              <div>
                <Icon name="bath" size={18} />
                <dt className="sr-only">Bathrooms</dt>
                <dd>{property.bathrooms} {property.bathrooms === 1 ? 'Bathroom' : 'Bathrooms'}</dd>
              </div>
              {property.area != null && Number(property.area) > 0 && (
                <div>
                  <Icon name="ruler" size={18} />
                  <dt className="sr-only">Size</dt>
                  <dd>{formatPropertyArea(property.area, property.areaUnit, property.areaType)}</dd>
                </div>
              )}
              <div className={property.isAvailable ? 'is-available' : 'is-unavailable'}>
                <Icon name="calendar" size={18} />
                <dt className="sr-only">Availability</dt>
                <dd>{property.isAvailable
                  ? availableFromLabel ? `Available ${availableFromLabel}` : 'Available now'
                  : availableFromLabel ? `Unavailable · Available ${availableFromLabel}` : 'Currently unavailable'}</dd>
              </div>
            </dl>
          </header>

          {matchReasons.length > 0 && (
            <section className="property-details-match" aria-labelledby="property-match-title">
              <div className="property-details-match__heading">
                <span aria-hidden="true"><Icon name="sparkles" size={17} /></span>
                <h2 id="property-match-title">Why this matches</h2>
              </div>
              <ul>
                {matchReasons.map((reason) => <li key={reason}>{reason}</li>)}
              </ul>
            </section>
          )}
        </div>

        {isOwner ? (
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
              <Link to={`/properties/${encodeURIComponent(property.id)}/viewing-availability`}>
                <Icon name="calendar" size={17} /> Viewing availability
              </Link>
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
        ) : (
          <aside className="property-details-summary" aria-label="Rental summary">
            <div className="property-details-summary__price">
              <strong>Rs. {Number(property.monthlyRent).toLocaleString()}</strong>
              <span>/month</span>
            </div>

            <dl className="property-details-summary__details">
              {property.advertisedSecurityDeposit != null && (
                <div>
                  <dt>Advertised security deposit</dt>
                  <dd>Rs. {Number(property.advertisedSecurityDeposit).toLocaleString()}</dd>
                </div>
              )}
              {property.preferredLeaseTermMonths != null && (
                <div>
                  <dt>Preferred lease term</dt>
                  <dd>{property.preferredLeaseTermMonths} months</dd>
                </div>
              )}
              {petPolicyLabel && (
                <div>
                  <dt>Pets</dt>
                  <dd>{petPolicyLabel}</dd>
                </div>
              )}
              {utilitiesLabel && (
                <div>
                  <dt>Utilities</dt>
                  <dd>{utilitiesLabel}</dd>
                </div>
              )}
              <div>
                <dt>Availability</dt>
                <dd className={property.isAvailable ? 'is-available' : 'is-unavailable'}>
                  <span aria-hidden="true" />
                  {property.isAvailable ? 'Available to rent' : 'Currently unavailable'}
                </dd>
              </div>
              {availableFromLabel && (
                <div>
                  <dt>Available from</dt>
                  <dd>{availableFromLabel}</dd>
                </div>
              )}
            </dl>

            {isTenant && (
              <div className="property-details-summary__actions">
                <Link
                  className={`property-details-summary__primary${property.isAvailable || workflowState.viewings > 0 ? '' : ' is-disabled'}`}
                  to={`/modules/my-viewings?propertyId=${encodeURIComponent(property.id)}`}
                  aria-disabled={!property.isAvailable && workflowState.viewings === 0}
                  onClick={(event) => { if (!property.isAvailable && workflowState.viewings === 0) event.preventDefault() }}
                >
                  {workflowState.viewings > 0 ? 'View viewing requests' : 'Book a Viewing'}
                </Link>
                <Link
                  className={`property-details-summary__secondary${canOpenApplication ? '' : ' is-disabled'}`}
                  to={eligibility.data?.existingApplicationId ? `/notifications/rental-application/${encodeURIComponent(eligibility.data.existingApplicationId)}` : `/modules/my-applications?propertyId=${encodeURIComponent(property.id)}`}
                  aria-disabled={!canOpenApplication}
                  onClick={(event) => { if (!canOpenApplication) event.preventDefault() }}
                >
                  {eligibility.data?.existingApplicationId
                    ? 'View application'
                    : eligibility.loading ? 'Checking eligibility…' : eligibility.data?.canApply ? 'Apply for Rental' : 'Apply after viewing'}
                </Link>
                {!canOpenApplication && !eligibility.loading && <p>{eligibility.error || eligibility.data?.reason || 'Complete a viewing before applying for this property.'}</p>}
                <p>{property.isAvailable
                  ? 'Your selected property will be carried into each workspace. New bookings and applications are completed in the RentFlow mobile app.'
                  : 'This property is currently unavailable. Existing requests and applications remain accessible.'}</p>
              </div>
            )}
          </aside>
        )}

        <div className="property-details-content">

          <section className="property-details-section">
            <h2>About this property</h2>
            <p>{property.description || 'No property description has been provided.'}</p>
          </section>

          <ViewingReviews key={property.id} propertyId={property.id} />
          <section className="property-details-section">
            <h2>Amenities</h2>
            {amenityDetails.length > 0 ? (
              <ul className="property-details-amenities">
                {amenityDetails.map((amenity, index) => {
                  const presentation = getAmenityPresentation(amenity)
                  return (
                    <li key={`${presentation.key}-${index}`}>
                      <span aria-hidden="true"><Icon name={presentation.icon} size={19} /></span>
                      {presentation.label}
                    </li>
                  )
                })}
              </ul>
            ) : (
              <p>No amenities have been added yet.</p>
            )}
          </section>

          <PropertyLocationMap
            address={property.address}
            city={property.city}
            latitude={property.latitude}
            longitude={property.longitude}
            googlePlaceId={property.googlePlaceId}
          />

          {isTenant && (
            <section className="property-details-section property-listed-by" aria-labelledby="property-listed-by-title">
              <h2 id="property-listed-by-title">Listed by</h2>
              <div className="property-listed-by__profile">
                {landlordState.status === 'ready' ? (
                  <>
                    <PublicLandlordAvatar propertyId={property.id} summary={landlordState.summary} />
                    <div>
                      <strong>{landlordState.summary.displayName}</strong>
                      <p>Member since {landlordState.summary.memberSinceYear}</p>
                      <Link className="property-listed-by__link" to={`/properties/${encodeURIComponent(property.id)}/landlord`}>
                        View landlord profile <span aria-hidden="true">→</span>
                      </Link>
                    </div>
                  </>
                ) : (
                  <>
                    <span className="property-listed-by__avatar" aria-hidden="true">
                      <Icon name="user" size={22} />
                    </span>
                    <div>
                      <strong>{landlordState.status === 'loading' ? 'Loading landlord details' : 'Landlord details unavailable'}</strong>
                      {landlordState.status === 'error' && <p>This listing remains available to review.</p>}
                    </div>
                  </>
                )}
              </div>
              <LandlordContact key={property.id} propertyId={property.id} isTenant={isTenant} />
            </section>
          )}
        </div>
      </div>
    </main>
  )
}
