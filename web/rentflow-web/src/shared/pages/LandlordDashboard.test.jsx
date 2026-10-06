import { act, cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter, RouterProvider } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { tokenStorage } from '../../core/auth/tokenStorage.js'

// This suite isolates dashboard record loading. The shared action-summary request
// and its sidebar badges are covered by LandlordActions.test.jsx.
vi.mock('../layout/useLandlordActionSummary.js', () => {
  const result = { status: 'ready', data: { maintenanceCount: 0, maintenanceByProperty: [], leaseCount: 0, paymentCount: 0 }, refresh: vi.fn() }
  return { default: () => result }
})

vi.mock('../../features/notifications/notificationsApi.js', async (importOriginal) => ({
  ...(await importOriginal()), getUnreadCount: vi.fn().mockResolvedValue(0),
}))
import { AuthProvider } from '../../features/auth/AuthContext.jsx'
import { AuthContext } from '../../features/auth/useAuth.js'
import { getApplicationValidationRuns } from '../../features/rentalApplications/services/applicationValidationApiService.js'
import { getMyProperties } from '../../features/properties/services/propertyApiService.js'
import { getLandlordPayments } from '../../features/payments/services/paymentApiService.js'
import { getPropertyMaintenanceRequests } from '../../features/maintenance/services/maintenanceApiService.js'
import { monthlyRevenue } from './useLandlordRevenue.js'
import { getLandlordLeases } from '../../features/leaseAgreements/services/leaseAgreementApiService.js'
import { renewalDays } from './useDashboardLeases.js'

vi.mock('../../features/leaseAgreements/services/leaseAgreementApiService.js', async (importOriginal) => ({
  ...(await importOriginal()), getLandlordLeases: vi.fn(),
}))

vi.mock('../../features/payments/services/paymentApiService.js', () => ({ getLandlordPayments: vi.fn() }))
vi.mock('../../features/maintenance/services/maintenanceApiService.js', async (importOriginal) => ({
  ...(await importOriginal()), getPropertyMaintenanceRequests: vi.fn(),
}))

vi.mock('../../features/rentalApplications/services/applicationValidationApiService.js', async (importOriginal) => ({
  ...(await importOriginal()), getApplicationValidationRuns: vi.fn(),
}))

vi.mock('../../features/properties/services/propertyApiService.js', async (importOriginal) => ({
  ...(await importOriginal()), getMyProperties: vi.fn(),
}))

const propertyId = '88888888-8888-8888-8888-888888888888'
const otherPropertyId = '99999999-9999-9999-9999-999999999999'
const landlord = { id: 'landlord-one', fullName: 'Nila Perera', email: 'nila@example.com', phoneNumber: '', role: 'Landlord' }
const ownedProperty = {
  id: propertyId,
  landlordId: landlord.id,
  title: 'Lake View Apartment',
  description: 'Owned property',
  address: '12 Lake Road',
  city: 'Colombo',
  monthlyRent: 120000,
  bedrooms: 2,
  bathrooms: 2,
  isAvailable: true,
  amenities: [],
}
const otherOwnedProperty = {
  ...ownedProperty,
  id: otherPropertyId,
  title: 'Garden House',
  address: '44 Green Lane',
  monthlyRent: 180000,
  isAvailable: false,
}
const viewings = [0, 0, 1, 2, 3, 4].map((status, index) => ({ id: `viewing-${index}`, propertyId, status }))
const applications = [0, 1, 1, 2, 3, 4, 5, 6].map((status, index) => ({
  id: `application-${index}`,
  tenantId: `tenant-${index}-reference`,
  propertyId,
  monthlyIncome: 75000 + (index * 5000),
  createdAt: `2026-09-${String(index + 1).padStart(2, '0')}T12:00:00Z`,
  status,
}))
const otherViewings = [{ id: 'other-viewing-0', propertyId: otherPropertyId, status: 0 }]
const otherApplications = [
  {
    id: 'other-application-0', tenantId: 'other-tenant-0', propertyId: otherPropertyId,
    monthlyIncome: 140000, createdAt: '2026-10-01T12:00:00Z', status: 1,
  },
  {
    id: 'other-application-1', tenantId: 'other-tenant-1', propertyId: otherPropertyId,
    monthlyIncome: 160000, createdAt: '2026-10-02T12:00:00Z', status: 4,
  },
]
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const scopedDashboard = (id = propertyId) => `/dashboard?propertyId=${id}`
const isViewing = (url) => url.includes('/api/viewings/property/')

