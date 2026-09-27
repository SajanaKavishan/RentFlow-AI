import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import PropertyImageGallery from '../components/PropertyImageGallery.jsx'
import {
  createProperty,
  getMyProperties,
  updateProperty,
  uploadPropertyImages,
} from '../services/propertyApiService.js'
import Icon from '../../../shared/ui/Icons.jsx'
import { PROPERTY_AREA_UNITS } from '../propertyArea.js'
import '../properties.css'

const MANAGE_PROPERTIES_PATH = '/modules/manage-properties'
const UNSAVED_MESSAGE = 'You have unsaved property changes. Leave without saving them?'
const STEPS = [
  { title: 'Basic Details', description: 'Name and locate the property.' },
  { title: 'Property Details', description: 'Add rent, rooms, size and amenities.' },
  { title: 'Photos & Availability', description: 'Finish the listing and publish.' },
]

const initialForm = {
  title: '',
  description: '',
  address: '',
  city: '',
  monthlyRent: '',
  bedrooms: '',
  bathrooms: '',
  area: '',
  areaUnit: 'sqft',
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
    area: property.area ?? '',
    areaUnit: property.areaUnit || 'sqft',
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
    area: Number(form.area),
    areaUnit: form.areaUnit,
    isAvailable: Boolean(form.isAvailable),
    amenities: form.amenities
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean),
  }
}

function formSnapshot(form) {
  const normalizeNumber = (value) => value === '' ? '' : Number(value)

  return JSON.stringify({
    title: form.title.trim(),
    description: form.description.trim(),
    address: form.address.trim(),
    city: form.city.trim(),
    monthlyRent: normalizeNumber(form.monthlyRent),
    bedrooms: normalizeNumber(form.bedrooms),
    bathrooms: normalizeNumber(form.bathrooms),
    area: normalizeNumber(form.area),
    areaUnit: form.areaUnit,
    amenities: form.amenities
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean),
    isAvailable: Boolean(form.isAvailable),
  })
}

function validateStep(step, form) {
  const errors = {}

  if (step === 0) {
    for (const [field, label] of [
      ['title', 'Property title'],
      ['description', 'Description'],
      ['address', 'Address'],
      ['city', 'City'],
    ]) {
      if (!form[field].trim()) errors[field] = `${label} is required.`
    }
  }

  if (step === 1) {
    for (const [field, message] of [
      ['monthlyRent', 'Enter a valid monthly rent.'],
      ['bedrooms', 'Enter a valid number of bedrooms.'],
      ['bathrooms', 'Enter a valid number of bathrooms.'],
      ['area', 'Enter a valid property or land size.'],
    ]) {
      const value = form[field]
      const numericValue = Number(value)
      if (value === '' || !Number.isFinite(numericValue)
        || numericValue < 0 || (field === 'area' && numericValue <= 0)) {
        errors[field] = message
      }
    }
  }

  return errors
}

function PropertyField({ children, error, name, label, wide = false }) {
  return (
    <div className={`property-form-field${wide ? ' property-form-field--wide' : ''}`}>
      <label htmlFor={name}>{label}</label>
      {children}
      {error && <small className="property-field-error" id={`${name}-error`}>{error}</small>}
    </div>
  )
}

