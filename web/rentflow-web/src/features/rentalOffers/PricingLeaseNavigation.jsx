import { NavLink } from 'react-router-dom'
import './rentalOffers.css'

export default function PricingLeaseNavigation() {
  return <nav className="pricing-lease-nav" aria-label="Pricing and lease sections">
    <NavLink end to="/modules/pricing-lease" className={({ isActive }) => isActive ? 'pricing-lease-nav__active' : ''}>Rental Price Analysis</NavLink>
    <NavLink to="/modules/pricing-lease/offers" className={({ isActive }) => isActive ? 'pricing-lease-nav__active' : ''}>Rental Offers</NavLink>
    <NavLink to="/modules/pricing-lease/leases" className={({ isActive }) => isActive ? 'pricing-lease-nav__active' : ''}>Lease Agreements</NavLink>
    <NavLink to="/modules/pricing-lease/schedules" className={({ isActive }) => isActive ? 'pricing-lease-nav__active' : ''}>Rent Schedules</NavLink>
  </nav>
}
