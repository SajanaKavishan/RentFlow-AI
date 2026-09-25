import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import { AuthProvider } from '../../features/auth/AuthContext.jsx'
import { AuthContext } from '../../features/auth/useAuth.js'
import {
  getNotificationPreferences,
  updateNotificationPreferences,
} from '../../features/notifications/notificationPreferencesApi.js'
import ProfilePage from './ProfilePage.jsx'

vi.mock('../../features/notifications/notificationPreferencesApi.js', () => ({
  getNotificationPreferences: vi.fn(),
  updateNotificationPreferences: vi.fn(),
}))

const applicationId = '22222222-2222-2222-2222-222222222222'
const documentId = '33333333-3333-3333-3333-333333333333'
const account = (role) => ({ id: '11111111-1111-1111-1111-111111111111', fullName: 'Amara Silva', email: 'amara@example.com', phoneNumber: '+94 77 123 4567', role })
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

function renderProfile(role = 'Tenant') {
  const updateProfile = vi.fn().mockResolvedValue(account(role))
  const uploadProfileImage = vi.fn().mockResolvedValue({ ...account(role), hasProfileImage: true })
  const result = render(<MemoryRouter><AuthContext.Provider value={{ user: account(role), updateProfile, uploadProfileImage, isAuthenticated: true, isLoading: false }}><ProfilePage /></AuthContext.Provider></MemoryRouter>)
  return { ...result, updateProfile, uploadProfileImage }
}

beforeEach(() => {
  tokenStorage.setToken('profile-token')
  vi.stubGlobal('fetch', vi.fn())
  getNotificationPreferences.mockResolvedValue({
    viewingUpdatesEnabled: true,
    rentalApplicationUpdatesEnabled: true,
    accountSecurityUpdatesEnabled: true,
  })
  updateNotificationPreferences.mockResolvedValue({
    viewingUpdatesEnabled: true,
    rentalApplicationUpdatesEnabled: true,
    accountSecurityUpdatesEnabled: true,
  })
})
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.unstubAllGlobals(); vi.restoreAllMocks() })

