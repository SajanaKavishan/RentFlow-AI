import { cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import ApplicationValidationReportPage from './ApplicationValidationReportPage.jsx'

const propertyId = '22222222-2222-2222-2222-222222222222'
const applicationId = '33333333-3333-3333-3333-333333333333'
const tenantId = '11111111-1111-1111-1111-111111111111'

const application = {
  id: applicationId,
  tenantId,
  propertyId,
  moveInDate: '2030-02-14',
  monthlyIncome: 6500,
  occupation: 'API occupation',
  numberOfOccupants: 2,
  status: 2,
  createdAt: '2026-09-10T08:00:00Z',
  submittedAt: '2026-09-11T09:30:00Z',
  updatedAt: '2026-09-12T10:45:00Z',
}

const workflow = {
  id: '55555555-5555-5555-5555-555555555555',
  applicationId,
  objective: 'API workflow objective',
  status: 2,
  currentStep: 4,
  completenessScore: 75,
  recommendation: 'Manual review required',
  requiresHumanApproval: true,
  createdAt: '2026-09-12T08:00:00Z',
  updatedAt: '2026-09-12T08:04:00Z',
  steps: [
    { agentName: 'Application Data Validator', stepOrder: 1, status: 2, result: {}, completedAt: '2026-09-12T08:01:00Z' },
    { agentName: 'Document Validation Agent', stepOrder: 2, status: 2, result: {}, completedAt: '2026-09-12T08:02:00Z' },
    { agentName: 'Deterministic Rule Checker', stepOrder: 3, status: 2, result: {}, completedAt: '2026-09-12T08:03:00Z' },
    { agentName: 'Agentic Application Review', stepOrder: 4, status: 2, result: {}, completedAt: '2026-09-12T08:04:00Z' },
  ],
  summary: {
    applicationData: {
      isValid: false,
      completenessScore: 75,
      missingFields: ['API missing field'],
      warnings: ['API application warning'],
    },
    documents: {
      isValid: false,
      presentDocumentTypes: ['IncomeProof'],
      missingDocumentTypes: ['IdentityDocument'],
      warnings: ['API document warning'],
    },
    deterministicRules: {
      passed: false,
      passedRules: ['API passing rule'],
      failedRules: ['API failed rule'],
      warnings: [],
    },
    agenticReview: {
      recommendation: 'Review documents',
      summary: 'API advisory summary',
      keyFindings: ['API key finding'],
      warnings: ['API AI warning'],
      requiresHumanApproval: true,
      agentVersion: 'api-version',
      supportingDocumentVerification: [{
        documentId: '44444444-4444-4444-4444-444444444444',
        documentType: 'IncomeProof',
        readable: true,
        detectedDocumentCategory: 'API category',
        extractedFacts: { applicantName: 'API extracted name', incomeAmount: 6500 },
        warnings: ['API document finding'],
        confidenceLabel: 'API confidence label',
        extractionMethod: 'API extraction method',
        requiresManualReview: true,
      }],
      crossDocumentConsistency: {
        matchedFacts: [{ comparison: 'API comparison', message: 'API matched fact' }],
        mismatches: [],
        warnings: [],
        requiresManualReview: true,
      },
    },
  },
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function renderReport(entry = `/properties/${propertyId}/rental-applications/${applicationId}/validation`) {
  return render(<MemoryRouter initialEntries={[entry]}><Routes>
    <Route path="/properties/:propertyId/rental-applications/:applicationId/validation" element={<ApplicationValidationReportPage />} />
    <Route path="/rental-applications/:applicationId/validation" element={<ApplicationValidationReportPage />} />
  </Routes></MemoryRouter>)
}

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

describe('AI validation report', () => {
  it('renders the authorized application and only API-backed workflow findings', async () => {
    vi.stubGlobal('fetch', vi.fn((url) => Promise.resolve(json(
      url.includes('/validation-runs') ? [workflow] : application,
    ))))
    renderReport()

    expect(await screen.findByRole('heading', { name: 'AI Validation Report' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to Applications' }))
      .toHaveAttribute('href', `/properties/${propertyId}/rental-applications`)
    expect(screen.getByText(applicationId)).toBeInTheDocument()
    expect(screen.getByText(propertyId)).toBeInTheDocument()
    expect(screen.getByLabelText('Application status: Under review')).toBeInTheDocument()

    const validation = await screen.findByRole('region', { name: 'Application validation' })
    expect(within(validation).getByText('Awaiting human review')).toBeInTheDocument()
    expect(within(validation).getByText('4/4')).toBeInTheDocument()
    expect(within(validation).getByText('Manual review required')).toBeInTheDocument()
    expect(within(validation).getAllByText('API AI warning').length).toBeGreaterThan(0)
    expect(within(validation).getByText('API advisory summary')).toBeInTheDocument()
    expect(within(validation).getByText('API confidence label')).toBeInTheDocument()
    expect(within(validation).getByText('API extraction method')).toBeInTheDocument()

    const applicationStep = within(validation).getByText('Application Data Validator').closest('details')
    await userEvent.click(applicationStep.querySelector('summary'))
    expect(within(applicationStep).getByText('API missing field')).toBeInTheDocument()
    const documentStep = within(validation).getByText('Document Validation Agent').closest('details')
    await userEvent.click(documentStep.querySelector('summary'))
    expect(within(documentStep).getByText('IdentityDocument')).toBeInTheDocument()
    const rulesStep = within(validation).getByText('Deterministic Rule Checker').closest('details')
    await userEvent.click(rulesStep.querySelector('summary'))
    expect(within(rulesStep).getByText('API failed rule')).toBeInTheDocument()

    const decision = screen.getByRole('region', { name: 'Landlord decision' })
    expect(within(decision).getByRole('button', { name: 'Approve' })).toBeInTheDocument()
    expect(within(decision).getByRole('button', { name: 'Request more information' })).toBeInTheDocument()
    expect(within(decision).getByRole('button', { name: 'Reject' })).toBeInTheDocument()
    expect(screen.getByText(/Final rental decisions remain human-controlled/)).toBeInTheDocument()
  })

  it('requires rejection feedback and updates only after the decision API succeeds', async () => {
    const rejected = { ...application, status: 5, landlordResponse: 'API rejection reason' }
    const fetchMock = vi.fn((url, request = {}) => {
      if (request.method === 'PATCH') return Promise.resolve(json(rejected))
      return Promise.resolve(json(url.includes('/validation-runs') ? [] : application))
    })
    vi.stubGlobal('fetch', fetchMock)
    renderReport()
    const decision = await screen.findByRole('region', { name: 'Landlord decision' })
    await userEvent.click(within(decision).getByRole('button', { name: 'Reject' }))
    await userEvent.click(within(decision).getByRole('button', { name: 'Confirm' }))
    expect(within(decision).getByRole('alert')).toHaveTextContent('Enter a reason')
    expect(fetchMock.mock.calls.filter(([, request]) => request?.method === 'PATCH')).toHaveLength(0)

    await userEvent.type(within(decision).getByLabelText('Rejection reason'), 'API rejection reason')
    await userEvent.click(within(decision).getByRole('button', { name: 'Confirm' }))
    expect(await screen.findByRole('status')).toHaveTextContent('Application rejected.')
    expect(screen.getByLabelText('Application status: Rejected')).toBeInTheDocument()
    expect(screen.queryByRole('region', { name: 'Landlord decision' })).not.toBeInTheDocument()
    const patchCall = fetchMock.mock.calls.find(([, request]) => request?.method === 'PATCH')
    expect(patchCall[0]).toContain(`/api/rental-applications/${applicationId}/reject`)
    expect(JSON.parse(patchCall[1].body)).toEqual({ landlordResponse: 'API rejection reason' })
  })

  it('retains the property-required state without calling public properties', () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)
    renderReport(`/rental-applications/${applicationId}/validation`)
    expect(screen.getByRole('heading', { name: 'Select a property' })).toBeInTheDocument()
    expect(fetchMock).not.toHaveBeenCalled()
  })
})
