import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  createProperty,
  deleteProperty,
  getMyProperties,
  updateProperty,
  uploadPropertyImages,
} from '../services/propertyApiService.js'
import PropertyImageGallery from '../components/PropertyImageGallery.jsx'
import Icon from '../../../shared/ui/Icons.jsx'
import '../properties.css'

const initialForm = {
  title: '',
  description: '',
  address: '',
  city: '',
  monthlyRent: '',
  bedrooms: '',
  bathrooms: '',
  amenities: '',
  isAvailable: true,
}

function propertyToForm(property) {
  return {
    title: property.title || '',
    description: property.description || '',
    address: property.address || '',
    city: property.city || '',
    monthlyRent: property.monthlyRent ?? '',
    bedrooms: property.bedrooms ?? '',
    bathrooms: property.bathrooms ?? '',
    amenities: (property.amenities || []).join(', '),
    isAvailable: property.isAvailable ?? true,
  }
}

function formToRequest(form) {
  return {
    title: form.title.trim(),
    description: form.description.trim(),
    address: form.address.trim(),
    city: form.city.trim(),
    monthlyRent: Number(form.monthlyRent),
    bedrooms: Number(form.bedrooms),
    bathrooms: Number(form.bathrooms),
    isAvailable: Boolean(form.isAvailable),
    amenities: form.amenities
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean),
  }
}