describe('shared profile', () => {
  it.each(['Tenant', 'Landlord', 'MaintenanceTechnician', 'Admin'])('shows real account details and notification preferences for %s', async (role) => {
    const { container } = renderProfile(role)
    expect(screen.getByRole('heading', { name: 'Profile' })).toBeInTheDocument()
    expect(container.querySelector('.profile-identity')).toHaveTextContent('ASAmara Silvaamara@example.com')
    expect(container.querySelector('.profile-identity')).not.toHaveTextContent(role)
    for (const section of ['Account', 'Preferences', 'Support']) expect(screen.getByRole('region', { name: section })).toBeInTheDocument()
    const accountSection = screen.getByRole('region', { name: 'Account' })
    expect(within(accountSection).getByText('+94 77 123 4567')).toBeInTheDocument()
    for (const name of ['Change password', 'Contact support']) {
      expect(screen.getByRole('button', { name: new RegExp(name) })).toBeDisabled()
    }
    expect(await screen.findByRole('checkbox', { name: /Viewing updates/ })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: /Rental application updates/ })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: /Account & security updates/ })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: /Account & security updates/ })).toBeDisabled()
    expect(screen.getByText('On / Required')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Save preferences' })).toBeDisabled()
    expect(screen.getByRole('button', { name: /Edit profile/ })).toBeEnabled()
    expect(screen.queryByRole('button', { name: /Sign out/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Language/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
    expect(Boolean(screen.queryByRole('button', { name: /Application documents/ }))).toBe(role === 'Tenant')
  })

  it('shows notification preference loading and load-retry states', async () => {
    let rejectLoad
    getNotificationPreferences.mockReturnValueOnce(new Promise((resolve, reject) => { rejectLoad = reject }))
    renderProfile('Landlord')
    expect(screen.getByRole('status')).toHaveTextContent('Loading notification preferences')
    rejectLoad(new Error('Notification preferences could not be loaded.'))
    expect(await screen.findByRole('alert')).toHaveTextContent('Notification preferences could not be loaded.')

    getNotificationPreferences.mockResolvedValueOnce({
      viewingUpdatesEnabled: false,
      rentalApplicationUpdatesEnabled: true,
      accountSecurityUpdatesEnabled: true,
    })
    await userEvent.click(screen.getByRole('button', { name: 'Retry' }))
    expect(await screen.findByRole('checkbox', { name: /Viewing updates/ })).not.toBeChecked()
    expect(getNotificationPreferences).toHaveBeenCalledTimes(2)
  })

  it('waits for API confirmation before reporting a saved preference', async () => {
    let confirmSave
    updateNotificationPreferences.mockReturnValueOnce(new Promise((resolve) => { confirmSave = resolve }))
    renderProfile('Admin')
    const viewingToggle = await screen.findByRole('checkbox', { name: /Viewing updates/ })
    await userEvent.click(viewingToggle)
    await userEvent.click(screen.getByRole('button', { name: 'Save preferences' }))

    expect(updateNotificationPreferences).toHaveBeenCalledWith(expect.objectContaining({
      viewingUpdatesEnabled: false,
      rentalApplicationUpdatesEnabled: true,
    }))
    expect(screen.getByRole('status')).toHaveTextContent('Saving notification preferences')
    expect(screen.queryByText('Notification preferences saved.')).not.toBeInTheDocument()

    confirmSave({
      viewingUpdatesEnabled: false,
      rentalApplicationUpdatesEnabled: true,
      accountSecurityUpdatesEnabled: true,
    })
    expect((await screen.findAllByText('Notification preferences saved.')).length).toBeGreaterThan(0)
    expect(viewingToggle).not.toBeChecked()
  })

  it('keeps failed notification changes unconfirmed and supports save retry', async () => {
    updateNotificationPreferences
      .mockRejectedValueOnce(new Error('Notification preferences could not be saved.'))
      .mockResolvedValueOnce({
        viewingUpdatesEnabled: true,
        rentalApplicationUpdatesEnabled: false,
        accountSecurityUpdatesEnabled: true,
      })
    renderProfile('MaintenanceTechnician')
    const applicationToggle = await screen.findByRole('checkbox', { name: /Rental application updates/ })
    await userEvent.click(applicationToggle)
    await userEvent.click(screen.getByRole('button', { name: 'Save preferences' }))

    const errors = await screen.findAllByRole('alert')
    expect(errors.some((alert) => alert.textContent.includes('Your previous settings are still saved.'))).toBe(true)
    expect(screen.queryByText('Notification preferences saved.')).not.toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect((await screen.findAllByText('Notification preferences saved.')).length).toBeGreaterThan(0)
    expect(updateNotificationPreferences).toHaveBeenCalledTimes(2)
  })

  it('updates profile fields and uploads a validated local image', async () => {
    const NativeURL = URL
    const createObjectURL = vi.fn(() => 'blob:profile-preview')
    const revokeObjectURL = vi.fn()
    vi.stubGlobal('URL', class extends NativeURL {
      static createObjectURL = createObjectURL
      static revokeObjectURL = revokeObjectURL
    })
    const { updateProfile, uploadProfileImage } = renderProfile('Admin')
    await userEvent.click(screen.getByRole('button', { name: /Edit profile/ }))
    expect(screen.getByRole('button', { name: 'Save profile' })).toBeDisabled()
    await userEvent.clear(screen.getByLabelText('Full name'))
    await userEvent.type(screen.getByLabelText('Full name'), 'Updated Admin')
    expect(screen.getByRole('button', { name: 'Save profile' })).toBeEnabled()
    await userEvent.clear(screen.getByLabelText('Phone number'))
    await userEvent.type(screen.getByLabelText('Phone number'), '+94 71 222 3333')
    const image = new File([new Uint8Array([0x89, 0x50, 0x4E, 0x47])], 'avatar.png', { type: 'image/png' })
    await userEvent.upload(screen.getByLabelText(/Profile image/), image)
    expect(document.querySelector('.profile-identity__avatar img')).toHaveAttribute('src', 'blob:profile-preview')
    await userEvent.click(screen.getByRole('button', { name: 'Save profile' }))
    await waitFor(() => expect(updateProfile).toHaveBeenCalledWith({ fullName: 'Updated Admin', phoneNumber: '+94 71 222 3333' }))
    expect(uploadProfileImage).toHaveBeenCalledWith(image)
    expect(await screen.findByText('Profile updated successfully.')).toBeInTheDocument()
  })

  it('rejects unsupported or oversized local images before upload', async () => {
    const { uploadProfileImage } = renderProfile('Admin')
    await userEvent.click(screen.getByRole('button', { name: /Edit profile/ }))
    await userEvent.upload(screen.getByLabelText(/Profile image/), new File(['text'], 'avatar.txt', { type: 'text/plain' }), { applyAccept: false })
    expect(screen.getByRole('alert')).toHaveTextContent('Choose a JPEG, PNG, or WEBP image.')
    expect(uploadProfileImage).not.toHaveBeenCalled()
  })

  it('automatically hides profile error notifications after three seconds', () => {
    vi.useFakeTimers()
    try {
      renderProfile('Admin')
      fireEvent.click(screen.getByRole('button', { name: /Edit profile/ }))
      fireEvent.change(screen.getByLabelText(/Profile image/), {
        target: { files: [new File(['text'], 'avatar.txt', { type: 'text/plain' })] },
      })
      expect(screen.getByRole('alert')).toHaveTextContent('Choose a JPEG, PNG, or WEBP image.')
      act(() => vi.advanceTimersByTime(3000))
      expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    } finally {
      vi.useRealTimers()
    }
  })

  it('loads only the signed-in tenant’s applications and their authorized documents on demand', async () => {
    fetch.mockImplementation((url) => {
      if (url.endsWith('/api/rental-applications')) return Promise.resolve(json([{ id: applicationId }]))
      if (url.endsWith(`/api/rental-applications/${applicationId}/documents`)) return Promise.resolve(json([{ id: documentId, applicationId, documentType: 1, originalFileName: 'income.pdf', fileSizeBytes: 1024, uploadedAt: '2026-09-01T00:00:00Z' }]))
      return Promise.reject(new Error(`Unexpected request: ${url}`))
    })
    renderProfile()
    const documents = screen.getByRole('button', { name: /Application documents/ })
    expect(fetch).not.toHaveBeenCalled()
    await userEvent.click(documents)
    expect(documents).toHaveAttribute('aria-expanded', 'true')
    const application = await screen.findByRole('button', { name: new RegExp(applicationId) })
    expect(fetch).toHaveBeenCalledTimes(1)
    await userEvent.click(application)
    expect(application).toHaveAttribute('aria-expanded', 'true')
    expect(await screen.findByText('income.pdf')).toBeInTheDocument()
    expect(fetch.mock.calls.map(([url]) => new URL(url, 'http://localhost').pathname)).toEqual([
      '/api/rental-applications', `/api/rental-applications/${applicationId}/documents`,
    ])
    expect(fetch.mock.calls.every(([, options]) => options.headers.Authorization === 'Bearer profile-token')).toBe(true)
  })

  it('opens a document through the existing authenticated download API', async () => {
    const popup = { opener: {}, location: { replace: vi.fn() }, close: vi.fn() }
    vi.stubGlobal('open', vi.fn(() => popup))
    vi.stubGlobal('URL', class extends URL {
      static createObjectURL = vi.fn(() => 'blob:profile-document')
      static revokeObjectURL = vi.fn()
    })
    fetch.mockImplementation((url) => {
      if (url.endsWith('/api/rental-applications')) return Promise.resolve(json([{ id: applicationId }]))
      if (url.endsWith(`/api/rental-applications/${applicationId}/documents`)) return Promise.resolve(json([{ id: documentId, applicationId, documentType: 0, originalFileName: 'identity.pdf', fileSizeBytes: 10, uploadedAt: '2026-09-01T00:00:00Z' }]))
      if (url.endsWith(`/api/application-documents/${documentId}/download`)) return Promise.resolve(new Response('file', { status: 200 }))
      return Promise.reject(new Error(`Unexpected request: ${url}`))
    })
    renderProfile()
    await userEvent.click(screen.getByRole('button', { name: /Application documents/ }))
    await userEvent.click(await screen.findByRole('button', { name: new RegExp(applicationId) }))
    await screen.findByText('identity.pdf')
    await userEvent.click(screen.getByRole('button', { name: 'Open document' }))
    expect(fetch).toHaveBeenCalledWith(expect.stringContaining(`/api/application-documents/${documentId}/download`), expect.objectContaining({ headers: expect.objectContaining({ Authorization: 'Bearer profile-token' }) }))
    await waitFor(() => expect(popup.location.replace).toHaveBeenCalledWith('blob:profile-document'))
    expect(popup.opener).toBeNull()
  })

  it('shows empty and retry states without treating a failed request as no documents', async () => {
    fetch.mockResolvedValueOnce(json({}, 500)).mockResolvedValueOnce(json([{ id: applicationId }])).mockResolvedValueOnce(json({}, 500)).mockResolvedValueOnce(json([]))
    renderProfile()
    await userEvent.click(screen.getByRole('button', { name: /Application documents/ }))
    expect(await screen.findByRole('alert')).toHaveTextContent('rental application request failed')
    await userEvent.click(screen.getByRole('button', { name: 'Retry applications' }))
    await userEvent.click(await screen.findByRole('button', { name: new RegExp(applicationId) }))
    expect(await screen.findByRole('alert')).toHaveTextContent('document request failed')
    await userEvent.click(screen.getByRole('button', { name: 'Retry documents' }))
    expect(await screen.findByText('No documents have been added to this application.')).toBeInTheDocument()
  })

  it('keeps removed account actions out of the page and opens the editor from the keyboard', async () => {
    const api = { getCurrentUser: vi.fn().mockResolvedValue(account('Tenant')) }
    render(<MemoryRouter initialEntries={['/profile']}><AuthProvider api={api}><App /></AuthProvider></MemoryRouter>)
    const documents = await screen.findByRole('button', { name: /Application documents/ })
    await userEvent.tab()
    // The shared shell provides earlier focus targets; focus the live profile action directly.
    documents.focus()
    await userEvent.tab()
    expect(screen.getByRole('button', { name: /Edit profile/ })).toHaveFocus()
    await userEvent.keyboard('{Enter}')
    expect(screen.getByRole('form', { name: 'Edit profile' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Sign out/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Language/ })).not.toBeInTheDocument()
  })
})
