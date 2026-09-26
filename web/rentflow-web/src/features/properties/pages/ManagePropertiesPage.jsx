import { useEffect, useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import {
  deleteProperty,
  getMyProperties,
  updateProperty,
} from '../services/propertyApiService.js'
import PropertyImageGallery from '../components/PropertyImageGallery.jsx'
import Icon from '../../../shared/ui/Icons.jsx'
import '../properties.css'

const PAGE_SIZE = 6

export default function ManagePropertiesPage() {
  const location = useLocation()
  const navigate = useNavigate()
  const [properties, setProperties] = useState([])
  const [searchQuery, setSearchQuery] = useState('')
  const [currentPage, setCurrentPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [message, setMessage] = useState(location.state?.propertyMessage || '')

  async function loadProperties() {
    setLoading(true)
    setError('')

    try {
      const result = await getMyProperties()
      setProperties(result)
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    let active = true
    getMyProperties()
      .then((result) => {
        if (active) setProperties(result)
      })
      .catch((err) => {
        if (active) setError(err.message)
      })
      .finally(() => {
        if (active) setLoading(false)
      })
    return () => { active = false }
  }, [])

  useEffect(() => {
    if (!location.state?.propertyMessage) return
    navigate(`${location.pathname}${location.search}`, { replace: true, state: null })
  }, [location.pathname, location.search, location.state, navigate])

  async function handleAvailability(property) {
    setError('')
    setMessage('')

    try {
      await updateProperty(property.id, {
        title: property.title,
        description: property.description,
        address: property.address,
        city: property.city,
        monthlyRent: Number(property.monthlyRent),
        bedrooms: Number(property.bedrooms),
        bathrooms: Number(property.bathrooms),
        isAvailable: !property.isAvailable,
        amenities: property.amenities || [],
      })

      setMessage(
        property.isAvailable
          ? 'Property marked as unavailable.'
          : 'Property marked as available.',
      )

      await loadProperties()
    } catch (err) {
      setError(err.message)
    }
  }

  async function handleDelete(propertyId) {
    const confirmed = window.confirm(
      'Are you sure you want to permanently delete this property?',
    )

    if (!confirmed) return

    setError('')
    setMessage('')

    try {
      await deleteProperty(propertyId)

      setMessage('Property deleted successfully.')
      await loadProperties()
    } catch (err) {
      setError(err.message)
    }
  }

  function handleSearchChange(event) {
    setSearchQuery(event.target.value)
    setCurrentPage(1)
  }

  function clearSearch() {
    setSearchQuery('')
    setCurrentPage(1)
  }

  const normalizedSearch = searchQuery.trim().toLocaleLowerCase()
  const visibleProperties = normalizedSearch
    ? properties.filter((property) =>
        [property.title, property.city].some((value) =>
          value?.toLocaleLowerCase().includes(normalizedSearch),
        ),
      )
    : properties
  const totalPages = Math.ceil(visibleProperties.length / PAGE_SIZE)
  const activePage = Math.min(currentPage, Math.max(totalPages, 1))
  const paginatedProperties = visibleProperties.slice(
    (activePage - 1) * PAGE_SIZE,
    activePage * PAGE_SIZE,
  )
  const propertyCountLabel = loading
    ? 'Loading properties...'
    : error && properties.length === 0
      ? 'Property count unavailable'
      : `${properties.length} ${properties.length === 1 ? 'property' : 'properties'} listed`

  return (
    <main className="manage-properties-page">
      <header className="manage-properties-header">
        <div>
          <h1>My Properties</h1>
          <p>{propertyCountLabel}</p>
        </div>

        <Link
          to="/properties/new"
          className="property-button property-button--primary"
        >
          + Add Property
        </Link>
      </header>

      {error && properties.length > 0 && (
        <div className="property-management-alert property-management-alert--error" role="alert">
          <strong>Something went wrong</strong>
          <span>{error}</span>
        </div>
      )}

      {message && (
        <div className="property-management-alert property-management-alert--success" role="status">
          <strong>Success</strong>
          <span>{message}</span>
        </div>
      )}

      <section className="managed-property-section" aria-label="Owned properties">
        {!loading && properties.length > 0 && (
          <label className="managed-property-search">
            <Icon name="search" size={18} />
            <span className="visually-hidden">Search properties by title or city</span>
            <input
              type="search"
              value={searchQuery}
              onChange={handleSearchChange}
              placeholder="Search by property name or city..."
            />
            {normalizedSearch && (
              <span className="managed-property-search__count">
                {visibleProperties.length} of {properties.length}
              </span>
            )}
          </label>
        )}

        {loading ? (
          <div className="property-state" role="status">
            <span className="property-spinner" aria-hidden="true" />
            <h3>Loading properties...</h3>
            <p>Retrieving your owned property portfolio.</p>
          </div>
        ) : error && properties.length === 0 ? (
          <div className="property-state property-state--error" role="alert">
            <span className="property-state__icon property-state__icon--error" aria-hidden="true">
              <Icon name="alert" size={26} />
            </span>
            <h3>We could not load your properties</h3>
            <p>{error}</p>
            <button
              type="button"
              className="property-button property-button--primary"
              onClick={loadProperties}
            >
              Try again
            </button>
          </div>
        ) : properties.length === 0 ? (
          <div className="property-state">
            <span className="property-state__icon" aria-hidden="true">
              <Icon name="building" size={27} />
            </span>
            <h3>No properties yet</h3>
            <p>
              Add your first property to start managing its details and
              landlord workflows.
            </p>
            <Link
              to="/properties/new"
              className="property-button property-button--primary"
            >
              Add your first property
            </Link>
          </div>
        ) : visibleProperties.length === 0 ? (
          <div className="property-state property-state--compact">
            <span className="property-state__icon" aria-hidden="true">
              <Icon name="search" size={25} />
            </span>
            <h3>No matching properties</h3>
            <p>Try a different property title or city.</p>
            <button
              type="button"
              className="property-button property-button--quiet"
              onClick={clearSearch}
            >
              Clear search
            </button>
          </div>
        ) : (
          <>
            <div className="managed-property-grid">
            {paginatedProperties.map((property) => (
              <article
                key={property.id}
                className="managed-property-card"
              >
                <div className="managed-property-card__images">
                  <PropertyImageGallery
                    propertyId={property.id}
                    variant="cover"
                    alt={property.title}
                  />
                  <span
                    className={
                      property.isAvailable
                        ? 'managed-property-status managed-property-status--available'
                        : 'managed-property-status managed-property-status--unavailable'
                    }
                  >
                    {property.isAvailable
                      ? 'Available'
                      : 'Unavailable'}
                  </span>
                </div>

                <div className="managed-property-card__body">
                  <div className="managed-property-card__top">
                    <span className="managed-property-city">
                      {property.city}
                    </span>
                  </div>

                  <h3>{property.title}</h3>

                  <p className="managed-property-address">
                    {[property.address, property.city]
                      .filter(Boolean)
                      .join(', ')}
                  </p>

                  <div className="managed-property-price">
                    <strong>
                      Rs.{' '}
                      {Number(
                        property.monthlyRent,
                      ).toLocaleString()}
                    </strong>
                    <span>per month</span>
                  </div>

                  <dl className="managed-property-facts">
                    <div>
                      <dt>Bedrooms</dt>
                      <dd>{property.bedrooms}</dd>
                    </div>

                    <div>
                      <dt>Bathrooms</dt>
                      <dd>{property.bathrooms}</dd>
                    </div>
                  </dl>

                  <div className="managed-property-workflows">
                    <Link
                      className="property-workflow-link"
                      to={`/properties/${encodeURIComponent(property.id)}/viewing-requests`}
                    >
                      <Icon name="calendar" size={18} />
                      <span>Viewing Requests</span>
                      <Icon name="arrow" size={16} />
                    </Link>

                    <Link
                      className="property-workflow-link"
                      to={`/properties/${encodeURIComponent(property.id)}/rental-applications`}
                    >
                      <Icon name="document" size={18} />
                      <span>Rental Applications</span>
                      <Icon name="arrow" size={16} />
                    </Link>
                  </div>

                  <div className="managed-property-actions">
                    <Link
                      className="property-button property-button--quiet"
                      to={`/properties/${encodeURIComponent(property.id)}`}
                    >
                      <Icon name="eye" size={17} />
                      View property
                    </Link>

                    <Link
                      className="property-button property-button--quiet"
                      to={`/properties/${encodeURIComponent(property.id)}/edit`}
                    >
                      Edit property
                    </Link>

                    <button
                      type="button"
                      className="property-button property-button--quiet"
                      onClick={() =>
                        handleAvailability(property)
                      }
                    >
                      {property.isAvailable
                        ? 'Mark unavailable'
                        : 'Mark available'}
                    </button>

                    <button
                      type="button"
                      className="property-delete-button"
                      onClick={() =>
                        handleDelete(property.id)
                      }
                    >
                      Delete
                    </button>
                  </div>
                </div>
              </article>
            ))}
            </div>

            {totalPages > 1 && (
              <nav className="managed-property-pagination" aria-label="Property pagination">
                <button
                  type="button"
                  onClick={() => setCurrentPage(activePage - 1)}
                  disabled={activePage === 1}
                >
                  Previous
                </button>

                <div className="managed-property-pagination__pages">
                  {Array.from({ length: totalPages }, (_, index) => index + 1).map((page) => (
                    <button
                      key={page}
                      type="button"
                      aria-label={`Page ${page}`}
                      aria-current={page === activePage ? 'page' : undefined}
                      onClick={() => setCurrentPage(page)}
                    >
                      {page}
                    </button>
                  ))}
                </div>

                <button
                  type="button"
                  onClick={() => setCurrentPage(activePage + 1)}
                  disabled={activePage === totalPages}
                >
                  Next
                </button>
              </nav>
            )}
          </>
        )}
      </section>
    </main>
  )
}
