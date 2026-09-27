import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import Icon from '../../../shared/ui/Icons.jsx'
import {
  getProperties,
  getPropertyImages,
  getPropertyImageUrl,
} from '../services/propertyApiService.js'
import '../properties.css'

export default function PropertiesPage() {
  const [properties, setProperties] = useState([])
  const [coverImages, setCoverImages] = useState({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  const [filters, setFilters] = useState({
    search: '',
    city: '',
    maxRent: '',
    minBedrooms: '',
    minBathrooms: '',
    amenity: '',
  })

  useEffect(() => {
    let active = true

    async function loadProperties() {
      setLoading(true)
      setError('')

      try {
        const result = await getProperties({
          isAvailable: true,
        })

        if (!active) return

        setProperties(result)

        const images = {}

        await Promise.all(
          result.map(async (property) => {
            try {
              const propertyImages =
                await getPropertyImages(property.id)

              if (!propertyImages?.length) return

              const imageResult = await getPropertyImageUrl(
                property.id,
                propertyImages[0].id,
              )

              if (imageResult?.url) {
                images[property.id] = imageResult.url
              }
            } catch {
              // A missing image should not prevent the property
              // itself from being displayed.
            }
          }),
        )

        if (active) setCoverImages(images)
      } catch (err) {
        if (active) {
          setError(
            err.message || 'Unable to load properties.',
          )
        }
      } finally {
        if (active) setLoading(false)
      }
    }

    loadProperties()

    return () => {
      active = false
    }
  }, [])

  function updateFilter(event) {
    const { name, value } = event.target

    setFilters((current) => ({
      ...current,
      [name]: value,
    }))
  }

  function clearFilters() {
    setFilters({
      search: '',
      city: '',
      maxRent: '',
      minBedrooms: '',
      minBathrooms: '',
      amenity: '',
    })
  }

  const visibleProperties = useMemo(() => {
    const search = filters.search.trim().toLowerCase()
    const city = filters.city.trim().toLowerCase()
    const amenity = filters.amenity.trim().toLowerCase()

    return properties.filter((property) => {
      const amenities = property.amenities || []

      const matchesSearch =
        !search ||
        [
          property.title,
          property.description,
          property.address,
          property.city,
        ].some((value) =>
          String(value || '')
            .toLowerCase()
            .includes(search),
        )

      const matchesCity =
        !city ||
        String(property.city || '')
          .toLowerCase()
          .includes(city)

      const matchesRent =
        !filters.maxRent ||
        Number(property.monthlyRent) <=
          Number(filters.maxRent)

      const matchesBedrooms =
        !filters.minBedrooms ||
        Number(property.bedrooms) >=
          Number(filters.minBedrooms)

      const matchesBathrooms =
        !filters.minBathrooms ||
        Number(property.bathrooms) >=
          Number(filters.minBathrooms)

      const matchesAmenity =
        !amenity ||
        amenities.some((item) =>
          String(item).toLowerCase().includes(amenity),
        )

      return (
        property.isAvailable !== false &&
        matchesSearch &&
        matchesCity &&
        matchesRent &&
        matchesBedrooms &&
        matchesBathrooms &&
        matchesAmenity
      )
    })
  }, [properties, filters])

  const hasFilters = Object.values(filters).some(
    (value) => value !== '',
  )

  return (
    <main
      className="properties-page"
      aria-busy={loading}
    >
      <header className="properties-page__header">
        <div>
          <span className="properties-page__eyebrow">
            Property marketplace
          </span>

          <h1>Find your next home</h1>

          <p className="properties-page__description">
            Browse available rental properties, compare
            amenities and use RentFlow AI to find properties
            that match your preferences.
          </p>

          {!loading && (
            <p className="properties-page__count">
              {visibleProperties.length}{' '}
              {visibleProperties.length === 1
                ? 'property'
                : 'properties'}{' '}
              available
            </p>
          )}
        </div>

        <Link
          to="/modules/property-matching"
          className="property-button property-button--ai"
        >
          <Icon name="sparkles" size={18} />
          AI Property Matching
        </Link>
      </header>

      <section
        className="property-filters"
        aria-label="Property filters"
      >
        <div className="property-filters__search">
          <Icon name="search" size={19} />

          <input
            type="search"
            name="search"
            value={filters.search}
            onChange={updateFilter}
            placeholder="Search properties, addresses or locations"
            aria-label="Search properties"
          />
        </div>

        <div className="property-filters__grid">
          <label>
            <span>City</span>
            <input
              name="city"
              value={filters.city}
              onChange={updateFilter}
              placeholder="Any city"
            />
          </label>

          <label>
            <span>Maximum rent</span>
            <input
              type="number"
              min="0"
              name="maxRent"
              value={filters.maxRent}
              onChange={updateFilter}
              placeholder="Any price"
            />
          </label>

          <label>
            <span>Bedrooms</span>
            <select
              name="minBedrooms"
              value={filters.minBedrooms}
              onChange={updateFilter}
            >
              <option value="">Any</option>
              <option value="1">1+</option>
              <option value="2">2+</option>
              <option value="3">3+</option>
              <option value="4">4+</option>
            </select>
          </label>

          <label>
            <span>Bathrooms</span>
            <select
              name="minBathrooms"
              value={filters.minBathrooms}
              onChange={updateFilter}
            >
              <option value="">Any</option>
              <option value="1">1+</option>
              <option value="2">2+</option>
              <option value="3">3+</option>
            </select>
          </label>

          <label>
            <span>Amenity</span>
            <input
              name="amenity"
              value={filters.amenity}
              onChange={updateFilter}
              placeholder="Parking, Security..."
            />
          </label>
        </div>

        {hasFilters && (
          <button
            type="button"
            className="property-button property-button--quiet"
            onClick={clearFilters}
          >
            Clear filters
          </button>
        )}
      </section>

      {loading && (
        <section className="property-state">
          <div className="property-spinner" />
          <h2>Loading properties</h2>
          <p>
            Finding the latest available rental properties.
          </p>
        </section>
      )}

      {!loading && error && (
        <section
          className="property-state property-state--error"
          role="alert"
        >
          <h2>We couldn't load the properties</h2>
          <p>{error}</p>
        </section>
      )}

      {!loading &&
        !error &&
        visibleProperties.length === 0 && (
          <section className="property-state">
            <h2>No matching properties</h2>

            <p>
              Try changing your filters or use AI Property
              Matching for recommendations.
            </p>

            {hasFilters && (
              <button
                type="button"
                className="property-button property-button--primary"
                onClick={clearFilters}
              >
                Clear filters
              </button>
            )}
          </section>
        )}

      {!loading &&
        !error &&
        visibleProperties.length > 0 && (
          <section
            className="property-grid"
            aria-label="Available properties"
          >
            {visibleProperties.map((property) => (
              <article
                className="property-card"
                key={property.id}
              >
                <div className="property-card__image">
                  {coverImages[property.id] ? (
                    <img
                      src={coverImages[property.id]}
                      alt={property.title}
                    />
                  ) : (
                    <div className="property-card__placeholder">
                      <Icon name="home" size={34} />
                      <span>Property photo</span>
                    </div>
                  )}

                  <span className="property-card__status">
                    Available
                  </span>
                </div>

                <div className="property-card__body">
                  <div className="property-card__location">
                    <Icon name="location" size={16} />
                    {property.city}
                  </div>

                  <h2>{property.title}</h2>

                  <p className="property-card__address">
                    {property.address}
                  </p>

                  <div className="property-card__features">
                    <span>
                      <strong>{property.bedrooms}</strong>{' '}
                      Bedrooms
                    </span>

                    <span>
                      <strong>{property.bathrooms}</strong>{' '}
                      Bathrooms
                    </span>
                  </div>

                  {property.amenities?.length > 0 && (
                    <div className="property-card__amenities">
                      {property.amenities
                        .slice(0, 3)
                        .map((amenity) => (
                          <span key={amenity}>
                            {amenity}
                          </span>
                        ))}

                      {property.amenities.length > 3 && (
                        <span>
                          +{property.amenities.length - 3}
                        </span>
                      )}
                    </div>
                  )}

                  <div className="property-card__footer">
                    <div className="property-card__price">
                      <strong>
                        Rs.{' '}
                        {Number(
                          property.monthlyRent,
                        ).toLocaleString()}
                      </strong>
                      <span>/ month</span>
                    </div>

                    <Link
                      to={`/properties/${property.id}`}
                      className="property-button property-button--primary"
                    >
                      View Details
                    </Link>
                  </div>
                </div>
              </article>
            ))}
          </section>
        )}
    </main>
  )
}