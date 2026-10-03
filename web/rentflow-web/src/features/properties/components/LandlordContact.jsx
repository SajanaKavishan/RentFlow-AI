import { useEffect, useState } from 'react'
import { getLandlordContact } from '../services/propertyApiService.js'
import { usablePublicContactPhone } from '../publicContactPhone.js'
import './landlord-contact.css'

export default function LandlordContact({ propertyId, isTenant }) {
  const [contact, setContact] = useState(null)
  useEffect(() => {
    let active = true
    let version = 0
    async function refresh() {
      const current = ++version
      setContact(null)
      if (!isTenant) return
      try {
        const result = await getLandlordContact(propertyId)
        const phone = usablePublicContactPhone(result?.phoneNumber)
        if (active && current === version && phone) setContact({ propertyId, phone })
      } catch { /* Contact is optional; fail closed. */ }
    }
    function onVisible() { if (document.visibilityState === 'visible') refresh() }
    refresh()
    window.addEventListener('focus', refresh)
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      active = false
      window.removeEventListener('focus', refresh)
      document.removeEventListener('visibilitychange', onVisible)
    }
  }, [propertyId, isTenant])

  if (!isTenant || contact?.propertyId !== propertyId) return null
  return <section className="landlord-contact" aria-label="Contact landlord">
    <h2>Contact landlord</h2>
    <p>{contact.phone}</p>
  </section>
}
