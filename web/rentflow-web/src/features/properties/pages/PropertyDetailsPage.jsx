import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import PropertyImageGallery from '../components/PropertyImageGallery.jsx'
import { getProperty } from '../services/propertyApiService.js'

export default function PropertyDetailsPage() {
  const { propertyId } = useParams()

  const [property, setProperty] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true

    async function loadProperty() {
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

    return () => {
      active = false
    }
  }, [propertyId])

  if (loading) return <p>Loading property...</p>

  if (error) return <p role="alert">{error}</p>

  if (!property) return <p>Property not found.</p>

  return (
    <section className="property-page">
      <Link to="/modules/properties">← Back to properties</Link>

      <h1>{property.title}</h1>

      <PropertyImageGallery propertyId={property.id} />

      <p>{property.description}</p>

      <dl>
        <dt>Address</dt>
        <dd>{property.address}</dd>

        <dt>City</dt>
        <dd>{property.city}</dd>

        <dt>Monthly rent</dt>
        <dd>
          Rs. {Number(property.monthlyRent).toLocaleString()}
        </dd>

        <dt>Bedrooms</dt>
        <dd>{property.bedrooms}</dd>

        <dt>Bathrooms</dt>
        <dd>{property.bathrooms}</dd>

        <dt>Status</dt>
        <dd>
          {property.isAvailable ? 'Available' : 'Unavailable'}
        </dd>
      </dl>

      {property.amenities?.length > 0 && (
        <>
          <h2>Amenities</h2>
          <ul>
            {property.amenities.map((amenity) => (
              <li key={amenity}>{amenity}</li>
            ))}
          </ul>
        </>
      )}
    </section>
  )
}
