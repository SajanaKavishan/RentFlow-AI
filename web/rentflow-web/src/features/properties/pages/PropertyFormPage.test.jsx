import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter, RouterProvider } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../../App.jsx'
import { AuthContext } from '../../auth/useAuth.js'
import {
  createProperty,
  getMyProperties,
  getPropertyImages,
  updateProperty,
  uploadPropertyImages,
} from '../services/propertyApiService.js'

vi.mock('../../notifications/notificationsApi.js', async (importOriginal) => ({
  ...(await importOriginal()), getUnreadCount: vi.fn().mockResolvedValue(0),
}))

vi.mock('../services/propertyApiService.js', async (importOriginal) => ({
  ...(await importOriginal()),
  createProperty: vi.fn(),
  getMyProperties: vi.fn(),
  getPropertyImages: vi.fn(),
  updateProperty: vi.fn(),
  uploadPropertyImages: vi.fn(),
}))

const propertyId = '11111111-1111-1111-1111-111111111111'
const newPropertyId = '77777777-7777-7777-7777-777777777777'
const property = {
  id: propertyId,
  landlordId: '22222222-2222-2222-2222-222222222222',
  title: 'Harbour View Residence',
  description: 'A bright apartment near the coast.',
  address: '18 Marine Drive',
  city: 'Colombo',
  monthlyRent: 185000,
  bedrooms: 3,
  bathrooms: 2,
  area: 1450,
  areaUnit: 'sqft',
  isAvailable: true,
  amenities: ['Parking', 'Security'],
}

function renderApp(entry) {
  const router = createMemoryRouter([{ path: '*', element: <App /> }], {
    initialEntries: [entry],
  })
  render(
    <AuthContext.Provider value={{
      user: {
        id: property.landlordId,
        fullName: 'Nila Perera',
        email: 'nila@example.com',
        role: 'Landlord',
      },
      isAuthenticated: true,
      isLoading: false,
      logout: vi.fn(),
    }}>
      <RouterProvider router={router} />
    </AuthContext.Provider>,
  )
  return router
}

async function completeBasicDetails() {
  await userEvent.type(screen.getByLabelText('Property title'), 'Lake House')
  await userEvent.type(screen.getByLabelText('Description'), 'A quiet lakeside home.')
  await userEvent.type(screen.getByLabelText('Address'), '25 Lake Road')
  await userEvent.type(screen.getByLabelText('City'), 'Kandy')
  await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
}

async function completePropertyDetails() {
  await userEvent.type(screen.getByLabelText('Monthly rent'), '95000')
  await userEvent.type(screen.getByLabelText('Bedrooms'), '2')
  await userEvent.type(screen.getByLabelText('Bathrooms'), '1')
  await userEvent.type(screen.getByLabelText('Property / land size'), '1250')
  await userEvent.type(screen.getByLabelText('Amenities'), 'Parking, Garden')
  await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
}

beforeEach(() => {
  getMyProperties.mockReset().mockResolvedValue([property])
  getPropertyImages.mockReset().mockResolvedValue([])
  createProperty.mockReset().mockResolvedValue({ id: newPropertyId })
  updateProperty.mockReset().mockResolvedValue(property)
  uploadPropertyImages.mockReset().mockResolvedValue([])
})

afterEach(() => {
  cleanup()
})

