import { cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import { AuthProvider } from '../../features/auth/AuthContext.jsx'
import { AuthContext } from '../../features/auth/useAuth.js'
import ProfilePage from './ProfilePage.jsx'

const applicationId = '22222222-2222-2222-2222-222222222222'
const documentId = '33333333-3333-3333-3333-333333333333'
const account = (role) => ({ id: '11111111-1111-1111-1111-111111111111', fullName: 'Amara Silva', email: 'amara@example.com', phoneNumber: '+94 77 123 4567', role })
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

function renderProfile(role = 'Tenant') {
  const logout = vi.fn()
  const result = render(<MemoryRouter><AuthContext.Provider value={{ user: account(role), logout, isAuthenticated: true, isLoading: false }}><ProfilePage /></AuthContext.Provider></MemoryRouter>)
  return { ...result, logout }
}

beforeEach(() => { tokenStorage.setToken('profile-token'); vi.stubGlobal('fetch', vi.fn()) })
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.unstubAllGlobals(); vi.restoreAllMocks() })

describe('shared profile', () => {
  it.each(['Tenant', 'Landlord', 'MaintenanceTechnician', 'Admin'])('shows real account details and unavailable actions for %s', (role) => {
    const { container } = renderProfile(role)
    expect(screen.getByRole('heading', { name: 'Profile' })).toBeInTheDocument()
    expect(container.querySelector('.profile-identity')).toHaveTextContent('ASAmara Silvaamara@example.com')
    expect(container.querySelector('.profile-identity')).not.toHaveTextContent(role)
    for (const section of ['Account', 'Preferences', 'Support']) expect(screen.getByRole('region', { name: section })).toBeInTheDocument()
    const accountSection = screen.getByRole('region', { name: 'Account' })
    expect(within(accountSection).getByText('+94 77 123 4567')).toBeInTheDocument()
    for (const name of ['Edit profile', 'Change password', 'Notifications', 'Language', 'Contact support']) {
      expect(screen.getByRole('button', { name: new RegExp(name) })).toBeDisabled()
    }
    expect(screen.getByRole('button', { name: /Sign out/ })).toBeEnabled()
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
    expect(Boolean(screen.queryByRole('button', { name: /Application documents/ }))).toBe(role === 'Tenant')
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

  it('keeps disabled actions out of keyboard activation and signs out through the existing session', async () => {
    const api = { getCurrentUser: vi.fn().mockResolvedValue(account('Tenant')) }
    render(<MemoryRouter initialEntries={['/profile']}><AuthProvider api={api}><App /></AuthProvider></MemoryRouter>)
    const documents = await screen.findByRole('button', { name: /Application documents/ })
    await userEvent.tab()
    // The shared shell provides earlier focus targets; focus the live profile action directly.
    documents.focus()
    await userEvent.tab()
    expect(screen.getByRole('button', { name: /Sign out/ })).toHaveFocus()
    await userEvent.keyboard('{Enter}')
    expect(await screen.findByRole('heading', { name: 'Sign in to RentFlow' })).toBeInTheDocument()
    expect(tokenStorage.getToken()).toBeNull()
  })
})
