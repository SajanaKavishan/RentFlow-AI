import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import PropertyImageGallery from '../components/PropertyImageGallery.jsx'
import PropertyLocationPicker from '../components/PropertyLocationPicker.jsx'
import {
  createProperty,
  getMyProperties,
  updatePropertyListing,
  uploadPropertyImages,
} from '../services/propertyApiService.js'
import Icon from '../../../shared/ui/Icons.jsx'
import { getPropertyAreaUnits, PROPERTY_AREA_TYPES } from '../propertyArea.js'
import { AMENITY_CATALOG, UTILITY_CATALOG, getPropertyAmenityDetails } from '../propertyListingCatalog.js'
import '../properties.css'

const MANAGE_PROPERTIES_PATH = '/modules/manage-properties'
const UNSAVED_MESSAGE = 'You have unsaved property changes. Leave without saving them?'
const STEPS = [
  { title: 'Basic Details', description: 'Name and locate the property.' },
  { title: 'Property Details', description: 'Add rent, rooms, size and availability.' },
  { title: 'Rental Preferences & Amenities', description: 'Share non-binding preferences and listing features.' },
  { title: 'Photos & Publication', description: 'Finish the listing and publish.' },
]

const initialForm = {
  title: '',
  description: '',
  address: '',
  city: '',
  latitude: null,
  longitude: null,
  googlePlaceId: null,
  monthlyRent: '',
  bedrooms: '',
  bathrooms: '',
  area: '',
  areaUnit: 'sqft',
  areaType: 'FloorArea',
  availableFrom: '',
  advertisedSecurityDeposit: '',
  preferredLeaseTermMonths: '',
  petPolicy: '',
  petPolicyNotes: '',
  utilityInfoProvided: false,
  includedUtilities: [],
  canonicalAmenities: [],
  customAmenities: [],
  customAmenityDraft: '',
  isAvailable: true,
}

function propertyToForm(property) {
  const amenityDetails = getPropertyAmenityDetails(property)
  return {
    title: property.title || '',
    description: property.description || '',
    address: property.address || '',
    city: property.city || '',
    latitude: Number.isFinite(property.latitude) ? property.latitude : null,
    longitude: Number.isFinite(property.longitude) ? property.longitude : null,
    googlePlaceId: property.googlePlaceId || null,
    monthlyRent: property.monthlyRent ?? '',
    bedrooms: property.bedrooms ?? '',
    bathrooms: property.bathrooms ?? '',
    area: property.area ?? '',
    areaUnit: property.areaUnit || '',
    areaType: property.areaType || '',
    availableFrom: property.availableFrom || '',
    advertisedSecurityDeposit: property.advertisedSecurityDeposit ?? '',
    preferredLeaseTermMonths: property.preferredLeaseTermMonths ?? '',
    petPolicy: property.petPolicy || '',
    petPolicyNotes: property.petPolicy === 'NotAllowed' ? '' : property.petPolicyNotes || '',
    utilityInfoProvided: Array.isArray(property.includedUtilities),
    includedUtilities: property.includedUtilities || [],
    canonicalAmenities: amenityDetails.filter((item) => item.canonicalKey).map((item) => item.canonicalKey),
    customAmenities: amenityDetails.filter((item) => !item.canonicalKey).map((item) => item.name),
    customAmenityDraft: '',
    isAvailable: property.isAvailable ?? true,
  }
}