describe('property form wizard', () => {
  it('validates each step and preserves entered values while moving backward and forward', async () => {
    renderApp('/properties/new')

    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))

    expect(screen.getByRole('heading', { name: 'Basic Details' })).toBeInTheDocument()
    expect(screen.getByText('Property title is required.')).toBeInTheDocument()
    expect(screen.getByText('Description is required.')).toBeInTheDocument()
    expect(createProperty).not.toHaveBeenCalled()

    await completeBasicDetails()

    expect(screen.getByRole('heading', { name: 'Property Details' })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    expect(screen.getByText('Enter a valid monthly rent.')).toBeInTheDocument()
    expect(createProperty).not.toHaveBeenCalled()

    await completePropertyDetails()

    expect(screen.getByRole('heading', { name: 'Photos & Availability' })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Back' }))
    expect(screen.getByLabelText('Monthly rent')).toHaveValue(95000)
    expect(screen.getByLabelText('Amenities')).toHaveValue('Parking, Garden')

    await userEvent.click(screen.getByRole('button', { name: 'Back' }))
    expect(screen.getByLabelText('Property title')).toHaveValue('Lake House')
    expect(screen.getByLabelText('Description')).toHaveValue('A quiet lakeside home.')

    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    expect(screen.getByLabelText('Bedrooms')).toHaveValue(2)
    expect(createProperty).not.toHaveBeenCalled()
  })

  it('creates only at the final action and uploads photos with the returned property ID', async () => {
    const router = renderApp('/properties/new')
    await completeBasicDetails()
    await completePropertyDetails()
    const photo = new File(['property-photo'], 'lake-house.png', { type: 'image/png' })

    await userEvent.upload(screen.getByLabelText('Choose property photos'), photo)
    expect(createProperty).not.toHaveBeenCalled()
    await userEvent.click(screen.getByRole('button', { name: 'Create Property' }))

    await waitFor(() => expect(router.state.location.pathname).toBe('/modules/manage-properties'))
    expect(createProperty).toHaveBeenCalledWith({
      title: 'Lake House',
      description: 'A quiet lakeside home.',
      address: '25 Lake Road',
      city: 'Kandy',
      monthlyRent: 95000,
      bedrooms: 2,
      bathrooms: 1,
      area: 1250,
      areaUnit: 'sqft',
      isAvailable: true,
      amenities: ['Parking', 'Garden'],
    })
    expect(uploadPropertyImages).toHaveBeenCalledWith(newPropertyId, [photo])
    expect(createProperty.mock.invocationCallOrder[0])
      .toBeLessThan(uploadPropertyImages.mock.invocationCallOrder[0])
    const createdMessage = await screen.findByText('Lake House was created successfully with 1 photo.')
    expect(createdMessage.closest('.property-toast')).toHaveClass('property-toast--success')
  })

  it('treats an early form submit as Continue instead of creating the property', async () => {
    renderApp('/properties/new')
    await completeBasicDetails()

    await userEvent.type(screen.getByLabelText('Monthly rent'), '95000')
    await userEvent.type(screen.getByLabelText('Bedrooms'), '2')
    await userEvent.type(screen.getByLabelText('Bathrooms'), '1')
    await userEvent.type(screen.getByLabelText('Property / land size'), '1250')

    fireEvent.submit(screen.getByLabelText('Monthly rent').closest('form'))

    expect(screen.getByRole('heading', { name: 'Photos & Availability' })).toBeInTheDocument()
    expect(createProperty).not.toHaveBeenCalled()
  })

  it('loads an owned property into the edit route and saves through the existing update flow', async () => {
    const router = renderApp(`/properties/${propertyId}/edit`)

    expect(await screen.findByRole('heading', { name: 'Edit Property' })).toBeInTheDocument()
    expect(screen.getByLabelText('Property title')).toHaveValue(property.title)
    expect(screen.getByLabelText('Description')).toHaveValue(property.description)
    expect(getMyProperties).toHaveBeenCalledTimes(1)

    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    expect(screen.getByLabelText('Monthly rent')).toHaveValue(property.monthlyRent)
    expect(screen.getByLabelText('Amenities')).toHaveValue('Parking, Security')
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))

    expect(screen.getByRole('heading', { name: 'Photos & Availability' })).toBeInTheDocument()
    expect(updateProperty).not.toHaveBeenCalled()
    expect(await screen.findByText('No property photos uploaded yet.')).toBeInTheDocument()
    const saveButton = screen.getByRole('button', { name: 'Save Changes' })
    expect(saveButton).toBeDisabled()

    await userEvent.click(screen.getByLabelText(/Available for rent/))
    expect(saveButton).toBeEnabled()
    await userEvent.click(saveButton)

    await waitFor(() => expect(router.state.location.pathname).toBe('/modules/manage-properties'))
    expect(updateProperty).toHaveBeenCalledWith(propertyId, {
      title: property.title,
      description: property.description,
      address: property.address,
      city: property.city,
      monthlyRent: property.monthlyRent,
      bedrooms: property.bedrooms,
      bathrooms: property.bathrooms,
      area: property.area,
      areaUnit: property.areaUnit,
      isAvailable: false,
      amenities: property.amenities,
    })
    expect(uploadPropertyImages).not.toHaveBeenCalled()
    const updatedMessage = await screen.findByText('Harbour View Residence was updated successfully.')
    expect(updatedMessage.closest('.property-toast')).toHaveClass('property-toast--success')
  })

  it('does not expose a property outside the authenticated owned collection', async () => {
    renderApp('/properties/99999999-9999-9999-9999-999999999999/edit')

    expect(await screen.findByRole('heading', { name: 'Property unavailable' })).toBeInTheDocument()
    expect(screen.getByText(/not in your authenticated property portfolio/)).toBeInTheDocument()
    expect(screen.queryByLabelText('Property title')).not.toBeInTheDocument()
  })

  it('confirms unsaved cancellation and provides a working back-to-list control', async () => {
    const router = renderApp('/properties/new')
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false)

    await userEvent.type(screen.getByLabelText('Property title'), 'Unsaved home')
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }))

    expect(confirm).toHaveBeenCalledWith('You have unsaved property changes. Leave without saving them?')
    expect(router.state.location.pathname).toBe('/properties/new')

    confirm.mockReturnValue(true)
    await userEvent.click(screen.getByRole('button', { name: 'Back to My Properties' }))

    await waitFor(() => expect(router.state.location.pathname).toBe('/modules/manage-properties'))
  })

  it('cancels a clean form without showing an unsaved warning', async () => {
    const router = renderApp('/properties/new')
    const confirm = vi.spyOn(window, 'confirm')

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }))

    await waitFor(() => expect(router.state.location.pathname).toBe('/modules/manage-properties'))
    expect(confirm).not.toHaveBeenCalled()
  })
})
