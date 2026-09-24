import { useEffect, useState } from 'react'
import {
  createProperty,
  deleteProperty,
  getMyProperties,
  updateProperty,
  uploadPropertyImages,
} from '../services/propertyApiService.js'
import PropertyImageGallery from '../components/PropertyImageGallery.jsx'
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
    loadProperties()
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
  }

  function beginEdit(property) {
    setEditingId(property.id)
    setForm(propertyToForm(property))

    // Clear files from a previous create/edit operation.
    // Existing property images are loaded separately.
    setFiles([])

    setError('')
    setMessage('')

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

  return (
    <main className="manage-properties-page">
      <header className="manage-properties-hero">
        <div>
          <span className="properties-page__eyebrow">
            Property Management
          </span>

          <h1>Manage your properties</h1>

          <p>
            Create and maintain rental listings, upload property
            photos and control listing availability.
          </p>
        </div>

        <div className="manage-properties-summary">
          <strong>{properties.length}</strong>
          <span>
            {properties.length === 1 ? 'Property' : 'Properties'}
          </span>
        </div>
      </header>

      {error && (
        <div className="property-management-alert property-management-alert--error">
          <strong>Something went wrong</strong>
          <span>{error}</span>
        </div>
      )}

      {message && (
        <div className="property-management-alert property-management-alert--success">
          <strong>Success</strong>
          <span>{message}</span>
        </div>
      )}

      <section className="property-editor-card">
        <div className="property-editor-heading">
          <div>
            <span className="property-section-number">
              {editingId ? 'EDIT' : 'NEW'}
            </span>

            <h2>
              {editingId
                ? 'Edit property'
                : 'Register a property'}
            </h2>

            <p>
              {editingId
                ? 'Update the listing details or add more photos.'
                : 'Add the details tenants need to discover your property.'}
            </p>
          </div>

          {editingId && (
            <button
              type="button"
              className="property-button property-button--quiet"
              onClick={resetEditor}
            >
              Cancel editing
            </button>
          )}
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
              placeholder="Modern Apartment in Colombo"
            />
          </label>

          <label className="property-form-field property-form-field--wide">
            <span>Description</span>

            <textarea
              required
              name="description"
              value={form.description}
              onChange={updateField}
              placeholder="Describe the property, location and key features..."
              rows="4"
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
              <small>
                Tenants can discover this property while enabled.
              </small>
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

      <section className="managed-property-section">
        <div className="managed-property-section__heading">
          <div>
            <span className="properties-page__eyebrow">
              Your portfolio
            </span>

            <h2>Properties</h2>
          </div>

          <span>
            {properties.filter(
              (property) => property.isAvailable,
            ).length}{' '}
            available
          </span>
        </div>

        {loading ? (
          <div className="property-state">
            <h3>Loading properties...</h3>
          </div>
        ) : properties.length === 0 ? (
          <div className="property-state">
            <h3>No properties yet</h3>
            <p>
              Register your first property using the form above.
            </p>
          </div>
        ) : (
          <div className="managed-property-grid">
            {properties.map((property) => (
              <article
                key={property.id}
                className="managed-property-card"
              >
                <div className="managed-property-card__images">
                  <PropertyImageGallery
                    propertyId={property.id}
                  />
                </div>

                <div className="managed-property-card__top">
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

                  <span className="managed-property-city">
                    {property.city}
                  </span>
                </div>

                <h3>{property.title}</h3>

                <p className="managed-property-address">
                  {property.address}
                </p>

                <div className="managed-property-price">
                  <strong>
                    Rs.{' '}
                    {Number(
                      property.monthlyRent,
                    ).toLocaleString()}
                  </strong>
                  <span>/month</span>
                </div>

                <div className="managed-property-facts">
                  <span>
                    {property.bedrooms} bedroom
                    {property.bedrooms === 1 ? '' : 's'}
                  </span>

                  <span>
                    {property.bathrooms} bathroom
                    {property.bathrooms === 1 ? '' : 's'}
                  </span>
                </div>

                {property.amenities?.length > 0 && (
                  <div className="property-card__amenities">
                    {property.amenities
                      .slice(0, 4)
                      .map((amenity) => (
                        <span key={amenity}>
                          {amenity}
                        </span>
                      ))}
                  </div>
                )}

                <div className="managed-property-actions">
                  <button
                    type="button"
                    className="property-button property-button--primary"
                    onClick={() => beginEdit(property)}
                  >
                    Edit
                  </button>

                  <button
                    type="button"
                    className="property-button property-button--quiet"
                    onClick={() =>
                      handleAvailability(property)
                    }
                  >
                    {property.isAvailable
                      ? 'Mark Unavailable'
                      : 'Mark Available'}
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
              </article>
            ))}
          </div>
        )}
      </section>
    </main>
  )
}