function formToRequest(form) {
  return {
    title: form.title.trim(),
    description: form.description.trim(),
    address: form.address.trim(),
    city: form.city.trim(),
    latitude: Number.isFinite(form.latitude) ? form.latitude : null,
    longitude: Number.isFinite(form.longitude) ? form.longitude : null,
    googlePlaceId: form.googlePlaceId?.trim() || null,
    monthlyRent: Number(form.monthlyRent),
    bedrooms: Number(form.bedrooms),
    bathrooms: Number(form.bathrooms),
    area: Number(form.area),
    areaUnit: form.areaUnit,
    areaType: form.areaType || null,
    availableFrom: form.availableFrom || null,
    isAvailable: Boolean(form.isAvailable),
    advertisedSecurityDeposit: form.advertisedSecurityDeposit === ''
      ? null : Number(form.advertisedSecurityDeposit),
    preferredLeaseTermMonths: form.preferredLeaseTermMonths === ''
      ? null : Number(form.preferredLeaseTermMonths),
    petPolicy: form.petPolicy || null,
    petPolicyNotes: form.petPolicyNotes.trim() || null,
    includedUtilities: form.utilityInfoProvided ? form.includedUtilities : null,
    amenities: [],
    amenityDetails: [
      ...form.canonicalAmenities.map((canonicalKey) => ({ canonicalKey, customName: null })),
      ...form.customAmenities.map((customName) => ({ canonicalKey: null, customName })),
    ],
  }
}

function formSnapshot(form) {
  const normalizeNumber = (value) => value === '' ? '' : Number(value)

  return JSON.stringify({
    title: form.title.trim(),
    description: form.description.trim(),
    address: form.address.trim(),
    city: form.city.trim(),
    latitude: Number.isFinite(form.latitude) ? form.latitude : null,
    longitude: Number.isFinite(form.longitude) ? form.longitude : null,
    googlePlaceId: form.googlePlaceId?.trim() || null,
    monthlyRent: normalizeNumber(form.monthlyRent),
    bedrooms: normalizeNumber(form.bedrooms),
    bathrooms: normalizeNumber(form.bathrooms),
    area: normalizeNumber(form.area),
    areaUnit: form.areaUnit,
    areaType: form.areaType || null,
    availableFrom: form.availableFrom || null,
    advertisedSecurityDeposit: normalizeNumber(form.advertisedSecurityDeposit),
    preferredLeaseTermMonths: normalizeNumber(form.preferredLeaseTermMonths),
    petPolicy: form.petPolicy || null,
    petPolicyNotes: form.petPolicyNotes.trim(),
    utilityInfoProvided: form.utilityInfoProvided,
    includedUtilities: [...form.includedUtilities].sort(),
    canonicalAmenities: [...form.canonicalAmenities].sort(),
    customAmenities: form.customAmenities.map((item) => item.trim()).filter(Boolean).sort(),
    isAvailable: Boolean(form.isAvailable),
  })
}

