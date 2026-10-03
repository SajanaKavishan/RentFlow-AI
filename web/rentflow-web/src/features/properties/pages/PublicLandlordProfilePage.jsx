import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import Icon from '../../../shared/ui/Icons.jsx'
import PublicLandlordAvatar from '../components/PublicLandlordAvatar.jsx'
import PropertyListingCard from '../components/PropertyListingCard.jsx'
import {
  getPublicLandlordSummary, getPublicLandlordProperties,
  getPropertyImages, getPropertyImageUrl,
} from '../services/propertyApiService.js'
import '../properties.css'
import './public-landlord-profile.css'

export default function PublicLandlordProfilePage() {
  const { propertyId } = useParams()
  const [retry, setRetry] = useState(0)
  const [profile, setProfile] = useState({ propertyId: null, status: 'loading', summary: null })
  const [listings, setListings] = useState({ propertyId: null, status: 'loading', properties: [], images: {} })
  const profileReady = profile.propertyId === propertyId && profile.status === 'ready'
  const profileFailed = profile.propertyId === propertyId && profile.status === 'error'
  const listingsStatus = listings.propertyId === propertyId ? listings.status : 'loading'

  useEffect(() => {
    let active = true
    async function loadProfile() {
      try {
        const summary = await getPublicLandlordSummary(propertyId)
        if (!summary || typeof summary.displayName !== 'string' || !summary.displayName.trim()
          || !Number.isInteger(summary.memberSinceYear) || typeof summary.hasProfileImage !== 'boolean') {
          throw new TypeError('Invalid landlord summary')
        }
        if (active) setProfile({ propertyId, status: 'ready', summary })
      } catch {
        if (active) setProfile({ propertyId, status: 'error', summary: null })
        return
      }
      try {
        const properties = await getPublicLandlordProperties(propertyId)
        if (!Array.isArray(properties) || properties.some((property) =>
          !property || typeof property.id !== 'string' || typeof property.title !== 'string'
          || property.isAvailable !== true)) throw new TypeError('Invalid public listings')
        if (active) setListings({ propertyId, status: 'ready', properties, images: {} })
        const entries = await Promise.all(properties.map(async (property) => {
          try {
            const metadata = await getPropertyImages(property.id)
            const urls = await Promise.all(metadata.map(async (image) => {
              try { return (await getPropertyImageUrl(property.id, image.id))?.url || null }
              catch { return null }
            }))
            return [property.id, urls.filter(Boolean)]
          } catch { return [property.id, []] }
        }))
        if (active) setListings({ propertyId, status: 'ready', properties, images: Object.fromEntries(entries) })
      } catch {
        if (active) setListings({ propertyId, status: 'error', properties: [], images: {} })
      }
    }
    loadProfile()
    return () => { active = false }
  }, [propertyId, retry])

  function tryAgain() {
    setProfile({ propertyId, status: 'loading', summary: null })
    setListings({ propertyId, status: 'loading', properties: [], images: {} })
    setRetry((value) => value + 1)
  }

  return <main className="public-landlord-page">
    <Link className="property-details-back" to={`/properties/${encodeURIComponent(propertyId)}`}>
      <Icon name="arrowLeft" size={16} /> Back to property
    </Link>
    {!profileReady && !profileFailed && <section className="property-state" role="status">
      <div className="property-spinner" /><h1>Loading landlord profile</h1>
    </section>}
    {profileFailed && <section className="property-state" role="alert">
      <h1>Landlord profile unavailable</h1><p>This profile could not be found or loaded.</p>
      <button className="property-button property-button--outline" onClick={tryAgain}>Try again</button>
    </section>}
    {profileReady && <>
      <header className="public-landlord-page__identity">
        <PublicLandlordAvatar key={propertyId} propertyId={propertyId} summary={profile.summary} className="public-landlord-page__avatar" />
        <div><p className="public-landlord-page__eyebrow">Landlord profile</p>
          <h1>{profile.summary.displayName}</h1><p>Member since {profile.summary.memberSinceYear}</p>
        </div>
      </header>
      <section aria-labelledby="public-landlord-properties">
        <div className="public-landlord-page__listings-heading">
          <h2 id="public-landlord-properties">Properties by {profile.summary.displayName}</h2>
          {listingsStatus === 'ready' && <span>{listings.properties.length} {listings.properties.length === 1 ? 'property' : 'properties'}</span>}
        </div>
        {listingsStatus === 'loading' && <p role="status">Loading properties…</p>}
        {listingsStatus === 'error' && <div className="property-state" role="alert"><p>Unable to load this landlord’s properties.</p>
          <button className="property-button property-button--outline" onClick={tryAgain}>Try again</button></div>}
        {listingsStatus === 'ready' && listings.properties.length === 0 && <div className="property-state"><p>No other properties are currently available.</p></div>}
        {listingsStatus === 'ready' && listings.properties.length > 0 && <div className="property-grid">
          {listings.properties.map((property) => <PropertyListingCard key={property.id} property={property} images={listings.images[property.id] || []} />)}
        </div>}
      </section>
    </>}
  </main>
}
