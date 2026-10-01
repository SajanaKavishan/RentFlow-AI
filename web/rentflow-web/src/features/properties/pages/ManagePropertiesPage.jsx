import { useEffect, useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { getMyProperties } from '../services/propertyApiService.js'
import PropertyImageGallery from '../components/PropertyImageGallery.jsx'
import Icon from '../../../shared/ui/Icons.jsx'
import { formatPropertyArea } from '../propertyArea.js'
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
  const [toast, setToast] = useState(() => location.state?.propertyMessage
    ? { tone: 'success', message: location.state.propertyMessage }
    : null)

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

  useEffect(() => {
    if (!toast) return undefined
    const timer = window.setTimeout(() => setToast(null), 3000)
    return () => window.clearTimeout(timer)
  }, [toast])

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
                <Link
                  className="managed-property-card__primary"
                  to={`/properties/${encodeURIComponent(property.id)}`}
                  aria-label="View property"
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
                    <div className="managed-property-card__summary">
                      <div>
                        <h3>{property.title}</h3>
                        <p className="managed-property-address">
                          <Icon name="pin" size={15} />
                          <span>{[property.address, property.city]
                            .filter(Boolean)
                            .join(', ')}</span>
                        </p>
                      </div>

                      <div className="managed-property-price">
                        <strong>
                          Rs.{' '}
                          {Number(
                            property.monthlyRent,
                          ).toLocaleString()}
                        </strong>
                        <span>/month</span>
                      </div>
                    </div>

                    <dl className="managed-property-facts">
                      <div>
                        <Icon name="bed" size={17} />
                        <dt className="visually-hidden">Bedrooms</dt>
                        <dd>{property.bedrooms} {Number(property.bedrooms) === 1 ? 'bed' : 'beds'}</dd>
                      </div>

                      <div>
                        <Icon name="bath" size={17} />
                        <dt className="visually-hidden">Bathrooms</dt>
                        <dd>{property.bathrooms} {Number(property.bathrooms) === 1 ? 'bath' : 'baths'}</dd>
                      </div>

                      {property.area && (
                        <div className="managed-property-facts__area">
                          <Icon name="ruler" size={17} />
                          <dt className="visually-hidden">Property size</dt>
                          <dd>{formatPropertyArea(property.area, property.areaUnit)}</dd>
                        </div>
                      )}
                    </dl>
                  </div>
                </Link>

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