export default function PropertyFormPage() {
  const { propertyId } = useParams()
  const navigate = useNavigate()
  const isEditing = Boolean(propertyId)
  const [form, setForm] = useState(initialForm)
  const [files, setFiles] = useState([])
  const [initialSnapshot, setInitialSnapshot] = useState(formSnapshot(initialForm))
  const [ownedPropertyId, setOwnedPropertyId] = useState(null)
  const [step, setStep] = useState(0)
  const [fieldErrors, setFieldErrors] = useState({})
  const [status, setStatus] = useState(isEditing ? 'loading' : 'ready')
  const [loadAttempt, setLoadAttempt] = useState(0)
  const [error, setError] = useState('')
  const [saving, setSaving] = useState(false)
  const stepHeadingRef = useRef(null)

  useEffect(() => {
    if (!isEditing) return undefined

    let active = true

    getMyProperties()
      .then((properties) => {
        if (!active) return
        const property = Array.isArray(properties)
          ? properties.find((item) =>
              typeof item?.id === 'string'
              && item.id.toLowerCase() === propertyId.toLowerCase())
          : null

        if (!property) {
          setStatus('unavailable')
          return
        }

        const populatedForm = propertyToForm(property)
        setForm(populatedForm)
        setInitialSnapshot(formSnapshot(populatedForm))
        setOwnedPropertyId(property.id)
        setStatus('ready')
      })
      .catch((err) => {
        if (!active) return
        setError(err instanceof Error ? err.message : 'Unable to load your property.')
        setStatus('error')
      })

    return () => { active = false }
  }, [isEditing, loadAttempt, propertyId])

  const isDirty = status === 'ready' && (
    formSnapshot(form) !== initialSnapshot || files.length > 0
  )

  useEffect(() => {
    if (!isDirty) return undefined

    const warnBeforeUnload = (event) => {
      event.preventDefault()
      event.returnValue = ''
    }

    const warnBeforeLinkNavigation = (event) => {
      if (event.defaultPrevented || event.button !== 0
        || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

      const link = event.target.closest?.('a[href]')
      if (!link || link.target === '_blank' || link.hasAttribute('download')) return

      const destination = new URL(link.href, window.location.href)
      if (destination.href === window.location.href) return

      if (!window.confirm(UNSAVED_MESSAGE)) {
        event.preventDefault()
        event.stopPropagation()
      }
    }

    window.addEventListener('beforeunload', warnBeforeUnload)
    document.addEventListener('click', warnBeforeLinkNavigation, true)
    return () => {
      window.removeEventListener('beforeunload', warnBeforeUnload)
      document.removeEventListener('click', warnBeforeLinkNavigation, true)
    }
  }, [isDirty])

  useEffect(() => {
    if (status === 'ready') stepHeadingRef.current?.focus()
  }, [status, step])

  const pageTitle = isEditing ? 'Edit Property' : 'Add Property'
  const pageDescription = isEditing
    ? 'Update the listing details and add new property photos.'
    : 'Create a complete listing in three short steps.'
  const progressLabel = useMemo(() => `Step ${step + 1} of ${STEPS.length}`, [step])

  function updateField(event) {
    const { name, value, type, checked } = event.target
    setForm((current) => ({
      ...current,
      [name]: type === 'checkbox' ? checked : value,
    }))
    setFieldErrors((current) => {
      if (!current[name]) return current
      const next = { ...current }
      delete next[name]
      return next
    })
  }

  function continueToNextStep() {
    const errors = validateStep(step, form)
    setFieldErrors(errors)
    if (Object.keys(errors).length > 0) return
    setStep((current) => Math.min(current + 1, STEPS.length - 1))
  }

  function returnToPreviousStep() {
    setFieldErrors({})
    setStep((current) => Math.max(current - 1, 0))
  }

  function leaveForm() {
    if (isDirty && !window.confirm(UNSAVED_MESSAGE)) return
    navigate(MANAGE_PROPERTIES_PATH)
  }

  async function handleSubmit(event) {
    event.preventDefault()

    if (step < STEPS.length - 1) {
      continueToNextStep()
      return
    }

    if (isEditing && !isDirty) return

    for (const candidateStep of [0, 1]) {
      const errors = validateStep(candidateStep, form)
      if (Object.keys(errors).length > 0) {
        setStep(candidateStep)
        setFieldErrors(errors)
        return
      }
    }

    setSaving(true)
    setError('')

    try {
      const request = formToRequest(form)
      let savedPropertyId = ownedPropertyId

      if (isEditing) {
        await updateProperty(ownedPropertyId, request)
      } else {
        const property = await createProperty(request)
        savedPropertyId = property.id
      }

      if (files.length > 0) {
        await uploadPropertyImages(savedPropertyId, files)
      }

      const propertyName = form.title.trim()
      const photoLabel = `${files.length} ${files.length === 1 ? 'photo' : 'photos'}`
      const successMessage = isEditing
        ? files.length > 0
          ? `${propertyName} was updated successfully with ${photoLabel} added.`
          : `${propertyName} was updated successfully.`
        : files.length > 0
          ? `${propertyName} was created successfully with ${photoLabel}.`
          : `${propertyName} was created successfully.`

      setInitialSnapshot(formSnapshot(form))
      setFiles([])
      navigate(MANAGE_PROPERTIES_PATH, {
        replace: true,
        state: { propertyMessage: successMessage },
      })
    } catch (err) {
      setError(err instanceof Error ? err.message : `Unable to ${isEditing ? 'update' : 'create'} the property.`)
    } finally {
      setSaving(false)
    }
  }

  if (status === 'loading') {
    return (
      <main className="property-form-page">
        <button type="button" className="property-form-back" onClick={leaveForm}>
          <Icon name="arrow" size={16} /> Back to My Properties
        </button>
        <div className="property-form-state" role="status">
          <span className="property-spinner" aria-hidden="true" />
          <h1>Loading property...</h1>
          <p>Checking your owned property portfolio.</p>
        </div>
      </main>
    )
  }

  if (status === 'error' || status === 'unavailable') {
    return (
      <main className="property-form-page">
        <button type="button" className="property-form-back" onClick={leaveForm}>
          <Icon name="arrow" size={16} /> Back to My Properties
        </button>
        <div className="property-form-state" role={status === 'error' ? 'alert' : undefined}>
          <span className="property-state__icon property-state__icon--error" aria-hidden="true">
            <Icon name="alert" size={26} />
          </span>
          <h1>{status === 'unavailable' ? 'Property unavailable' : 'We could not load this property'}</h1>
          <p>{status === 'unavailable'
            ? 'This property is not in your authenticated property portfolio.'
            : error}</p>
          {status === 'error' && (
            <button
              type="button"
              className="property-button property-button--primary"
              onClick={() => {
                setStatus('loading')
                setError('')
                setLoadAttempt((current) => current + 1)
              }}
            >
              Try again
            </button>
          )}
        </div>
      </main>
    )
  }

  return (
    <main className="property-form-page">
      <button type="button" className="property-form-back" onClick={leaveForm} disabled={saving}>
        <Icon name="arrow" size={16} /> Back to My Properties
      </button>

      <header className="property-form-header">
        <div>
          <h1>{pageTitle}</h1>
          <p>{pageDescription}</p>
        </div>
        <span className="property-form-progress-label">{progressLabel}</span>
      </header>

      <ol className="property-wizard-steps" aria-label="Property form progress">
        {STEPS.map((item, index) => (
          <li
            key={item.title}
            className={`${index === step ? 'is-active' : ''}${index < step ? ' is-complete' : ''}`.trim()}
            aria-current={index === step ? 'step' : undefined}
          >
            <span className="property-wizard-steps__number">{index < step ? '✓' : index + 1}</span>
            <span>
              <strong>{item.title}</strong>
              <small>{item.description}</small>
            </span>
          </li>
        ))}
      </ol>

      {error && (
        <div className="property-management-alert property-management-alert--error" role="alert">
          <strong>Something went wrong</strong>
          <span>{error}</span>
        </div>
      )}

      <section className="property-wizard-card" aria-labelledby="property-step-title">
        <div className="property-wizard-card__heading">
          <span className="property-section-number">{progressLabel}</span>
          <h2 id="property-step-title" ref={stepHeadingRef} tabIndex="-1">{STEPS[step].title}</h2>
          <p>{STEPS[step].description}</p>
        </div>

        <form onSubmit={handleSubmit} className="property-editor-form" noValidate>
          {step === 0 && (
            <>
              <PropertyField name="title" label="Property title" error={fieldErrors.title} wide>
                <input
                  id="title"
                  name="title"
                  value={form.title}
                  onChange={updateField}
                  placeholder="e.g. Harbour View Residence"
                  aria-invalid={Boolean(fieldErrors.title)}
                  aria-describedby={fieldErrors.title ? 'title-error' : undefined}
                />
              </PropertyField>

              <PropertyField name="description" label="Description" error={fieldErrors.description} wide>
                <textarea
                  id="description"
                  name="description"
                  value={form.description}
                  onChange={updateField}
                  placeholder="Describe the property and its key features..."
                  rows="4"
                  aria-invalid={Boolean(fieldErrors.description)}
                  aria-describedby={fieldErrors.description ? 'description-error' : undefined}
                />
              </PropertyField>

              <PropertyField name="address" label="Address" error={fieldErrors.address} wide>
                <input
                  id="address"
                  name="address"
                  value={form.address}
                  onChange={updateField}
                  placeholder="Enter the property address"
                  aria-invalid={Boolean(fieldErrors.address)}
                  aria-describedby={fieldErrors.address ? 'address-error' : undefined}
                />
              </PropertyField>

              <PropertyField name="city" label="City" error={fieldErrors.city}>
                <input
                  id="city"
                  name="city"
                  value={form.city}
                  onChange={updateField}
                  placeholder="e.g. Colombo"
                  aria-invalid={Boolean(fieldErrors.city)}
                  aria-describedby={fieldErrors.city ? 'city-error' : undefined}
                />
              </PropertyField>
            </>
          )}

          {step === 1 && (
            <>
              <PropertyField name="monthlyRent" label="Monthly rent" error={fieldErrors.monthlyRent}>
                <div className="property-input-prefix">
                  <span>Rs.</span>
                  <input
                    id="monthlyRent"
                    type="number"
                    min="0"
                    name="monthlyRent"
                    value={form.monthlyRent}
                    onChange={updateField}
                    placeholder="e.g. 85000"
                    aria-invalid={Boolean(fieldErrors.monthlyRent)}
                    aria-describedby={fieldErrors.monthlyRent ? 'monthlyRent-error' : undefined}
                  />
                </div>
              </PropertyField>

              <PropertyField name="bedrooms" label="Bedrooms" error={fieldErrors.bedrooms}>
                <input
                  id="bedrooms"
                  type="number"
                  min="0"
                  name="bedrooms"
                  value={form.bedrooms}
                  onChange={updateField}
                  placeholder="e.g. 2"
                  aria-invalid={Boolean(fieldErrors.bedrooms)}
                  aria-describedby={fieldErrors.bedrooms ? 'bedrooms-error' : undefined}
                />
              </PropertyField>

              <PropertyField name="bathrooms" label="Bathrooms" error={fieldErrors.bathrooms}>
                <input
                  id="bathrooms"
                  type="number"
                  min="0"
                  name="bathrooms"
                  value={form.bathrooms}
                  onChange={updateField}
                  placeholder="e.g. 2"
                  aria-invalid={Boolean(fieldErrors.bathrooms)}
                  aria-describedby={fieldErrors.bathrooms ? 'bathrooms-error' : undefined}
                />
              </PropertyField>

              <PropertyField name="area" label="Property / land size" error={fieldErrors.area} wide>
                <div className="property-size-input">
                  <input
                    id="area"
                    type="number"
                    min="0.01"
                    step="0.01"
                    name="area"
                    value={form.area}
                    onChange={updateField}
                    placeholder="e.g. 1250"
                    aria-invalid={Boolean(fieldErrors.area)}
                    aria-describedby={fieldErrors.area ? 'area-error' : undefined}
                  />
                  <label className="visually-hidden" htmlFor="areaUnit">Size unit</label>
                  <select
                    id="areaUnit"
                    name="areaUnit"
                    value={form.areaUnit}
                    onChange={updateField}
                  >
                    {PROPERTY_AREA_UNITS.map((unit) => (
                      <option key={unit.value} value={unit.value}>{unit.label}</option>
                    ))}
                  </select>
                </div>
                <small>Choose the unit that matches the building or land measurement.</small>
              </PropertyField>

              <PropertyField name="amenities" label="Amenities" wide>
                <input
                  id="amenities"
                  name="amenities"
                  value={form.amenities}
                  onChange={updateField}
                  placeholder="e.g. Parking, Air Conditioning, Security"
                />
                <small>Separate multiple amenities with commas.</small>
              </PropertyField>
            </>
          )}

          {step === 2 && (
            <>
              <div className="property-photo-field">
                {isEditing && (
                  <div className="property-existing-images">
                    <strong>Current photos</strong>
                    <p>These photos are already saved with this property.</p>
                    <PropertyImageGallery propertyId={ownedPropertyId} />
                  </div>
                )}

                <div>
                  <strong>{isEditing ? 'Add more property photos' : 'Property photos'}</strong>
                  <p>{isEditing
                    ? 'Select new images only if you want to add more photos.'
                    : 'Photos are uploaded after the property is safely created.'}</p>
                </div>

                <label className="property-photo-picker">
                  <span>{files.length > 0
                    ? `${files.length} photo${files.length === 1 ? '' : 's'} selected`
                    : isEditing ? 'Choose additional photos' : 'Choose property photos'}</span>
                  <input
                    type="file"
                    accept="image/jpeg,image/png"
                    multiple
                    onChange={(event) => setFiles(Array.from(event.target.files || []))}
                  />
                </label>

                {files.length > 0 && (
                  <div className="property-selected-files">
                    {files.map((file) => (
                      <span key={`${file.name}-${file.size}`}>{file.name}</span>
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
            </>
          )}

          <div className="property-editor-actions property-wizard-actions">
            <div>
              {step > 0 && (
                <button
                  type="button"
                  className="property-button property-button--quiet"
                  onClick={returnToPreviousStep}
                  disabled={saving}
                >
                  Back
                </button>
              )}
              <button
                type="button"
                className="property-button property-button--quiet"
                onClick={leaveForm}
                disabled={saving}
              >
                Cancel
              </button>
            </div>

            {step < STEPS.length - 1 ? (
              <button
                type="submit"
                className="property-button property-button--primary"
                disabled={saving}
              >
                Continue
              </button>
            ) : (
              <button
                type="submit"
                className="property-button property-button--primary"
                disabled={saving || (isEditing && !isDirty)}
              >
                {saving
                  ? isEditing ? 'Saving changes...' : 'Creating property...'
                  : isEditing ? 'Save Changes' : 'Create Property'}
              </button>
            )}
          </div>
        </form>
      </section>
    </main>
  )
}