export default function ManagePropertiesPage() {
  const [properties, setProperties] = useState([])
  const [form, setForm] = useState(initialForm)
  const [files, setFiles] = useState([])
  const [editingId, setEditingId] = useState(null)
  const [editorOpen, setEditorOpen] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

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

  function updateField(event) {
    const { name, value, type, checked } = event.target

    setForm((current) => ({
      ...current,
      [name]: type === 'checkbox' ? checked : value,
    }))
  }

  function resetEditor() {
    setForm(initialForm)
    setFiles([])
    setEditingId(null)
    setEditorOpen(false)
  }

  function beginCreate() {
    setForm(initialForm)
    setFiles([])
    setEditingId(null)
    setError('')
    setMessage('')
    setEditorOpen(true)
  }

  function beginEdit(property) {
    setEditingId(property.id)
    setForm(propertyToForm(property))

    // Clear files from a previous create/edit operation.
    // Existing property images are loaded separately.
    setFiles([])

    setError('')
    setMessage('')
    setEditorOpen(true)

    window.scrollTo({
      top: 0,
      behavior: 'smooth',
    })
  }

  async function handleSubmit(event) {
    event.preventDefault()

    setSaving(true)
    setError('')
    setMessage('')

    try {
      const request = formToRequest(form)

      if (editingId) {
        await updateProperty(editingId, request)

        // Only upload newly selected photos.
        if (files.length > 0) {
          await uploadPropertyImages(editingId, files)
        }

        setMessage(
          files.length > 0
            ? `Property updated and ${files.length} new photo(s) uploaded.`
            : 'Property updated successfully.',
        )
      } else {
        const property = await createProperty(request)

        if (files.length > 0) {
          await uploadPropertyImages(property.id, files)
        }

        setMessage(
          files.length > 0
            ? `Property created with ${files.length} photo(s).`
            : 'Property created successfully.',
        )
      }

      resetEditor()
      await loadProperties()
    } catch (err) {
      setError(err.message)
    } finally {
      setSaving(false)
    }
  }

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

      if (editingId === propertyId) {
        resetEditor()
      }

      setMessage('Property deleted successfully.')
      await loadProperties()
    } catch (err) {
      setError(err.message)
    }
  }

  const normalizedSearch = searchQuery.trim().toLocaleLowerCase()
  const visibleProperties = normalizedSearch
    ? properties.filter((property) =>
        [property.title, property.city].some((value) =>
          value?.toLocaleLowerCase().includes(normalizedSearch),
        ),
      )
    : properties
  const availableCount = properties.filter(
    (property) => property.isAvailable,
  ).length

  return (
    <main className="manage-properties-page">
      <header className="manage-properties-hero">
        <div className="manage-properties-hero__copy">
          <span className="properties-page__eyebrow">
            Landlord workspace
          </span>

          <h1>Manage Properties</h1>

          <p>
            Keep your portfolio details, availability and property
            workflows up to date.
          </p>
        </div>

        <div className="manage-properties-hero__actions">
          <div className="manage-properties-summary" aria-label={`${properties.length} total properties, ${availableCount} available`}>
            <strong>{properties.length}</strong>
            <span>Total properties</span>
            <small>{availableCount} available</small>
          </div>

          <button
            type="button"
            className="property-button property-button--primary"
            onClick={beginCreate}
            aria-expanded={editorOpen && !editingId}
            aria-controls="property-editor"
          >
            Add Property
          </button>
        </div>
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

      {editorOpen && (
        <section className="property-editor-card" id="property-editor">
          <div className="property-editor-heading">
            <div>
              <span className="property-section-number">
                {editingId ? 'Edit property' : 'New property'}
              </span>

              <h2>
                {editingId
                  ? `Update ${form.title || 'property'}`
                  : 'Add to your portfolio'}
              </h2>

              <p>
                {editingId
                  ? 'Update the property details or upload additional photos.'
                  : 'Enter the property details and add photos when you are ready.'}
              </p>
            </div>

            <button
              type="button"
              className="property-button property-button--quiet"
              onClick={resetEditor}
              disabled={saving}
            >
              {editingId ? 'Cancel editing' : 'Close'}
            </button>
          </div>

          <form
            onSubmit={handleSubmit}
            className="property-editor-form"
          >
          <label className="property-form-field property-form-field--wide">
            <span>Property title</span>

            <input
              required
              name="title"
              value={form.title}
              onChange={updateField}
              placeholder="Harbour View Residence"
            />
          </label>

          <label className="property-form-field property-form-field--wide">
            <span>Description</span>

            <textarea
              required
              name="description"
              value={form.description}
              onChange={updateField}
              placeholder="Describe the property and its key features..."
              rows="3"
            />
          </label>

          <label className="property-form-field property-form-field--wide">
            <span>Address</span>

            <input
              required
              name="address"
              value={form.address}
              onChange={updateField}
              placeholder="Property address"
            />
          </label>

          <label className="property-form-field">
            <span>City</span>

            <input
              required
              name="city"
              value={form.city}
              onChange={updateField}
              placeholder="Colombo"
            />
          </label>

          <label className="property-form-field">
            <span>Monthly rent</span>

            <div className="property-input-prefix">
              <span>Rs.</span>

              <input
                required
                type="number"
                min="0"
                name="monthlyRent"
                value={form.monthlyRent}
                onChange={updateField}
                placeholder="85000"
              />
            </div>
          </label>

          <label className="property-form-field">
            <span>Bedrooms</span>

            <input
              required
              type="number"
              min="0"
              name="bedrooms"
              value={form.bedrooms}
              onChange={updateField}
              placeholder="2"
            />
          </label>

          <label className="property-form-field">
            <span>Bathrooms</span>

            <input
              required
              type="number"
              min="0"
              name="bathrooms"
              value={form.bathrooms}
              onChange={updateField}
              placeholder="2"
            />
          </label>

          <label className="property-form-field property-form-field--wide">
            <span>Amenities</span>

            <input
              name="amenities"
              value={form.amenities}
              onChange={updateField}
              placeholder="Parking, Air Conditioning, Security"
            />

            <small>
              Separate multiple amenities with commas.
            </small>
          </label>

          <div className="property-photo-field">
            {editingId && (
              <div className="property-existing-images">
                <strong>Current photos</strong>

                <p>
                  These photos are already saved with this property.
                </p>

                <PropertyImageGallery
                  propertyId={editingId}
                />
              </div>
            )}

            <div>
              <strong>
                {editingId
                  ? 'Add more property photos'
                  : 'Property photos'}
              </strong>

              <p>
                {editingId
                  ? 'Select new images only if you want to add more photos.'
                  : 'Select multiple images to upload them together.'}
              </p>
            </div>

            <label className="property-photo-picker">
              <span>
                {files.length > 0
                  ? `${files.length} photo${
                      files.length === 1 ? '' : 's'
                    } selected`
                  : editingId
                    ? 'Choose additional photos'
                    : 'Choose property photos'}
              </span>

              <input
                type="file"
                accept="image/jpeg,image/png"
                multiple
                onChange={(event) =>
                  setFiles(
                    Array.from(event.target.files || []),
                  )
                }
              />
            </label>

            {files.length > 0 && (
              <div className="property-selected-files">
                {files.map((file) => (
                  <span key={`${file.name}-${file.size}`}>
                    {file.name}
                  </span>
                ))}
              </div>
            )}
          </div>

          <label className="property-availability-control">
            <input
              type="checkbox"
              name="isAvailable"
              checked={form.isAvailable}
              onChange={updateField}
            />

            <span>
              <strong>Available for rent</strong>
              <small>The property is currently accepting enquiries.</small>
            </span>
          </label>

          <div className="property-editor-actions">
            <button
              type="submit"
              className="property-button property-button--primary"
              disabled={saving}
            >
              {saving
                ? editingId
                  ? 'Saving changes...'
                  : 'Creating property...'
                : editingId
                  ? 'Save Changes'
                  : 'Create Property'}
            </button>

            {(editingId ||
              Object.values(form).some(
                (value) =>
                  typeof value === 'string' && value !== '',
              )) && (
              <button
                type="button"
                className="property-button property-button--quiet"
                onClick={resetEditor}
                disabled={saving}
              >
                Clear
              </button>
            )}
          </div>
          </form>
        </section>
      )}

      <section className="managed-property-section">
        <div className="managed-property-section__heading">
          <div>
            <span className="properties-page__eyebrow">
              Your portfolio
            </span>

            <h2>Property portfolio</h2>
          </div>

          <span>
            {availableCount} available
          </span>
        </div>

        {!loading && properties.length > 0 && (
          <label className="managed-property-search">
            <Icon name="search" size={18} />
            <span className="visually-hidden">Search properties by title or city</span>
            <input
              type="search"
              value={searchQuery}
              onChange={(event) => setSearchQuery(event.target.value)}
              placeholder="Search by property title or city"
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
            <button
              type="button"
              className="property-button property-button--primary"
              onClick={beginCreate}
            >
              Add your first property
            </button>
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
              onClick={() => setSearchQuery('')}
            >
              Clear search
            </button>
          </div>
        ) : (
          <div className="managed-property-grid">
            {visibleProperties.map((property) => (
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

                    <button
                      type="button"
                      className="property-button property-button--quiet"
                      onClick={() => beginEdit(property)}
                    >
                      Edit property
                    </button>

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
        )}
      </section>
    </main>
  )
}
