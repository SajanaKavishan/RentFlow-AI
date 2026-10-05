import { act, cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import { AuthContext } from '../auth/useAuth.js'
import LandlordMaintenancePage from './pages/LandlordMaintenancePage.jsx'
import AiCoordinationCard from './components/AiCoordinationCard.jsx'

const propertyId = '88888888-8888-4888-8888-888888888888'
const requestId = '99999999-9999-4999-8999-999999999999'
const request = {
  id: requestId, propertyId, tenantId: 'tenant-1', technicianId: null,
  title: 'Broken bedroom air conditioner', description: 'The air conditioner will not start.',
  status: 0, category: 2, priority: 1,
}
const result = (overrides = {}) => ({
  suggestedCategory: 'Hvac', categoryConfidence: 'High',
  suggestedPriority: 'High', priorityConfidence: 'Medium',
  recommendedTechnicianCategory: 'Hvac', nextAction: 'triage',
  validationFlags: [{ code: 'CategoryDescriptionMismatch', message: 'Compare the issue description with the selected category.' }],
  rationale: 'The symptoms suggest an air-conditioning issue. Review the controls and repair scope.',
  requiresHumanReview: true, agentVersion: 'test-phase1', ...overrides,
})
const workflow = (overrides = {}, resultOverrides = {}) => ({
  id: 'workflow-1', maintenanceRequestId: requestId,
  status: 2, approvalStatus: 1, requiresHumanApproval: true,
  finalResultJson: JSON.stringify(result(resultOverrides)), ...overrides,
})
const response = (body, status = 200) =>
  new Response(body === undefined ? null : JSON.stringify(body), { status })

function renderPage() {
  return render(<MemoryRouter initialEntries={[`/modules/maintenance/landlord?propertyId=${propertyId}`]}>
    <AuthContext.Provider value={{ user: { id: 'landlord-1', role: 'Landlord' }, isAuthenticated: true }}>
      <LandlordMaintenancePage />
    </AuthContext.Provider>
  </MemoryRouter>)
}

function mockApi({ latest = null, requests = [request], onStart, onDecision, onLatest } = {}) {
  let saved = latest
  const fetchMock = vi.fn(async (url, options = {}) => {
    const path = new URL(String(url), 'http://localhost').pathname
    if (path.endsWith(`/property/${propertyId}`)) return response(requests)
    if (path.endsWith('/history')) return response([])
    if (path.endsWith('/estimates/latest')) return response(undefined, 204)
    if (path.endsWith('/coordination-workflows/latest')) {
      if (onLatest) return onLatest(path)
      return saved ? response(saved) : response(undefined, 204)
    }
    if (path.endsWith('/coordination-workflows') && options.method === 'POST') {
      const next = onStart ? await onStart(path, options) : response(workflow(), 201)
      if (next.ok) saved = await next.clone().json()
      return next
    }
    if (/\/coordination-workflows\/[^/]+\/(approve|reject)$/.test(path)) {
      if (onDecision) return onDecision(path, options)
      const accepted = path.endsWith('/approve')
      saved = { ...saved, status: accepted ? 3 : 4, approvalStatus: accepted ? 2 : 3 }
      return response(saved)
    }
    const selected = requests.find((item) => path.endsWith('/' + item.id))
    if (selected) return response(selected)
    throw new Error('Unexpected API request: ' + path)
  })
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

const writes = (mock) => mock.mock.calls.filter(([, options]) => ['POST', 'PATCH', 'PUT', 'DELETE'].includes(options?.method))
const aiCard = () => screen.getByRole('region', { name: 'AI Coordination' })

beforeEach(() => {
  tokenStorage.setToken('test-user-token')
  window.localStorage.removeItem(`rentflow.maintenance.workflow.${requestId}`)
})
afterEach(() => { cleanup(); tokenStorage.clearToken(); vi.unstubAllGlobals() })

describe('landlord AI Coordination', () => {
  it.each([
    [1, 1, 'Photo evidence: 1 photo analyzed.'],
    [3, 3, 'Photo evidence: 3 photos analyzed.'],
    [3, 2, 'Photo evidence: 2 of 3 photos analyzed.'],
    [3, 0, 'Photo evidence: 0 of 3 photos analyzed.'],
  ])('renders truthful persisted photo evidence counts (%i, %i)', async (suppliedPhotoCount, analyzedPhotoCount, wording) => {
    const mock = mockApi({ latest: workflow({ photoEvidence: { suppliedPhotoCount, analyzedPhotoCount } }) })
    renderPage()
    expect(await screen.findByText(wording)).toBeInTheDocument()
    expect(within(aiCard()).getByText(result().rationale)).toBeInTheDocument()
    expect(writes(mock)).toHaveLength(0)
    expect(aiCard().querySelector('img')).toBeNull()
  })

  it.each([undefined, null, {}, { suppliedPhotoCount: 0, analyzedPhotoCount: 0 },
    { suppliedPhotoCount: 3, analyzedPhotoCount: 4 }, { suppliedPhotoCount: '3', analyzedPhotoCount: 2 },
    { suppliedPhotoCount: 6, analyzedPhotoCount: 1 }, { suppliedPhotoCount: 3, analyzedPhotoCount: -1 },
    { suppliedPhotoCount: 3, analyzedPhotoCount: 1, mediaBase64: 'private-bytes', signedUrl: 'https://private.example/photo' },
  ])('omits absent or invalid photo metadata without exposing its content', async (photoEvidence) => {
    mockApi({ latest: workflow({ photoEvidence }) })
    renderPage()
    expect(await screen.findByText(result().rationale)).toBeInTheDocument()
    expect(within(aiCard()).queryByText(/Photo evidence:/)).not.toBeInTheDocument()
    expect(aiCard().textContent).not.toMatch(/private-bytes|private\.example|AI verified image/)
  })

  it('restores from the server and offers explicit analysis without generating a result automatically', async () => {
    const mock = mockApi()
    window.localStorage.setItem(`rentflow.maintenance.workflow.${requestId}`, 'obsolete-workflow')
    renderPage()
    expect(await screen.findByRole('button', { name: 'Analyze request' })).toBeEnabled()
    expect(within(aiCard()).queryByText('Suggested category')).not.toBeInTheDocument()
    expect(mock.mock.calls.some(([url]) => String(url).endsWith('/coordination-workflows/latest'))).toBe(true)
    expect(mock.mock.calls.some(([url]) => String(url).endsWith('/obsolete-workflow'))).toBe(false)
    expect(writes(mock)).toHaveLength(0)
  })

  it('renders the typed result with friendly labels, flags and plain-text rationale', async () => {
    const mock = mockApi({ latest: workflow() })
    renderPage()
    expect(await within(await screen.findByRole('region', { name: 'AI Coordination' })).findByText('HVAC / A/C')).toBeInTheDocument()
    const card = aiCard()
    expect(within(card).getByText('High confidence')).toBeInTheDocument()
    expect(within(card).getByText('Medium confidence')).toBeInTheDocument()
    expect(within(card).getByText('High')).toBeInTheDocument()
    expect(within(card).getByText('HVAC / A/C maintenance')).toBeInTheDocument()
    expect(within(card).getByText('Review and triage the request')).toBeInTheDocument()
    expect(within(card).getByText('Responsible: Landlord / Admin')).toBeInTheDocument()
    expect(within(card).getByText('Human review required')).toBeInTheDocument()
    expect(within(card).getByText('Check the selected category')).toBeInTheDocument()
    expect(within(card).getByText(result().rationale)).toBeInTheDocument()
    expect(card.textContent).not.toContain('suggestedCategory')
    expect(card.textContent).not.toContain('CategoryDescriptionMismatch')
    expect(card.textContent).not.toContain('workflow-1')
    expect(writes(mock)).toHaveLength(0)
  })

  it('contains loading, prevents duplicate analysis and leaves normal triage usable', async () => {
    let finish
    const mock = mockApi({ onStart: () => new Promise((resolve) => { finish = resolve }) })
    renderPage()
    const button = await screen.findByRole('button', { name: 'Analyze request' })
    await userEvent.dblClick(button)
    expect(within(aiCard()).getByRole('status')).toHaveTextContent('Analyzing maintenance request')
    expect(screen.getByRole('button', { name: 'Triage request' })).toBeEnabled()
    expect(within(aiCard()).queryByRole('button', { name: 'Analyze request' })).not.toBeInTheDocument()
    expect(writes(mock)).toHaveLength(1)
    await act(async () => finish(response(workflow(), 201)))
    expect(await screen.findByRole('button', { name: 'Accept recommendation' })).toBeEnabled()
    expect(writes(mock)).toHaveLength(1)
  })

  it('joins an in-flight analysis when the page is refreshed without allowing a duplicate POST', async () => {
    let finish
    const mock = mockApi({ onStart: () => new Promise((resolve) => { finish = resolve }) })
    renderPage()
    await userEvent.click(await screen.findByRole('button', { name: 'Analyze request' }))
    await userEvent.click(screen.getByRole('button', { name: 'Refresh' }))
    await waitFor(() => expect(within(aiCard()).getByRole('status')).toHaveTextContent('Analyzing maintenance request'))
    expect(within(aiCard()).queryByRole('button', { name: 'Analyze request' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Triage request' })).toBeEnabled()
    await act(async () => finish(response(workflow(), 201)))
    expect(await screen.findByRole('button', { name: 'Accept recommendation' })).toBeEnabled()
    expect(writes(mock)).toHaveLength(1)
  })

  it('supports keyboard activation of the explicit recommendation review', async () => {
    const mock = mockApi({ latest: workflow() })
    renderPage()
    const accept = await screen.findByRole('button', { name: 'Accept recommendation' })
    accept.focus()
    await userEvent.keyboard('{Enter}')
    expect(await screen.findByText('Recommendation accepted')).toBeInTheDocument()
    expect(writes(mock)).toHaveLength(1)
  })

  it.each([
    ['Accept recommendation', 'approve', 'Recommendation accepted'],
    ['Reject recommendation', 'reject', 'Recommendation rejected'],
  ])('records %s separately and restores the final review on reload', async (label, action, outcome) => {
    const mock = mockApi({ latest: workflow() })
    const view = renderPage()
    await screen.findByRole('button', { name: label })
    await userEvent.type(screen.getByLabelText('Review notes (optional)'), 'Reviewed the evidence.')
    await userEvent.click(screen.getByRole('button', { name: label }))
    expect(await screen.findByText(outcome)).toBeInTheDocument()
    expect(within(aiCard()).queryByRole('button', { name: 'Accept recommendation' })).not.toBeInTheDocument()
    expect(within(aiCard()).queryByRole('button', { name: 'Reject recommendation' })).not.toBeInTheDocument()
    const mutations = writes(mock)
    expect(mutations).toHaveLength(1)
    expect(String(mutations[0][0])).toMatch(new RegExp(`/workflow-1/${action}$`))
    expect(JSON.parse(mutations[0][1].body)).toEqual({ decisionNotes: 'Reviewed the evidence.' })
    expect(screen.getByRole('button', { name: 'Triage request' })).toBeEnabled()
    view.unmount()
    window.localStorage.removeItem(`rentflow.maintenance.workflow.${requestId}`)
    renderPage()
    expect(await screen.findByText(outcome)).toBeInTheDocument()
  })

  it('uses the returned decision state rather than assuming an acceptance occurred', async () => {
    mockApi({ latest: workflow(), onDecision: () => response(workflow()) })
    renderPage()
    await userEvent.click(await screen.findByRole('button', { name: 'Accept recommendation' }))
    await waitFor(() => expect(screen.getByRole('button', { name: 'Accept recommendation' })).toBeEnabled())
    expect(screen.queryByText('Recommendation accepted')).not.toBeInTheDocument()
  })

  it('shows uncertainty and null suggestions without fabricating recommendations', async () => {
    mockApi({ latest: workflow({}, {
      suggestedCategory: null, categoryConfidence: 'Unknown', suggestedPriority: null,
      priorityConfidence: 'Low', recommendedTechnicianCategory: null, nextAction: null,
    }) })
    renderPage()
    expect(await screen.findByText('Confidence unknown')).toBeInTheDocument()
    expect(within(aiCard()).getAllByText('Insufficient information')).toHaveLength(2)
    expect(within(aiCard()).getByText('Low confidence')).toBeInTheDocument()
    expect(within(aiCard()).getByText('No AI workflow action suggested')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Use suggestion in triage' })).toBeDisabled()
  })

  it('shows emergency human review and never changes the actual request', async () => {
    const mock = mockApi({ latest: workflow({}, { suggestedPriority: 'Emergency' }) })
    renderPage()
    expect(await screen.findByText('Urgent review needed')).toBeInTheDocument()
    expect(within(aiCard()).getByRole('alert')).toHaveTextContent('Confirm the situation')
    expect(screen.getByRole('combobox', { name: 'Priority' })).toHaveValue('Normal')
    expect(writes(mock)).toHaveLength(0)
  })

  it('only prefills triage after an explicit click and never saves it automatically', async () => {
    const mock = mockApi({ latest: workflow() })
    renderPage()
    await within(await screen.findByRole('region', { name: 'AI Coordination' })).findByText('HVAC / A/C')
    expect(screen.getByRole('combobox', { name: 'Category' })).toHaveValue('Appliance')
    await userEvent.click(screen.getByRole('button', { name: 'Use suggestion in triage' }))
    expect(screen.getByRole('combobox', { name: 'Category' })).toHaveValue('Hvac')
    expect(screen.getByRole('combobox', { name: 'Priority' })).toHaveValue('High')
    expect(await screen.findByText(/Submit triage separately to save/)).toBeInTheDocument()
    expect(writes(mock)).toHaveLength(0)
  })

  it('keeps a human Emergency selection when filling triage suggestions', async () => {
    const mock = mockApi({ latest: workflow(), requests: [{ ...request, priority: 3 }] })
    renderPage()
    await userEvent.click(await screen.findByRole('button', { name: 'Use suggestion in triage' }))
    expect(screen.getByRole('combobox', { name: 'Priority' })).toHaveValue('Emergency')
    expect(screen.getByText(/Emergency priority was kept/)).toBeInTheDocument()
    expect(writes(mock)).toHaveLength(0)
  })

  it.each([
    ['not-json'],
    [JSON.stringify({ suggestedCategory: 'Electrical', rationale: 'provider stack trace' })],
    [JSON.stringify(result({ suggestedCategory: 1 }))],
    [JSON.stringify(result({ requiresHumanReview: false }))],
    [JSON.stringify(result({ nextAction: 'automatically-assign' }))],
    [JSON.stringify(result({ validationFlags: [{ code: 'private-debug-data', message: 'secret' }] }))],
    [JSON.stringify({ recommendedCategory: 'plumbing', reasoning: 'Old model result' })],
  ])('safely handles malformed or historical result %s', async (finalResultJson) => {
    mockApi({ latest: workflow({ finalResultJson, errorMessage: 'https://agent.internal stack trace secret' }) })
    renderPage()
    expect(await screen.findByText('AI analysis unavailable')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Triage request' })).toBeEnabled()
    expect(within(aiCard()).queryByRole('button', { name: 'Accept recommendation' })).not.toBeInTheDocument()
    expect(aiCard().textContent).not.toMatch(/agent\.internal|stack trace|private-debug-data|Old model result/)
  })

  it('keeps workflow failures isolated and allows an explicit retry', async () => {
    let attempts = 0
    const mock = mockApi({ latest: workflow({ status: 4, approvalStatus: 0, finalResultJson: null }),
      onStart: () => ++attempts === 1 ? response({ detail: 'internal provider credential and stack trace' }, 502) : response(workflow(), 201) })
    renderPage()
    await userEvent.click(await screen.findByRole('button', { name: 'Try again' }))
    expect(await screen.findByText('AI analysis unavailable')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Triage request' })).toBeEnabled()
    expect(aiCard().textContent).not.toContain('credential')
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await within(await screen.findByRole('region', { name: 'AI Coordination' })).findByText('HVAC / A/C')).toBeInTheDocument()
    expect(writes(mock)).toHaveLength(2)
  })

  it('keeps review failure safe without changing business controls', async () => {
    mockApi({ latest: workflow(), onDecision: () => response({ detail: 'provider secret traceback' }, 502) })
    renderPage()
    await userEvent.click(await screen.findByRole('button', { name: 'Reject recommendation' }))
    expect(await screen.findByText(/Unable to record the recommendation review/)).toBeInTheDocument()
    expect(aiCard().textContent).not.toMatch(/secret|traceback/)
    expect(screen.getByRole('button', { name: 'Triage request' })).toBeEnabled()
    expect(screen.queryByText('Recommendation rejected')).not.toBeInTheDocument()
  })

  it('treats rationale as text and leaves HTML and Markdown inactive', async () => {
    const rationale = '<img src=x onerror="alert(1)"> **human review**'
    mockApi({ latest: workflow({}, { rationale }) })
    renderPage()
    expect(await screen.findByText(rationale)).toBeInTheDocument()
    expect(aiCard().querySelector('img')).toBeNull()
  })

  it('does not attach a late analysis to a different selected request', async () => {
    let finish
    const second = { ...request, id: 'second-request', title: 'Second issue' }
    mockApi({ requests: [request, second], onStart: () => new Promise((resolve) => { finish = resolve }) })
    renderPage()
    await userEvent.click(await screen.findByRole('button', { name: 'Analyze request' }))
    await userEvent.click(screen.getByRole('button', { name: /Second issue/ }))
    await screen.findByRole('button', { name: 'Analyze request' })
    await act(async () => finish(response(workflow(), 201)))
    expect(within(aiCard()).queryByText('HVAC / A/C')).not.toBeInTheDocument()
    expect(within(aiCard()).getByRole('button', { name: 'Analyze request' })).toBeInTheDocument()
  })
})

describe('friendly action and flag presentation', () => {
  const props = {
    request: { ...request, status: 'Submitted', priority: 'Normal' },
    state: 'success', pending: false, decisionNotes: '', onDecisionNotesChange: vi.fn(),
    onAnalyze: vi.fn(), onRefresh: vi.fn(), onDecision: vi.fn(),
  }

  it.each([
    ['triage', 'Review and triage the request', 'Landlord / Admin'],
    ['assign-technician', 'Assign a maintenance technician', 'Landlord / Admin'],
    ['estimate-pending', 'Request a repair estimate', 'Landlord / Admin'],
    ['submit-estimate', 'Technician should submit an estimate', 'Technician'],
    ['submit-for-review', 'Submit the estimate for landlord review', 'Technician'],
    ['review-estimate', 'Review the submitted estimate', 'Landlord / Admin'],
    ['start-work', 'Technician can start approved work', 'Technician'],
    ['complete-work', 'Technician can complete the work when finished', 'Technician'],
  ])('explains %s and its responsible actor', (nextAction, label, actor) => {
    render(<AiCoordinationCard {...props} workflow={workflow({ status: 'AwaitingHumanReview', approvalStatus: 'Pending' }, { nextAction })} />)
    expect(screen.getByText(label)).toBeInTheDocument()
    expect(screen.getByText('Responsible: ' + actor)).toBeInTheDocument()
  })

  it.each([
    ['InsufficientInformation', 'More information may be needed'],
    ['CategoryDescriptionMismatch', 'Check the selected category'],
    ['EstimateExplanationMissing', 'The estimate needs more detail'],
    ['EstimateScopeMismatch', 'Check the scope of the estimate'],
    ['PhotoUnavailable', 'Some photo evidence is unavailable'],
    ['PhotoUnreadable', 'Photo information is unclear'],
    ['UrgencyNeedsHumanReview', 'Urgency needs human review'],
  ])('renders %s as a readable consideration', (code, title) => {
    render(<AiCoordinationCard {...props} workflow={workflow({ status: 'AwaitingHumanReview', approvalStatus: 'Pending' },
      { validationFlags: [{ code, message: 'Review the supplied information.' }] })} />)
    expect(screen.getByText(title)).toBeInTheDocument()
    expect(screen.getByText('Review the supplied information.')).toBeInTheDocument()
    expect(aiCard().textContent).not.toContain(code)
  })

  it('restores a running workflow with a read-only progress check rather than another Analyze button', () => {
    render(<AiCoordinationCard {...props} workflow={workflow({ status: 'Running', approvalStatus: 'Pending', finalResultJson: null })} />)
    expect(screen.getByRole('status')).toHaveTextContent('Analyzing maintenance request')
    expect(screen.getByRole('button', { name: 'Check progress' })).toBeEnabled()
    expect(screen.queryByRole('button', { name: 'Analyze request' })).not.toBeInTheDocument()
  })
})