function renderApp(entry = scopedDashboard(), user = landlord) {
  const router = createMemoryRouter([{ path: '*', element: <App /> }], { initialEntries: [entry] })
  const tree = (account) => (
    <AuthContext.Provider value={{ user: account, isAuthenticated: true, isLoading: false, logout: vi.fn() }}>
      <RouterProvider router={router} />
    </AuthContext.Provider>
  )
  const result = render(tree(user))
  return { router, changeUser: (account) => result.rerender(tree(account)) }
}

beforeEach(() => {
  getLandlordLeases.mockReset().mockResolvedValue([])
  getLandlordPayments.mockReset().mockResolvedValue([])
  getPropertyMaintenanceRequests.mockReset().mockResolvedValue([])
  tokenStorage.setToken('landlord-token')
  getMyProperties.mockReset().mockResolvedValue([ownedProperty, otherOwnedProperty])
  getApplicationValidationRuns.mockReset().mockResolvedValue([])
  vi.stubGlobal('fetch', vi.fn((url) => Promise.resolve(json(isViewing(url) ? viewings : applications))))
})

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

describe('landlord dashboard redesign', () => {
  it('routes maintenance and lease attention to their own records and scopes them by property', async () => {
    fetch.mockImplementation(() => Promise.resolve(json([])))
    getPropertyMaintenanceRequests.mockImplementation(async (id) => id === propertyId ? [
      { id: 'repair-1', propertyId: id, title: 'Emergency plumbing', priority: 'Emergency', status: 'Submitted' },
      { id: 'repair-closed', propertyId: id, priority: 'Emergency', status: 'Completed' },
    ] : [])
    const day = new Date()
    day.setUTCDate(day.getUTCDate() + 45)
    const endDate = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Colombo', year: 'numeric', month: '2-digit', day: '2-digit' }).format(day)
    getLandlordLeases.mockResolvedValue([
      { id: 'lease-1', propertyId, endDate, status: 1 },
      { id: 'lease-ended', propertyId, endDate, status: 3 },
    ])
    renderApp('/dashboard')
    let attention = screen.getByRole('region', { name: 'Needs Attention' })
    expect(await within(attention).findByText('1 urgent maintenance request')).toBeInTheDocument()
    expect(within(attention).getByRole('link', { name: 'Assign' })).toHaveAttribute('href', `/properties/${propertyId}/maintenance?requestId=repair-1`)
    expect(await within(attention).findByText('Lease renewal due in 45 days')).toBeInTheDocument()
    expect(within(attention).getByRole('link', { name: 'View' })).toHaveAttribute('href', '/modules/pricing-lease/leases?leaseId=lease-1')
    expect(within(attention).queryByText("You're all caught up")).not.toBeInTheDocument()
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Filter dashboard by property' }), otherPropertyId)
    attention = screen.getByRole('region', { name: 'Needs Attention' })
    expect(await within(attention).findByText("You're all caught up")).toBeInTheDocument()
    expect(within(attention).queryByText('1 urgent maintenance request')).not.toBeInTheDocument()
  })

  it('keeps available actions visible when another activity source fails', async () => {
    getLandlordLeases.mockRejectedValue(new Error('Unavailable'))
    renderApp()
    const attention = screen.getByRole('region', { name: 'Needs Attention' })
    expect(await within(attention).findByText('3 applications awaiting review')).toBeInTheDocument()
    expect(await within(attention).findByText(/Some landlord activity could not be checked/)).toBeInTheDocument()
    expect(within(attention).queryByText("You're all caught up")).not.toBeInTheDocument()
  })

  it('calculates renewal days using Sri Lankan calendar dates', () => {
    expect(renewalDays({ endDate: '2026-10-07' }, new Date('2026-10-06T18:30:00Z'))).toBe(0)
    expect(renewalDays({ endDate: '2026-10-06' }, new Date('2026-10-06T18:30:00Z'))).toBe(-1)
  })

  it('uses a time-aware greeting and places the property filter with Needs Attention', async () => {
    renderApp()

    expect(screen.getByRole('heading', { name: /Good (morning|afternoon|evening), Nila/ })).toBeInTheDocument()
    expect(screen.getByText("Here's what's happening across your rental portfolio today.")).toBeInTheDocument()
    const attention = screen.getByRole('region', { name: 'Needs Attention' })
    expect(await within(attention).findByRole('combobox', { name: 'Filter dashboard by property' })).toHaveValue(propertyId)
    expect(within(attention).getByText('Filter by property')).toBeInTheDocument()
    expect(screen.queryByRole('navigation', { name: 'Quick actions' })).not.toBeInTheDocument()
  })

  it('shows truthful summary cards and completed monthly revenue', async () => {
    renderApp()
    const active = screen.getByRole('region', { name: 'Active Properties' })
    const viewing = screen.getByRole('region', { name: 'Pending Viewings' })
    const application = screen.getByRole('region', { name: 'Applications' })

    expect(await within(viewing).findByText('2')).toBeInTheDocument()
    expect(within(viewing).getByText('For Lake View Apartment')).toBeInTheDocument()
    expect(await within(application).findByText('8')).toBeInTheDocument()
    expect(within(application).getByText('3 awaiting review')).toBeInTheDocument()
    expect(await within(active).findByText('1')).toBeInTheDocument()
    expect(within(active).getByText('2 total properties')).toBeInTheDocument()

    const revenue = screen.getByRole('region', { name: 'Revenue This Month' })
    expect(await within(revenue).findByText('Rs. 0')).toBeInTheDocument()
    expect(within(revenue).getByRole('link', { name: 'View Payments' })).toHaveAttribute('href', '/modules/payments')
    expect(screen.queryByText('Integration pending')).not.toBeInTheDocument()
  })

  it('derives only real availability and rent metrics for the portfolio', async () => {
    renderApp()
    const portfolio = screen.getByRole('region', { name: 'Portfolio Overview' })

    await waitFor(() => expect(portfolio).toHaveTextContent('Available properties1 / 2'))
    expect(portfolio).toHaveTextContent('Unavailable properties1 / 2')
    expect(portfolio).toHaveTextContent('Average monthly rentRs. 150,000')
    expect(portfolio).not.toHaveTextContent(/occupied|occupancy/i)
  })

  it('omits average rent unless all owned-property rent values are usable', async () => {
    getMyProperties.mockResolvedValue([{ ...ownedProperty, monthlyRent: null }, otherOwnedProperty])
    renderApp()
    const portfolio = screen.getByRole('region', { name: 'Portfolio Overview' })
    await waitFor(() => expect(portfolio).toHaveTextContent('Available properties1 / 2'))
    expect(within(portfolio).queryByText('Average monthly rent')).not.toBeInTheDocument()
  })

  it('shows empty maintenance with a working property-scoped action', async () => {
    renderApp()
    const maintenance = screen.getByRole('region', { name: 'Maintenance' })
    expect(await within(maintenance).findByText('No open maintenance requests')).toBeInTheDocument()
    expect(within(maintenance).getByRole('link', { name: 'View all' })).toHaveAttribute('href', `/properties/${propertyId}/maintenance`)
  })

  it('filters revenue and maintenance when switching between the portfolio and a property', async () => {
    const paidAt = new Date().toISOString()
    getLandlordPayments.mockResolvedValue([
      { id: 'paid-1', propertyId, amount: 120000, status: 1, paidAt },
      { id: 'paid-2', propertyId: otherPropertyId, amount: 180000, status: 1, paidAt },
      { id: 'pending', propertyId, amount: 90000, status: 0 },
      { id: 'failed', propertyId, amount: 90000, status: 2 },
      { id: 'old', propertyId, amount: 90000, status: 1, paidAt: '2020-01-01T00:00:00Z' },
    ])
    getPropertyMaintenanceRequests.mockImplementation(async (id) => [
      { id: `${id}-open`, propertyId: id, status: id === propertyId ? 'AwaitingLandlordApproval' : 'InProgress' },
      { id: `${id}-done`, propertyId: id, status: 'Completed' },
      { id: `${id}-cancelled`, propertyId: id, status: 'Cancelled' },
    ])
    renderApp('/dashboard')
    const revenue = () => screen.getByRole('region', { name: 'Revenue This Month' })
    const maintenance = () => screen.getByRole('region', { name: 'Maintenance' })
    expect(await within(revenue()).findByText('Rs. 300,000')).toBeInTheDocument()
    expect(await within(maintenance()).findByText('2 open requests')).toBeInTheDocument()
    expect(within(maintenance()).getByText('1 awaiting your approval')).toBeInTheDocument()
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Filter dashboard by property' }), otherPropertyId)
    expect(await within(revenue()).findByText('Rs. 180,000')).toBeInTheDocument()
    expect(await within(maintenance()).findByText('1 open request')).toBeInTheDocument()
    expect(within(maintenance()).getByText('No estimates awaiting your approval.')).toBeInTheDocument()
  })

  it.each(['Revenue This Month', 'Maintenance'])('retries %s independently after a service failure', async (title) => {
    const service = title === 'Maintenance' ? getPropertyMaintenanceRequests : getLandlordPayments
    service.mockRejectedValueOnce(new Error('Unavailable'))
    renderApp()
    const card = screen.getByRole('region', { name: title })
    await within(card).findByRole('alert')
    expect(within(card).queryByText('Rs. 0')).not.toBeInTheDocument()
    await userEvent.click(within(card).getByRole('button', { name: 'Try again' }))
    expect(await within(card).findByText(title === 'Maintenance' ? 'No open maintenance requests' : 'Rs. 0')).toBeInTheDocument()
  })

  it('uses the Sri Lankan month boundary and excludes pending payments from revenue', () => {
    expect(monthlyRevenue([
      { amount: 100, status: 1, paidAt: '2026-09-30T18:29:59Z' },
      { amount: 200, status: 1, paidAt: '2026-09-30T18:30:00Z' },
      { amount: 300, status: 1, paidAt: '2026-10-31T18:30:00Z' },
      { amount: 400, status: 0, paidAt: '2026-10-01T00:00:00Z' },
    ], new Date('2026-10-06T00:00:00Z'))).toBe(200)
  })

  it('shows only real, selected-property actions in Needs Attention', async () => {
    renderApp()
    const attention = screen.getByRole('region', { name: 'Needs Attention' })

    expect(await within(attention).findByText('3 applications awaiting review')).toBeInTheDocument()
    expect(within(attention).getByText('Lake View Apartment', { selector: 'p' })).toBeInTheDocument()
    expect(within(attention).getByText('2 viewing requests pending approval')).toBeInTheDocument()
    expect(within(attention).getByText('Respond to requested viewing appointments.')).toBeInTheDocument()
    expect(within(attention).getByRole('link', { name: 'Review' })).toHaveAttribute('href', `/rental-applications?propertyId=${propertyId}`)
    expect(within(attention).getByRole('link', { name: 'Approve' })).toHaveAttribute('href', `/viewing-requests?propertyId=${propertyId}`)
  })

  it('shows the caught-up state when the selected property has no urgent actions', async () => {
    fetch.mockImplementation((url) => Promise.resolve(json(isViewing(url)
      ? viewings.filter((item) => item.status !== 0)
      : applications.filter((item) => ![1, 2].includes(item.status)))))
    renderApp()
    const attention = screen.getByRole('region', { name: 'Needs Attention' })

    expect(await within(attention).findByText("You're all caught up")).toBeInTheDocument()
    expect(within(attention).getByText('No urgent landlord actions for Lake View Apartment right now.')).toBeInTheDocument()
    expect(getApplicationValidationRuns).not.toHaveBeenCalled()
  })

  it('renders applicant names and application details links without exposing IDs as names', async () => {
    const records = applications.map((application, index) => index === 7
      ? { ...application, applicantName: 'Ayesha Fernando' }
      : application)
    fetch.mockImplementation((url) => Promise.resolve(json(isViewing(url) ? [] : records)))
    renderApp()
    const recent = screen.getByRole('region', { name: 'Recent Applications' })

    expect(await within(recent).findByText('Showing applications for Lake View Apartment')).toBeInTheDocument()
    const rows = (await within(recent).findAllByRole('row')).slice(1)
    expect(rows).toHaveLength(5)
    expect(within(rows[0]).getByText('Ayesha Fernando')).toBeInTheDocument()
    expect(within(rows[0]).queryByText('tenant-7-reference')).not.toBeInTheDocument()
    expect(within(rows[0]).getByText('Rs. 110,000')).toBeInTheDocument()
    expect(within(rows[0]).getByLabelText('Application status: Withdrawn')).toBeInTheDocument()
    expect(within(rows[1]).getByText('Name unavailable')).toBeInTheDocument()
    expect(rows.every((row) => within(row).getByText('Lake View Apartment'))).toBe(true)
    expect(within(rows[0]).getByRole('link', { name: 'Review application application-7' })).toHaveAttribute(
      'href',
      '/notifications/rental-application/application-7',
    )
  })

  it('shows AI review actions only for confirmed human-review workflows', async () => {
    getApplicationValidationRuns.mockImplementation((id) => Promise.resolve(id === 'application-3'
      ? [{ id: 'run-three', applicationId: id, status: 2 }]
      : []))
    renderApp()
    const attention = screen.getByRole('region', { name: 'Needs Attention' })

    expect(await within(attention).findByText('AI validation completed for 1 application')).toBeInTheDocument()
    expect(within(attention).getAllByRole('link', { name: 'Review' }).map((link) => link.getAttribute('href'))).toContain(`/properties/${propertyId}/rental-applications/application-3/validation`)
    const recent = screen.getByRole('region', { name: 'Recent Applications' })
    expect(within(recent).getByRole('link', { name: 'AI Review application application-3' })).toHaveAttribute(
      'href',
      `/properties/${propertyId}/rental-applications/application-3/validation`,
    )
  })

  it.each(['/dashboard', '/dashboard?propertyId=invalid'])('defaults to an all-properties summary at %s', async (entry) => {
    fetch.mockImplementation((url) => {
      const isOtherProperty = url.endsWith(otherPropertyId)
      if (isViewing(url)) return Promise.resolve(json(isOtherProperty ? otherViewings : viewings))
      return Promise.resolve(json(isOtherProperty ? otherApplications : applications))
    })
    renderApp(entry)
    const selector = await screen.findByRole('combobox', { name: 'Filter dashboard by property' })
    expect(selector).toHaveValue('')
    expect(within(selector).getByRole('option', { name: 'All properties' }).selected).toBe(true)

    const viewing = screen.getByRole('region', { name: 'Pending Viewings' })
    const application = screen.getByRole('region', { name: 'Applications' })
    expect(await within(viewing).findByText('3')).toBeInTheDocument()
    expect(within(viewing).getByText('Across all properties')).toBeInTheDocument()
    expect(await within(application).findByText('10')).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Needs Attention' })).getByText('Lake View Apartment, Garden House')).toBeInTheDocument()
    expect(screen.getByText('Showing applications for all properties')).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Recent Applications' })).getAllByText('Garden House')).toHaveLength(2)
    expect(fetch).toHaveBeenCalledTimes(4)
    expect(fetch.mock.calls.map(([url]) => new URL(url, 'http://localhost').pathname).sort()).toEqual([
      `/api/rental-applications/property/${propertyId}`,
      `/api/rental-applications/property/${otherPropertyId}`,
      `/api/viewings/property/${propertyId}`,
      `/api/viewings/property/${otherPropertyId}`,
    ].sort())
  })

  it('changes the selected property from the dashboard selector and reloads only scoped endpoints', async () => {
    fetch.mockImplementation(() => Promise.resolve(json([])))
    const { router } = renderApp()
    const selector = await screen.findByRole('combobox', { name: 'Filter dashboard by property' })
    await userEvent.selectOptions(selector, otherPropertyId)

    expect(router.state.location.pathname).toBe('/dashboard')
    expect(router.state.location.search).toBe(`?propertyId=${otherPropertyId}`)
    expect(await within(screen.getByRole('region', { name: 'Applications' })).findByText('0')).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Applications' })).getByText('For Garden House')).toBeInTheDocument()
    expect(fetch.mock.calls.slice(-2).every(([url]) => url.endsWith(otherPropertyId))).toBe(true)
  })

  it('shows the exact no-property state and real zero portfolio metrics', async () => {
    getMyProperties.mockResolvedValue([])
    renderApp('/dashboard')

    expect(await screen.findByRole('link', { name: 'Add your first property' })).toHaveAttribute('href', '/properties/new')
    const active = screen.getByRole('region', { name: 'Active Properties' })
    expect(within(active).getByText('0')).toBeInTheDocument()
    expect(within(active).getByText('No properties yet')).toBeInTheDocument()
    const portfolio = screen.getByRole('region', { name: 'Portfolio Overview' })
    expect(portfolio).toHaveTextContent('Available properties0 / 0')
    expect(portfolio).toHaveTextContent('Unavailable properties0 / 0')
    expect(within(portfolio).queryByText('Average monthly rent')).not.toBeInTheDocument()
  })

  it('uses honest empty copy for an application-free selected property', async () => {
    fetch.mockImplementation(() => Promise.resolve(json([])))
    renderApp()
    const recent = screen.getByRole('region', { name: 'Recent Applications' })

    expect(await within(recent).findByText('No applications yet')).toBeInTheDocument()
    expect(within(recent).getByText('Rental applications for Lake View Apartment will appear here.')).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Needs Attention' })).getByText("You're all caught up")).toBeInTheDocument()
  })

  it.each(['viewings', 'applications'])('shows and retries the %s error without inventing a zero summary', async (failed) => {
    let attempts = 0
    fetch.mockImplementation((url) => {
      const viewing = isViewing(url)
      if (viewing === (failed === 'viewings') && ++attempts === 1) return Promise.resolve(json({}, 500))
      return Promise.resolve(json(viewing ? viewings : applications))
    })
    renderApp()
    const failedCard = screen.getByRole('region', { name: failed === 'viewings' ? 'Pending Viewings' : 'Applications' })

    expect(await within(failedCard).findByText('Summary unavailable')).toBeInTheDocument()
    expect(within(failedCard).getByText('Something went wrong while loading the latest landlord data.')).toBeInTheDocument()
    expect(within(failedCard).queryByText('0')).not.toBeInTheDocument()
    await userEvent.click(within(failedCard).getByRole('button', { name: 'Try again' }))
    expect(await within(failedCard).findByText(failed === 'viewings' ? '2' : '8')).toBeInTheDocument()
    expect(fetch).toHaveBeenCalledTimes(3)
  })

  it('rejects mismatched or duplicate scoped records and does not request AI validation', async () => {
    fetch.mockImplementation(() => Promise.resolve(json([
      { ...applications[1], propertyId: otherPropertyId },
      { ...applications[1], propertyId: otherPropertyId },
    ])))
    renderApp()

    const applicationCard = screen.getByRole('region', { name: 'Applications' })
    expect(await within(applicationCard).findByText('Summary unavailable')).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Recent Applications' })).getByText("We couldn't load this section")).toBeInTheDocument()
    expect(getApplicationValidationRuns).not.toHaveBeenCalled()
  })

  it('uses only the authenticated selected-property endpoints', async () => {
    renderApp()
    await within(screen.getByRole('region', { name: 'Applications' })).findByText('8')

    expect(fetch).toHaveBeenCalledTimes(2)
    expect(fetch.mock.calls.map(([url]) => new URL(url, 'http://localhost').pathname).sort()).toEqual([
      `/api/rental-applications/property/${propertyId}`,
      `/api/viewings/property/${propertyId}`,
    ])
    for (const [, options] of fetch.mock.calls) {
      expect(options.headers.Authorization).toBe('Bearer landlord-token')
      expect(options.method).toBeUndefined()
      expect(options.body).toBeUndefined()
    }
  })

  it('discards late responses after changing properties', async () => {
    const oldRequests = []
    fetch.mockImplementation(() => new Promise((resolve) => { oldRequests.push(resolve) }))
    const { router } = renderApp()
    await waitFor(() => expect(oldRequests).toHaveLength(2))
    fetch.mockImplementation(() => Promise.resolve(json([])))

    await act(async () => { await router.navigate(scopedDashboard(otherPropertyId)) })
    expect(await within(screen.getByRole('region', { name: 'Applications' })).findByText('0')).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Applications' })).getByText('For Garden House')).toBeInTheDocument()
    await act(async () => {
      oldRequests[0](json(viewings))
      oldRequests[1](json(applications))
    })
    expect(within(screen.getByRole('region', { name: 'Applications' })).queryByText('8')).not.toBeInTheDocument()
    expect(fetch.mock.calls.slice(2).every(([url]) => url.endsWith(otherPropertyId))).toBe(true)
  })

  it('publishes selected-property pending counts to the existing sidebar badges', async () => {
    renderApp()
    const navigation = screen.getByRole('navigation', { name: 'Primary navigation' })
    expect(await within(navigation).findByRole('link', { name: 'Viewing Requests, 2 pending' })).toBeInTheDocument()
    expect(within(navigation).getByRole('link', { name: 'Rental Applications, 3 pending' })).toBeInTheDocument()
  })

  it.each(['Tenant', 'Admin', 'MaintenanceTechnician'])('does not load landlord-scoped data for %s', async (role) => {
    renderApp(scopedDashboard(), { ...landlord, role })
    await act(async () => {})
    expect(fetch.mock.calls.some(([url]) => url.includes('/property/'))).toBe(false)
    expect(screen.queryByRole('navigation', { name: 'Quick actions' })).not.toBeInTheDocument()
  })

  it('uses the existing session-expiry behavior for a 401 response', async () => {
    fetch.mockImplementation(() => Promise.resolve(json({}, 401)))
    const api = { getCurrentUser: vi.fn().mockResolvedValue(landlord) }
    const router = createMemoryRouter(
      [{ path: '*', element: <AuthProvider api={api}><App /></AuthProvider> }],
      { initialEntries: [scopedDashboard()] },
    )
    render(<RouterProvider router={router} />)

    expect(await screen.findByRole('heading', { name: 'Sign in to RentFlow' })).toBeInTheDocument()
    expect(tokenStorage.getToken()).toBeNull()
  })
})
