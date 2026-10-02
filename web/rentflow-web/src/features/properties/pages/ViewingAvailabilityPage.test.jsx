import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter, RouterProvider } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../../App.jsx'
import { AuthContext } from '../../auth/useAuth.js'
import ViewingAvailabilityPage from './ViewingAvailabilityPage.jsx'
import { getUnreadCount } from '../../notifications/notificationsApi.js'
import { getMyProperties, getProperty, getPropertyImages } from '../services/propertyApiService.js'
import { getViewingAvailability, saveViewingAvailability } from '../services/viewingAvailabilityApi.js'

vi.mock('../services/propertyApiService.js', async importOriginal => ({
  ...(await importOriginal()), getMyProperties: vi.fn(), getProperty: vi.fn(), getPropertyImages: vi.fn(),
}))
vi.mock('../services/viewingAvailabilityApi.js', () => ({
  getViewingAvailability: vi.fn(), saveViewingAvailability: vi.fn(),
}))
vi.mock('../../notifications/notificationsApi.js', async importOriginal => ({
  ...(await importOriginal()), getUnreadCount: vi.fn().mockResolvedValue(0),
}))

const propertyId = '11111111-1111-1111-1111-111111111111'
const secondId = '99999999-9999-9999-9999-999999999999'
const landlordId = '22222222-2222-2222-2222-222222222222'
const property = {
  id: propertyId, landlordId, title: 'Harbour View Residence', address: '18 Marine Drive', city: 'Colombo',
  description: 'A bright home.', monthlyRent: 185000, bedrooms: 3, bathrooms: 2,
  isAvailable: true, amenities: [],
}
const empty = { propertyId, timeZoneId: 'Asia/Colombo', slotDurationMinutes: 60, windows: [] }
const configured = { ...empty, windows: [{ dayOfWeek: 1, isEnabled: true, startTime: '09:00:00', endTime: '17:00:00' }] }
const pathFor = id => `/properties/${id}/viewing-availability`

function renderApp(path = pathFor(propertyId), role = 'Landlord') {
  const router = createMemoryRouter([
    { path: '/missing-property', element: <ViewingAvailabilityPage /> },
    { path: '*', element: <App /> },
  ], { initialEntries: [path] })
  render(<AuthContext.Provider value={{
    user: { id: landlordId, role, fullName: 'Lena Landlord', email: 'lena@example.test' },
    isAuthenticated: true, isLoading: false, logout: vi.fn(),
  }}><RouterProvider router={router} /></AuthContext.Provider>)
  return router
}

beforeEach(() => {
  vi.resetAllMocks()
  getUnreadCount.mockResolvedValue(0)
  getMyProperties.mockResolvedValue([property])
  getProperty.mockResolvedValue(property)
  getPropertyImages.mockResolvedValue([])
  getViewingAvailability.mockResolvedValue(configured)
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('[]', { status: 200 })))
})
afterEach(() => { cleanup(); vi.restoreAllMocks(); vi.unstubAllGlobals() })