function validateStep(step, form, locationMode) {
  const errors = {}

  if (step === 0) {
    for (const [field, label] of [
      ['title', 'Property title'],
      ['description', 'Description'],
    ]) {
      if (!form[field].trim()) errors[field] = `${label} is required.`
    }

    const coordinatesValid = Number.isFinite(form.latitude) && form.latitude >= -90 && form.latitude <= 90
      && Number.isFinite(form.longitude) && form.longitude >= -180 && form.longitude <= 180

    if (locationMode === 'manual' || locationMode === 'legacy') {
      if (!form.address.trim()) errors.address = 'Address is required.'
      if (!form.city.trim()) errors.city = 'City is required.'
    } else if (locationMode === 'confirmed') {
      if (!coordinatesValid) {
        errors.location = 'Select a Google place, use your current location, choose a point on the map, or enter the address manually.'
      }
      if (!form.address.trim()) errors.address = 'Address is required.'
      if (!form.city.trim()) errors.city = 'City is required.'
    } else {
      errors.location = 'Select a Google place, use your current location, choose a point on the map, or enter the address manually.'
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
        || numericValue < 0 || ((field === 'area' || field === 'monthlyRent') && numericValue <= 0)) {
        errors[field] = message
      }
    }
    if (form.areaType === 'FloorArea' &&
      (form.areaUnit === 'perch' || form.areaUnit === 'acre')) {
      errors.areaUnit = 'Floor area must use square feet or square metres.'
    }
  }

  if (step === 2) {
    if (form.advertisedSecurityDeposit !== ''
      && (!Number.isFinite(Number(form.advertisedSecurityDeposit)) || Number(form.advertisedSecurityDeposit) < 0)) {
      errors.advertisedSecurityDeposit = 'Advertised security deposit must be zero or more.'
    }
    if (form.preferredLeaseTermMonths !== '') {
      const term = Number(form.preferredLeaseTermMonths)
      if (!Number.isInteger(term) || term < 1 || term > 120) {
        errors.preferredLeaseTermMonths = 'Preferred lease term must be 1 to 120 months.'
      }
    }
    if (form.petPolicy === 'Conditional' && !form.petPolicyNotes.trim()) {
      errors.petPolicyNotes = 'Add meaningful notes for a conditional pet policy.'
    }
    if (form.petPolicyNotes.length > 500) {
      errors.petPolicyNotes = 'Pet notes must be 500 characters or fewer.'
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
  const [locationMode, setLocationMode] = useState(
    () => import.meta.env.VITE_GOOGLE_MAPS_API_KEY?.trim() ? 'search' : 'manual',
  )
  const [locationSource, setLocationSource] = useState('manual')
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
        setLocationMode(
          Number.isFinite(populatedForm.latitude) && Number.isFinite(populatedForm.longitude)
            ? 'confirmed'
            : 'legacy',
        )
        setLocationSource(
          Number.isFinite(populatedForm.latitude) && Number.isFinite(populatedForm.longitude)
            ? populatedForm.googlePlaceId ? 'google' : 'map'
            : 'manual',
        )
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
    : 'Create a complete listing in four short steps.'
  const progressLabel = useMemo(() => `Step ${step + 1} of ${STEPS.length}`, [step])

  function updateField(event) {
    const { name, value, type, checked } = event.target
    setForm((current) => ({
      ...current,
      [name]: type === 'checkbox' ? checked : value,
      ...(name === 'areaType' && value === 'FloorArea'
        && (current.areaUnit === 'perch' || current.areaUnit === 'acre')
        ? { areaUnit: 'sqft' }
        : {}),
      ...(name === 'petPolicy' && value === 'NotAllowed'
        ? { petPolicyNotes: '' }
        : {}),
    }))
    setFieldErrors((current) => {
      if (!current[name]) return current
      const next = { ...current }
      delete next[name]
      return next
    })
  }

  function toggleCollection(field, value) {
    setForm((current) => ({
      ...current,
      [field]: current[field].includes(value)
        ? current[field].filter((item) => item !== value)
        : [...current[field], value],
    }))
  }

  function addCustomAmenity() {
    const value = form.customAmenityDraft.trim()
    if (!value) return
    setForm((current) => ({
      ...current,
      customAmenities: current.customAmenities.some((item) => item.toLowerCase() === value.toLowerCase())
        ? current.customAmenities : [...current.customAmenities, value],
      customAmenityDraft: '',
    }))
  }

  function continueToNextStep() {
    const errors = validateStep(step, form, locationMode)
    setFieldErrors(errors)
    if (Object.keys(errors).length > 0) return
    setStep((current) => Math.min(current + 1, STEPS.length - 1))
  }

  function returnToPreviousStep() {
    setFieldErrors({})
    setStep((current) => Math.max(current - 1, 0))
  }

  function selectLocation(location, source = 'google') {
    setForm((current) => ({ ...current, ...location }))
    setLocationMode('confirmed')
    setLocationSource(source)
    setFieldErrors((current) => {
      const next = { ...current }
      delete next.location
      delete next.address
      delete next.city
      return next
    })
  }

  function useManualLocation() {
    setForm((current) => ({
      ...current,
      latitude: null,
      longitude: null,
      googlePlaceId: null,
    }))
    setLocationMode('manual')
    setLocationSource('manual')
    setFieldErrors((current) => {
      if (!current.location) return current
      const next = { ...current }
      delete next.location
      return next
    })
  }

  function searchWithGoogle() {
    setLocationMode('search')
    setFieldErrors((current) => {
      if (!current.location) return current
      const next = { ...current }
      delete next.location
      return next
    })
  }

  function useCurrentLocation() {
    setLocationMode('current')
    setFieldErrors((current) => {
      if (!current.location) return current
      const next = { ...current }
      delete next.location
      return next
    })
  }

  function pickOnMap() {
    setLocationMode('map')
    setFieldErrors((current) => {
      if (!current.location) return current
      const next = { ...current }
      delete next.location
      return next
    })
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

    for (const candidateStep of [0, 1, 2]) {
      const errors = validateStep(candidateStep, form, locationMode)
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
        await updatePropertyListing(ownedPropertyId, request)
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

              <PropertyLocationPicker
                form={form}
                mode={locationMode}
                source={locationSource}
                errors={fieldErrors}
                onFieldChange={updateField}
                onLocationSelected={selectLocation}
                onChangeLocation={searchWithGoogle}
                onUseManual={useManualLocation}
                onSearchWithGoogle={searchWithGoogle}
                onUseCurrentLocation={useCurrentLocation}
                onPickOnMap={pickOnMap}
              />
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

              <PropertyField name="area" label="Size" error={fieldErrors.area}>
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
              </PropertyField>

              <PropertyField name="areaType" label="Size type">
                <select id="areaType" name="areaType" value={form.areaType} onChange={updateField}>
                  {!form.areaType && <option value="">Not specified (legacy listing)</option>}
                  {PROPERTY_AREA_TYPES.map((type) => (
                    <option key={type.value} value={type.value}>{type.label}</option>
                  ))}
                </select>
              </PropertyField>

              <PropertyField name="areaUnit" label="Size unit" error={fieldErrors.areaUnit}>
                <select
                  id="areaUnit"
                  name="areaUnit"
                  value={form.areaUnit}
                  onChange={updateField}
                  aria-invalid={Boolean(fieldErrors.areaUnit)}
                  aria-describedby={fieldErrors.areaUnit ? 'areaUnit-error' : undefined}
                >
                  {!form.areaUnit && <option value="">Not specified (legacy listing)</option>}
                  {getPropertyAreaUnits(form.areaType).map((unit) => (
                    <option key={unit.value} value={unit.value}>{unit.label}</option>
                  ))}
                </select>
              </PropertyField>

              <PropertyField name="availableFrom" label="Available from">
                <input
                  id="availableFrom"
                  type="date"
                  name="availableFrom"
                  value={form.availableFrom}
                  onChange={updateField}
                />
                <small>Optional. Leave blank when no specific date has been promised.</small>
              </PropertyField>

            </>
          )}

          {step === 2 && (
            <>
              <PropertyField
                name="advertisedSecurityDeposit"
                label="Advertised security deposit"
                error={fieldErrors.advertisedSecurityDeposit}
              >
                <div className="property-input-prefix">
                  <span>Rs.</span>
                  <input
                    id="advertisedSecurityDeposit"
                    type="number"
                    min="0"
                    step="0.01"
                    name="advertisedSecurityDeposit"
                    value={form.advertisedSecurityDeposit}
                    onChange={updateField}
                    placeholder="Optional"
                  />
                </div>
                <small>Public listing information only; final negotiated terms may differ.</small>
              </PropertyField>

              <PropertyField
                name="preferredLeaseTermMonths"
                label="Preferred lease term"
                error={fieldErrors.preferredLeaseTermMonths}
              >
                <div className="property-input-suffix">
                  <input
                    id="preferredLeaseTermMonths"
                    type="number"
                    min="1"
                    max="120"
                    name="preferredLeaseTermMonths"
                    value={form.preferredLeaseTermMonths}
                    onChange={updateField}
                    placeholder="12"
                  />
                  <span>months</span>
                </div>
              </PropertyField>

              <PropertyField name="petPolicy" label="Pet policy">
                <select id="petPolicy" name="petPolicy" value={form.petPolicy} onChange={updateField}>
                  <option value="">Not specified</option>
                  <option value="Allowed">Allowed</option>
                  <option value="NotAllowed">Not allowed</option>
                  <option value="Conditional">Conditional</option>
                </select>
              </PropertyField>

              {form.petPolicy !== 'NotAllowed' && (
                <PropertyField name="petPolicyNotes" label="Pet notes" error={fieldErrors.petPolicyNotes} wide>
                  <textarea
                    id="petPolicyNotes"
                    name="petPolicyNotes"
                    value={form.petPolicyNotes}
                    onChange={updateField}
                    maxLength="500"
                    rows="3"
                    placeholder={form.petPolicy === 'Conditional'
                      ? 'Required, e.g. Landlord approval required'
                      : 'Optional, e.g. Small pets only'}
                  />
                </PropertyField>
              )}

              <fieldset className="property-choice-group property-form-field--wide">
                <legend>Utilities included in monthly rent</legend>
                <label className="property-choice-toggle">
                  <input
                    type="checkbox"
                    checked={form.utilityInfoProvided}
                    onChange={(event) => setForm((current) => ({
                      ...current,
                      utilityInfoProvided: event.target.checked,
                      includedUtilities: event.target.checked ? current.includedUtilities : [],
                    }))}
                  />
                  <span>I want to provide utility information</span>
                </label>
                {form.utilityInfoProvided && (
                  <div className="property-choice-grid">
                    {UTILITY_CATALOG.map((utility) => (
                      <label key={utility.key}>
                        <input
                          type="checkbox"
                          checked={form.includedUtilities.includes(utility.key)}
                          onChange={() => toggleCollection('includedUtilities', utility.key)}
                        />
                        <span>{utility.label}</span>
                      </label>
                    ))}
                  </div>
                )}
                <small>{form.utilityInfoProvided && form.includedUtilities.length === 0
                  ? 'No utilities are advertised as included.'
                  : 'Only select utilities included in the advertised monthly rent.'}</small>
              </fieldset>

              <fieldset className="property-choice-group property-form-field--wide">
                <legend>Amenities</legend>
                <div className="property-choice-grid property-choice-grid--amenities">
                  {AMENITY_CATALOG.map((amenity) => (
                    <label key={amenity.key}>
                      <input
                        type="checkbox"
                        checked={form.canonicalAmenities.includes(amenity.key)}
                        onChange={() => toggleCollection('canonicalAmenities', amenity.key)}
                      />
                      <Icon name={amenity.icon} size={18} />
                      <span>{amenity.label}</span>
                    </label>
                  ))}
                </div>
                <div className="property-custom-amenity">
                  <input
                    value={form.customAmenityDraft}
                    onChange={(event) => setForm((current) => ({ ...current, customAmenityDraft: event.target.value }))}
                    placeholder="Other amenity"
                    maxLength="100"
                  />
                  <button type="button" onClick={addCustomAmenity}>+ Add</button>
                </div>
                {form.customAmenities.length > 0 && (
                  <div className="property-custom-amenity-list">
                    {form.customAmenities.map((amenity) => (
                      <span key={amenity}>
                        {amenity}
                        <button
                          type="button"
                          aria-label={`Remove ${amenity}`}
                          onClick={() => setForm((current) => ({
                            ...current,
                            customAmenities: current.customAmenities.filter((item) => item !== amenity),
                          }))}
                        >×</button>
                      </span>
                    ))}
                  </div>
                )}
              </fieldset>
            </>
          )}

          {step === 3 && (
            <>
              <div className="property-photo-field">
                {isEditing && (
                  <div className="property-existing-images">
                    <strong>Current photos</strong>
                    <p>These photos are already saved with this property.</p>
                    <PropertyImageGallery propertyId={ownedPropertyId} manageable />
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
