import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { tokenStorage } from '../../../core/auth/tokenStorage.js'
import RentalOffersPage from './RentalOffersPage.jsx'

const propertyId = '11111111-1111-1111-1111-111111111111'
const applicationId = '22222222-2222-2222-2222-222222222222'
const tenantId = '33333333-3333-3333-3333-333333333333'
const offerId = '44444444-4444-4444-4444-444444444444'
const properties = [{ id: propertyId, title: 'Lake House', city: 'Kandy' }]
const applications = [{ id: applicationId, tenantId, propertyId, status: 4 }, { id: 'not-approved', tenantId, propertyId, status: 2 }]

function offer(overrides = {}) {
  return { id: offerId, rentalApplicationId: applicationId, tenantId, propertyId, monthlyRent: 85000, securityDeposit: 170000, proposedStartDate: '2026-11-01', proposedEndDate: '2027-10-31', expiresAt: '2026-10-01T10:00:00Z', status: 0, landlordNote: 'Welcome.', createdAt: '2026-09-27T10:00:00Z', updatedAt: null, ...overrides }
}

function response(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

function setupApi({ offers = [], listStatus = 200 } = {}) {
  const fetchMock = vi.fn((url, options = {}) => {
    if (url.endsWith('/api/properties/mine')) return Promise.resolve(response(properties))
    if (url.includes(`/api/rental-applications/property/${propertyId}`)) return Promise.resolve(response(applications))
    if (url.endsWith('/api/rental-offers/landlord')) return Promise.resolve(response(offers, listStatus))
    if (options.method === 'POST') return Promise.resolve(response(offer(), 201))
    if (options.method === 'PATCH') return Promise.resolve(response(offer({ status: 3, updatedAt: '2026-09-27T11:00:00Z' })))
    if (url.endsWith(`/api/rental-offers/${offerId}`)) return Promise.resolve(response(offer()))
    return Promise.resolve(response({ title: 'Not found' }, 404))
  })
  vi.stubGlobal('fetch', fetchMock)
  tokenStorage.setToken('landlord-token')
  render(<MemoryRouter initialEntries={['/modules/pricing-lease/offers']}><RentalOffersPage /></MemoryRouter>)
  return fetchMock
}

afterEach(() => { cleanup(); vi.unstubAllGlobals(); tokenStorage.clearToken() })

describe('landlord rental offers', () => {
  it('renders the landlord offer list and loads details by ID', async () => {
    const fetchMock = setupApi({ offers: [offer()] })
    expect(await screen.findByText(/Monthly rent 85,000/)).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'View details' }))
    expect(await screen.findByText('Welcome.')).toBeInTheDocument()
    expect(screen.getByText('170,000')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining(`/api/rental-offers/${offerId}`), expect.any(Object))
  })

  it('shows an empty landlord offer list', async () => {
    setupApi()
    expect(await screen.findByText('No rental offers yet.')).toBeInTheDocument()
  })

  it('creates an offer for a selected approved application using the exact DTO fields', async () => {
    const fetchMock = setupApi()
    await userEvent.selectOptions(await screen.findByLabelText('Property'), propertyId)
    await userEvent.selectOptions(await screen.findByLabelText('Approved application'), applicationId)
    expect(within(screen.getByLabelText('Approved application')).queryByRole('option', { name: /not-approved/ })).not.toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Monthly rent'), { target: { value: '85000' } })
    fireEvent.change(screen.getByLabelText('Security deposit'), { target: { value: '170000' } })
    fireEvent.change(screen.getByLabelText('Proposed start date'), { target: { value: '2026-11-01' } })
    fireEvent.change(screen.getByLabelText('Proposed end date'), { target: { value: '2027-10-31' } })
    fireEvent.change(screen.getByLabelText('Offer expiry'), { target: { value: '2030-10-01T10:00' } })
    await userEvent.type(screen.getByLabelText('Landlord note'), 'Welcome.')
    await userEvent.click(screen.getByRole('button', { name: 'Create offer' }))
    await waitFor(() => expect(fetchMock.mock.calls.some(([, options]) => options?.method === 'POST')).toBe(true))
    const [url, options] = fetchMock.mock.calls.find(([, request]) => request?.method === 'POST')
    expect(url).toContain('/api/rental-offers')
    expect(options.headers.Authorization).toBe('Bearer landlord-token')
    expect(JSON.parse(options.body)).toEqual({ rentalApplicationId: applicationId, monthlyRent: 85000, securityDeposit: 170000, proposedStartDate: '2026-11-01', proposedEndDate: '2027-10-31', expiresAt: new Date('2030-10-01T10:00').toISOString(), landlordNote: 'Welcome.' })
    expect(await screen.findByText('Rental offer created successfully.')).toBeInTheDocument()
  })

  it('shows a safe error when the landlord list API fails', async () => {
    setupApi({ offers: { detail: 'Internal database exception' }, listStatus: 500 })
    expect(await screen.findByRole('alert')).toHaveTextContent('Unable to load rental offers.')
    expect(screen.queryByText('Internal database exception')).not.toBeInTheDocument()
  })

  it('withdraws a pending offer through the landlord PATCH endpoint', async () => {
    const fetchMock = setupApi({ offers: [offer()] })
    await userEvent.click(await screen.findByRole('button', { name: 'View details' }))
    await userEvent.click(await screen.findByRole('button', { name: 'Withdraw offer' }))
    expect(await screen.findByText('Rental offer withdrawn.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Withdraw offer' })).not.toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining(`/api/rental-offers/${offerId}/withdraw`), expect.objectContaining({ method: 'PATCH' }))
  })
})