describe('dedicated property viewing availability', () => {
  it('loads the selected property, current schedule and property back link', async () => {
    renderApp()
    const context = await screen.findByRole('region', { name: 'Property context' })
    expect(within(context).getByRole('heading', { name: property.title })).toBeInTheDocument()
    expect(context).toHaveTextContent('18 Marine Drive, Colombo')
    expect(screen.getByRole('link', { name: 'Back to property' })).toHaveAttribute('href', `/properties/${propertyId}`)
    expect(await screen.findByLabelText('Monday start')).toHaveValue('09:00')
    expect(screen.getByLabelText('Monday end')).toHaveValue('17:00')
    expect(screen.getByLabelText('Slot duration')).toHaveValue('60')
    expect(screen.getByText('Sri Lanka (Asia/Colombo)')).toBeInTheDocument()
    expect(getViewingAvailability).toHaveBeenCalledWith(propertyId)
    expect(screen.getByRole('button', { name: 'Save viewing availability' })).toBeDisabled()
  })

  it('keeps an unconfigured schedule empty without inventing weekday hours', async () => {
    getViewingAvailability.mockResolvedValue(empty)
    renderApp()
    expect(await screen.findByText('No weekdays are enabled. Tenants will see no viewing times.')).toBeInTheDocument()
    expect(screen.getAllByRole('checkbox')).toHaveLength(7)
    expect(screen.getAllByRole('checkbox').every(day => !day.checked)).toBe(true)
    expect(screen.queryByLabelText('Monday start')).not.toBeInTheDocument()
  })

  it('edits weekdays, both time boundaries and duration, saving only after server confirmation', async () => {
    let finish
    saveViewingAvailability.mockImplementation(() => new Promise(resolve => { finish = resolve }))
    renderApp()
    fireEvent.click(await screen.findByLabelText('Tuesday enabled'))
    expect(screen.getByLabelText('Tuesday start')).toHaveValue('')
    expect(screen.getByRole('button', { name: 'Save viewing availability' })).toBeDisabled()
    fireEvent.change(screen.getByLabelText('Tuesday start'), { target: { value: '10:00' } })
    fireEvent.change(screen.getByLabelText('Tuesday end'), { target: { value: '14:00' } })
    fireEvent.click(screen.getByLabelText('Monday enabled'))
    fireEvent.change(screen.getByLabelText('Slot duration'), { target: { value: '90' } })
    await userEvent.click(screen.getByRole('button', { name: 'Save viewing availability' }))
    expect(saveViewingAvailability).toHaveBeenCalledWith(propertyId, expect.objectContaining({
      timeZoneId: 'Asia/Colombo', slotDurationMinutes: 90,
      windows: expect.arrayContaining([
        { dayOfWeek: 1, isEnabled: false, startTime: null, endTime: null },
        { dayOfWeek: 2, isEnabled: true, startTime: '10:00:00', endTime: '14:00:00' },
      ]),
    }))
    expect(screen.getByRole('button', { name: 'Saving availability...' })).toBeDisabled()
    expect(screen.getByLabelText('Tuesday start')).toBeDisabled()
    expect(screen.queryByText('Viewing availability saved.')).not.toBeInTheDocument()
    await act(async () => finish({ ...empty, slotDurationMinutes: 90, windows: [
      { dayOfWeek: 2, isEnabled: true, startTime: '10:15:00', endTime: '14:00:00' },
    ] }))
    expect(await screen.findByText('Viewing availability saved.')).toBeInTheDocument()
    expect(screen.getByLabelText('Tuesday start')).toHaveValue('10:15')
    expect(screen.getByRole('button', { name: 'Save viewing availability' })).toBeDisabled()
  })

  it('preserves values and stays on the page after a failed save, allowing retry', async () => {
    saveViewingAvailability.mockRejectedValueOnce(new Error('Unable to save. Please try again.'))
    const router = renderApp()
    fireEvent.change(await screen.findByLabelText('Monday end'), { target: { value: '18:00' } })
    fireEvent.change(screen.getByLabelText('Slot duration'), { target: { value: '45' } })
    await userEvent.click(screen.getByRole('button', { name: 'Save viewing availability' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Unable to save. Please try again.')
    expect(screen.getByLabelText('Monday end')).toHaveValue('18:00')
    expect(screen.getByLabelText('Slot duration')).toHaveValue('45')
    expect(router.state.location.pathname).toBe(pathFor(propertyId))
    expect(screen.queryByText('Viewing availability saved.')).not.toBeInTheDocument()
    saveViewingAvailability.mockResolvedValue({ ...configured, slotDurationMinutes: 45,
      windows: [{ ...configured.windows[0], endTime: '18:00:00' }] })
    await userEvent.click(screen.getByRole('button', { name: 'Save viewing availability' }))
    expect(await screen.findByText('Viewing availability saved.')).toBeInTheDocument()
  })

  it.each(['not-a-property', null])('handles an invalid or missing property ID (%s) without scoped API calls', async id => {
    renderApp(id === null ? '/missing-property' : pathFor(id))
    expect(await screen.findByRole('heading', { name: 'Property unavailable' })).toBeInTheDocument()
    expect(getMyProperties).not.toHaveBeenCalled()
    expect(getViewingAvailability).not.toHaveBeenCalled()
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
  })

  it('does not select a fallback property or load another landlord’s schedule', async () => {
    getMyProperties.mockResolvedValue([{ ...property, landlordId: 'another-landlord' }, { ...property, id: secondId }])
    renderApp()
    expect(await screen.findByRole('heading', { name: 'Property unavailable' })).toBeInTheDocument()
    expect(getViewingAvailability).not.toHaveBeenCalled()
    expect(saveViewingAvailability).not.toHaveBeenCalled()
  })

  it('retries a portfolio load failure before loading schedule controls', async () => {
    getMyProperties.mockRejectedValueOnce(new Error('Your properties could not be loaded.'))
    renderApp()
    expect(await screen.findByRole('alert')).toHaveTextContent('Your properties could not be loaded.')
    expect(getViewingAvailability).not.toHaveBeenCalled()
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByLabelText('Monday start')).toHaveValue('09:00')
  })

  it('honors backend schedule access errors and offers load retry without an editable form', async () => {
    getViewingAvailability.mockRejectedValueOnce(new Error('This schedule is not accessible.'))
    renderApp()
    expect(await screen.findByRole('alert')).toHaveTextContent('This schedule is not accessible.')
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
    expect(saveViewingAvailability).not.toHaveBeenCalled()
    await userEvent.click(screen.getByRole('button', { name: 'Retry availability' }))
    expect(await screen.findByLabelText('Monday start')).toHaveValue('09:00')
  })

  it.each(['Tenant', 'MaintenanceTechnician'])('blocks direct schedule navigation for %s', async role => {
    renderApp(pathFor(propertyId), role)
    expect(await screen.findByRole('heading', { name: 'Not accessible' })).toBeInTheDocument()
    expect(getViewingAvailability).not.toHaveBeenCalled()
    expect(getMyProperties).not.toHaveBeenCalled()
  })

  it('preserves supported admin access through the same backend schedule APIs', async () => {
    renderApp(pathFor(propertyId), 'Admin')
    expect(await screen.findByLabelText('Monday start')).toHaveValue('09:00')
    expect(getProperty).toHaveBeenCalledWith(propertyId)
    expect(getMyProperties).not.toHaveBeenCalled()
    expect(getViewingAvailability).toHaveBeenCalledWith(propertyId)
  })

  it('keeps property schedules separate and ignores a stale load after switching properties', async () => {
    let finishFirst
    getMyProperties.mockResolvedValue([property, { ...property, id: secondId, title: 'Garden Cottage' }])
    getViewingAvailability.mockImplementation(id => id === propertyId
      ? new Promise(resolve => { finishFirst = resolve })
      : Promise.resolve({ ...empty, propertyId: secondId, slotDurationMinutes: 30, windows: [
        { dayOfWeek: 6, isEnabled: true, startTime: '10:00:00', endTime: '14:00:00' },
      ] }))
    const router = renderApp()
    await waitFor(() => expect(getViewingAvailability).toHaveBeenCalledWith(propertyId))
    await act(async () => router.navigate(pathFor(secondId)))
    expect(await screen.findByLabelText('Saturday start')).toHaveValue('10:00')
    await act(async () => finishFirst(configured))
    expect(screen.getByRole('region', { name: 'Property context' })).toHaveTextContent('Garden Cottage')
    expect(screen.queryByLabelText('Monday start')).not.toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Saturday end'), { target: { value: '15:00' } })
    saveViewingAvailability.mockResolvedValue({ ...empty, propertyId: secondId, slotDurationMinutes: 30, windows: [
      { dayOfWeek: 6, isEnabled: true, startTime: '10:00:00', endTime: '15:00:00' },
    ] })
    await userEvent.click(screen.getByRole('button', { name: 'Save viewing availability' }))
    expect(await screen.findByText('Viewing availability saved.')).toBeInTheDocument()
    expect(saveViewingAvailability).toHaveBeenCalledWith(secondId, expect.objectContaining({ propertyId: secondId }))
  })

  it('protects unsaved schedule edits when following the property back link', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false)
    const router = renderApp()
    fireEvent.change(await screen.findByLabelText('Monday start'), { target: { value: '10:00' } })
    await userEvent.click(screen.getByRole('link', { name: 'Back to property' }))
    expect(confirm).toHaveBeenCalledWith(expect.stringContaining('unsaved viewing availability changes'))
    expect(router.state.location.pathname).toBe(pathFor(propertyId))
    const unload = new Event('beforeunload', { cancelable: true })
    window.dispatchEvent(unload)
    expect(unload.defaultPrevented).toBe(true)
  })
})
