import { act, cleanup, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { tokenStorage } from '../../../core/auth/tokenStorage.js'
import PricingAnalysisPage from './PricingAnalysisPage.jsx'

const firstId = '11111111-1111-1111-1111-111111111111'
const secondId = '22222222-2222-2222-2222-222222222222'
const workflowId = '33333333-3333-3333-3333-333333333333'
const properties = [{ id: firstId, title: 'Lake House', city: 'Kandy' }, { id: secondId, title: 'Garden Flat', city: 'Colombo' }]

function workflow(result) {
  return { workflowId, propertyId: secondId, status: 2, evidenceSufficiency: result.evidenceSufficiency, confidence: result.confidence, createdAt: '2026-09-27T10:00:00Z', completedAt: '2026-09-27T10:01:00Z', result, steps: [{ order: 1, name: 'Gather property facts', status: 2, outputSummary: 'Property facts loaded.', validationSummary: 'Valid.' }, { order: 4, name: 'Review evidence', status: 4 }] }
}

function response(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

function mockApi({ postResult, postStatus = 201, history = [] } = {}) {
  const fetchMock = vi.fn((url, options = {}) => {
    if (url.endsWith('/api/properties/mine')) return Promise.resolve(response(properties))
    if (options.method === 'POST') return Promise.resolve(response(postResult, postStatus))
    if (url.includes('/pricing-analysis-workflows/')) return Promise.resolve(response(postResult))
    return Promise.resolve(response(history))
  })
  vi.stubGlobal('fetch', fetchMock)
  tokenStorage.setToken('landlord-token')
  return fetchMock
}

async function selectSecondProperty() {
  await userEvent.selectOptions(await screen.findByLabelText('Property'), secondId)
}

afterEach(() => { cleanup(); vi.unstubAllGlobals(); tokenStorage.clearToken() })

describe('rental price analysis', () => {
  it('shows a completed numeric recommendation and workflow steps', async () => {
    mockApi({ postResult: workflow({ evidenceSufficiency: 'MODERATE', confidence: 'MEDIUM', recommendedMinRent: 60000, recommendedMaxRent: 70000, rationale: 'Comparable rents support this range.', citedEvidenceRefs: ['listing:1'] }) })
    render(<PricingAnalysisPage />)
    await selectSecondProperty()
    await userEvent.click(screen.getByRole('button', { name: 'Start analysis' }))
    expect(await screen.findByText('Comparable rents support this range.')).toBeInTheDocument()
    expect(screen.getByText('60,000')).toBeInTheDocument()
    expect(screen.getByText('70,000')).toBeInTheDocument()
    expect(screen.getByText('listing:1')).toBeInTheDocument()
    expect(screen.getByText('Gather property facts')).toBeInTheDocument()
    expect(screen.getByText('Skipped')).toBeInTheDocument()
  })

  it('treats insufficient evidence without numbers as a completed outcome', async () => {
    mockApi({ postResult: workflow({ evidenceSufficiency: 'INSUFFICIENT', confidence: 'LOW', recommendedMinRent: null, recommendedMaxRent: null, rationale: 'More comparable evidence is needed.' }) })
    render(<PricingAnalysisPage />)
    await selectSecondProperty()
    await userEvent.click(screen.getByRole('button', { name: 'Start analysis' }))
    expect(await screen.findByText(/completed with insufficient evidence/i)).toBeInTheDocument()
    expect(screen.getByText('More comparable evidence is needed.')).toBeInTheDocument()
    expect(screen.queryByText(/something went wrong/i)).not.toBeInTheDocument()
  })

  it('shows a safe API error when starting fails', async () => {
    mockApi({ postResult: { title: 'An unexpected error occurred.', detail: 'Internal provider trace' }, postStatus: 500 })
    render(<PricingAnalysisPage />)
    await selectSecondProperty()
    await userEvent.click(screen.getByRole('button', { name: 'Start analysis' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Unable to complete the pricing analysis')
    expect(screen.queryByText('Internal provider trace')).not.toBeInTheDocument()
  })

  it('posts to ASP.NET for the selected property with the stored bearer token', async () => {
    const fetchMock = mockApi({ postResult: workflow({ evidenceSufficiency: 'LIMITED', confidence: 'LOW', recommendedMinRent: 50000, recommendedMaxRent: 60000 }) })
    render(<PricingAnalysisPage />)
    await selectSecondProperty()
    await userEvent.click(screen.getByRole('button', { name: 'Start analysis' }))
    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining(`/api/properties/${secondId}/pricing-analysis-workflows`), expect.objectContaining({ method: 'POST', headers: expect.objectContaining({ Authorization: 'Bearer landlord-token' }) })))
    expect(fetchMock.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1)
  })

  it('loads property history and opens a previous workflow through the detail endpoint', async () => {
    const prior = workflow({ evidenceSufficiency: 'STRONG', confidence: 'HIGH', recommendedMinRent: 80000, recommendedMaxRent: 90000, rationale: 'Prior analysis.' })
    const fetchMock = mockApi({ history: [prior], postResult: prior })
    render(<PricingAnalysisPage />)
    await selectSecondProperty()
    await userEvent.click(await screen.findByRole('button', { name: 'View details' }))
    expect(await screen.findByText('Prior analysis.')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining(`/api/pricing-analysis-workflows/${workflowId}`), expect.any(Object))
  })

  it('keeps failed workflows distinct from insufficient evidence', async () => {
    const failed = { ...workflow({}), status: 3, result: null, evidenceSufficiency: null, confidence: null, errorMessage: 'The pricing analysis agent timed out.' }
    mockApi({ postResult: failed })
    render(<PricingAnalysisPage />)
    await selectSecondProperty()
    await userEvent.click(screen.getByRole('button', { name: 'Start analysis' }))
    expect(await screen.findByText('The pricing analysis agent timed out.')).toBeInTheDocument()
    expect(screen.queryByText(/completed with insufficient evidence/i)).not.toBeInTheDocument()
  })

  it('reloads history for the new property without showing the previous property history', async () => {
    let finishFirstHistory
    const firstHistory = new Promise((resolve) => { finishFirstHistory = resolve })
    const previous = workflow({ evidenceSufficiency: 'STRONG', confidence: 'HIGH', recommendedMinRent: 80000, recommendedMaxRent: 90000 })
    const fetchMock = vi.fn((url) => {
      if (url.endsWith('/api/properties/mine')) return Promise.resolve(response(properties))
      if (url.includes(`/api/properties/${firstId}/pricing-analysis-workflows`)) return firstHistory
      if (url.includes(`/api/properties/${secondId}/pricing-analysis-workflows`)) return Promise.resolve(response([previous]))
      return Promise.resolve(response(previous))
    })
    vi.stubGlobal('fetch', fetchMock)
    tokenStorage.setToken('landlord-token')
    render(<PricingAnalysisPage />)
    await userEvent.selectOptions(await screen.findByLabelText('Property'), firstId)
    expect(await screen.findByText('Loading analysis history…')).toBeInTheDocument()
    await userEvent.selectOptions(screen.getByLabelText('Property'), secondId)
    expect(await screen.findByRole('button', { name: 'View details' })).toBeInTheDocument()
    await act(async () => { finishFirstHistory(response([])) })
    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining(`/api/properties/${secondId}/pricing-analysis-workflows`), expect.any(Object)))
    expect(screen.getAllByRole('button', { name: 'View details' })).toHaveLength(1)
  })
})
