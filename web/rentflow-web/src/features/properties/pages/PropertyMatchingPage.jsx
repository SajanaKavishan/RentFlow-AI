import { useState } from 'react'
import { Link } from 'react-router-dom'
import { matchProperties } from '../services/propertyApiService.js'
import '../properties.css'

const initialPreferences = {
  preferredCity: '',
  maximumMonthlyRent: '',
  minimumBedrooms: '',
  minimumBathrooms: '',
  preferredAmenities: '',
}

export default function PropertyMatchingPage() {
  const [form, setForm] = useState(initialPreferences)
  const [result, setResult] = useState(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  function updateField(event) {
    const { name, value } = event.target

    setForm((current) => ({
      ...current,
      [name]: value,
    }))
  }

  async function handleSubmit(event) {
    event.preventDefault()

    setLoading(true)
    setError('')
    setResult(null)

    const preferences = {
      preferredCity: form.preferredCity.trim() || null,

      maximumMonthlyRent:
        form.maximumMonthlyRent === ''
          ? null
          : Number(form.maximumMonthlyRent),

      minimumBedrooms:
        form.minimumBedrooms === ''
          ? null
          : Number(form.minimumBedrooms),

      minimumBathrooms:
        form.minimumBathrooms === ''
          ? null
          : Number(form.minimumBathrooms),

      preferredAmenities: form.preferredAmenities
        .split(',')
        .map((item) => item.trim())
        .filter(Boolean),
    }

    try {
      const response = await matchProperties(preferences)
      setResult(response)
    } catch (err) {
      setError(
        err.message ||
          'Unable to generate property recommendations.',
      )
    } finally {
      setLoading(false)
    }
  }

  function resetForm() {
    setForm(initialPreferences)
    setResult(null)
    setError('')
  }

  return (
    <main className="property-match-page">
      <Link
        to="/modules/properties"
        className="property-back-link"
      >
        ← Back to properties
      </Link>

      <header className="property-match-hero">
        <div className="property-match-hero__content">
          <span className="properties-page__eyebrow">
            RentFlow AI
          </span>

          <h1>Find your best property match</h1>

          <p>
            Tell us what you're looking for. RentFlow evaluates
            available properties using deterministic matching
            rules and our Property Matching Agent explains the
            strongest recommendations.
          </p>
        </div>

        <div className="property-match-hero__badge">
          AI Property Matching
        </div>
      </header>

      <div className="property-match-layout">
        <section className="property-preference-card">
          <div className="property-section-heading">
            <div>
              <span className="property-section-number">
                01
              </span>

              <h2>Your preferences</h2>
            </div>

            <p>
              Add as many preferences as you want.
            </p>
          </div>

          <form
            onSubmit={handleSubmit}
            className="property-preference-form"
          >
            <label className="property-form-field property-form-field--wide">
              <span>Preferred city</span>

              <input
                name="preferredCity"
                value={form.preferredCity}
                onChange={updateField}
                placeholder="e.g. Colombo"
              />
            </label>

            <label className="property-form-field">
              <span>Maximum monthly rent</span>

              <div className="property-input-prefix">
                <span>Rs.</span>

                <input
                  type="number"
                  min="0"
                  name="maximumMonthlyRent"
                  value={form.maximumMonthlyRent}
                  onChange={updateField}
                  placeholder="150000"
                />
              </div>
            </label>

            <label className="property-form-field">
              <span>Minimum bedrooms</span>

              <select
                name="minimumBedrooms"
                value={form.minimumBedrooms}
                onChange={updateField}
              >
                <option value="">Any</option>
                <option value="1">1+</option>
                <option value="2">2+</option>
                <option value="3">3+</option>
                <option value="4">4+</option>
              </select>
            </label>

            <label className="property-form-field">
              <span>Minimum bathrooms</span>

              <select
                name="minimumBathrooms"
                value={form.minimumBathrooms}
                onChange={updateField}
              >
                <option value="">Any</option>
                <option value="1">1+</option>
                <option value="2">2+</option>
                <option value="3">3+</option>
              </select>
            </label>

            <label className="property-form-field property-form-field--wide">
              <span>Preferred amenities</span>

              <input
                name="preferredAmenities"
                value={form.preferredAmenities}
                onChange={updateField}
                placeholder="Parking, Air Conditioning, Security"
              />

              <small>
                Separate multiple amenities with commas.
              </small>
            </label>

            <div className="property-match-actions">
              <button
                type="submit"
                className="property-button property-button--ai property-match-submit"
                disabled={loading}
              >
                {loading
                  ? 'Finding your matches...'
                  : 'Find My Matches'}
              </button>

              <button
                type="button"
                className="property-button property-button--quiet property-reset-button"
                onClick={resetForm}
                disabled={loading}
              >
                Reset
              </button>
            </div>
          </form>
        </section>

        <aside className="property-ai-info">
          <span className="property-section-number">
            AI
          </span>

          <h2>How matching works</h2>

          <p>
            RentFlow compares your preferences against currently
            available properties.
          </p>

          <div className="property-ai-step">
            <strong>1</strong>
            <div>
              <h3>Compare</h3>
              <p>
                City, rent, bedrooms, bathrooms and amenities
                are evaluated.
              </p>
            </div>
          </div>

          <div className="property-ai-step">
            <strong>2</strong>
            <div>
              <h3>Score</h3>
              <p>
                Deterministic rules calculate a transparent
                match score.
              </p>
            </div>
          </div>

          <div className="property-ai-step">
            <strong>3</strong>
            <div>
              <h3>Explain</h3>
              <p>
                The Property Matching Agent explains why each
                recommendation fits.
              </p>
            </div>
          </div>
        </aside>
      </div>

      {error && (
        <section
          className="property-match-error"
          role="alert"
        >
          <strong>We couldn't generate your matches.</strong>
          <p>{error}</p>
        </section>
      )}

      {loading && (
        <section className="property-state property-match-loading">
          <div className="property-spinner" />
          <h2>Finding your best matches</h2>
          <p>
            RentFlow AI is analyzing the available properties.
          </p>
        </section>
      )}

      {!loading && result && (
        <section className="property-match-results">
          <div className="property-match-results__header">
            <div>
              <span className="properties-page__eyebrow">
                Recommendations
              </span>

              <h2>Your property matches</h2>

              <p>{result.summary}</p>
            </div>

            <div className="property-match-results__count">
              {result.matches?.length || 0}{' '}
              {(result.matches?.length || 0) === 1
                ? 'match'
                : 'matches'}
            </div>
          </div>

          {!result.matches?.length ? (
            <section className="property-state">
              <h2>No recommendations found</h2>

              <p>
                Try adjusting your budget, location or property
                requirements.
              </p>
            </section>
          ) : (
            <div className="property-match-list">
              {result.matches.map((property, index) => (
                <article
                  className="property-match-card"
                  key={property.propertyId}
                >
                  <div className="property-match-card__rank">
                    #{index + 1}
                  </div>

                  <div className="property-match-card__main">
                    <div className="property-match-card__heading">
                      <div>
                        <span className="property-match-card__city">
                          {property.city}
                        </span>

                        <h3>{property.title}</h3>
                      </div>

                      <div className="property-match-score">
                        <strong>
                          {property.matchScore}
                        </strong>
                        <span>/100</span>
                        <small>Match score</small>
                      </div>
                    </div>

                    <div className="property-match-card__facts">
                      <span>
                        Rs.{' '}
                        {Number(
                          property.monthlyRent,
                        ).toLocaleString()}
                        /month
                      </span>

                      <span>
                        {property.bedrooms} bedrooms
                      </span>

                      <span>
                        {property.bathrooms} bathrooms
                      </span>
                    </div>

                    {property.amenities?.length > 0 && (
                      <div className="property-card__amenities">
                        {property.amenities.map(
                          (amenity) => (
                            <span key={amenity}>
                              {amenity}
                            </span>
                          ),
                        )}
                      </div>
                    )}

                    {property.matchReasons?.length > 0 && (
                      <div className="property-match-reasons">
                        <h4>Why this property matches</h4>

                        <ul>
                          {property.matchReasons.map(
                            (reason) => (
                              <li key={reason}>
                                <span
                                  className="property-match-check"
                                  aria-hidden="true"
                                >
                                  ✓
                                </span>

                                {reason}
                              </li>
                            ),
                          )}
                        </ul>
                      </div>
                    )}

                    <div className="property-match-card__footer">
                      <Link
                        to={`/properties/${property.propertyId}`}
                        className="property-button property-button--primary"
                      >
                        View Property
                      </Link>
                    </div>
                  </div>
                </article>
              ))}
            </div>
          )}
        </section>
      )}
    </main>
  )
}