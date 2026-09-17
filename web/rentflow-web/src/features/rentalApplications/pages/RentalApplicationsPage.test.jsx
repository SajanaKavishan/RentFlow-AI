import { cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import RentalApplicationsPage from './RentalApplicationsPage.jsx'

const propertyId = '22222222-2222-2222-2222-222222222222'
const tenantId = '11111111-1111-1111-1111-111111111111'

function application(overrides = {}) {
  return {
    id: '33333333-3333-3333-3333-333333333333',
    tenantId,
    propertyId,
    moveInDate: '2030-02-14',
    monthlyIncome: 6500,
    occupation: 'Product designer',
    numberOfOccupants: 2,
    tenantNote: 'We would like a long-term tenancy.',
    status: 1,
    landlordResponse: null,
    createdAt: '2026-09-10T08:00:00Z',
    submittedAt: '2026-09-11T09:30:00Z',
    updatedAt: '2026-09-12T10:45:00Z',
    ...overrides,
  }
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function mockApplicationApi(applications, options = {}) {
  const { documents = [], validationRuns = [], actionResponse } = options
  const fetchMock = vi.fn().mockImplementation((url, request = {}) => {
    if (url.includes('/documents')) {
      return Promise.resolve(jsonResponse(documents))
    }
    if (url.includes('/validation-runs')) {
      return Promise.resolve(jsonResponse(validationRuns))
    }
    if (request.method === 'PATCH' && actionResponse) {
      return Promise.resolve(jsonResponse(actionResponse))
    }
    return Promise.resolve(jsonResponse(applications))
  })
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

describe('Landlord rental applications', () => {
  it('prioritizes attention states and exposes every application status clearly', async () => {
    const applications = [
      application({ id: 'approved', status: 4 }),
      application({ id: 'withdrawn', status: 6 }),
      application({ id: 'changes', status: 3, landlordResponse: 'Upload a clearer identity document.' }),
      application({ id: 'rejected', status: 5 }),
      application({ id: 'review', status: 2 }),
      application({ id: 'draft', status: 0 }),
      application({ id: 'submitted', status: 1 }),
    ]
    mockApplicationApi(applications)

    render(<RentalApplicationsPage />)

    const cards = await screen.findAllByRole('article')
    expect(cards).toHaveLength(7)
    expect(within(cards[0]).getByLabelText('Application status: Submitted')).toBeInTheDocument()
    expect(within(cards[1]).getByLabelText('Application status: Under review')).toBeInTheDocument()
    expect(within(cards[2]).getByLabelText('Application status: Changes requested')).toBeInTheDocument()
    expect(within(cards[2]).getByText('Tenant update required')).toBeInTheDocument()
    expect(within(cards[2]).getByText('Upload a clearer identity document.')).toBeInTheDocument()

    for (const label of ['Draft', 'Approved', 'Rejected', 'Withdrawn']) {
      expect(screen.getByLabelText(`Application status: ${label}`)).toBeInTheDocument()
    }

    expect(within(cards[0]).getByText(tenantId)).toBeInTheDocument()
    expect(within(cards[0]).getByText(propertyId)).toBeInTheDocument()
    expect(screen.getAllByRole('button', { name: 'Approve' })).toHaveLength(2)
    expect(screen.getAllByRole('button', { name: 'Reject' })).toHaveLength(2)
    expect(screen.getAllByRole('button', { name: 'Request changes' })).toHaveLength(2)
  })

  it('shows API-backed document details in a readable review section', async () => {
    const currentApplication = application()
    const document = {
      id: '44444444-4444-4444-4444-444444444444',
      applicationId: currentApplication.id,
      documentType: 1,
      originalFileName: 'income-proof-september.pdf',
      contentType: 'application/pdf',
      fileSizeBytes: 204800,
      uploadedAt: '2026-09-11T11:20:00Z',
    }
    mockApplicationApi([currentApplication], { documents: [document] })

    render(<RentalApplicationsPage />)
    await userEvent.click(
      await screen.findByRole('button', {
        name: `Review documents for application ${currentApplication.id}`,
      }),
    )

    const review = await screen.findByRole('region', {
      name: 'Application documents',
    })
    expect(within(review).getByText('1 document')).toBeInTheDocument()
    expect(within(review).getByText('Income proof')).toBeInTheDocument()
    expect(within(review).getByText(document.originalFileName)).toBeInTheDocument()
    expect(within(review).getByText(document.id)).toBeInTheDocument()
    expect(within(review).getByText('application/pdf')).toBeInTheDocument()
    expect(within(review).getByRole('button', { name: 'Open document' })).toBeInTheDocument()
  })

  it('presents AwaitingHumanReview findings separately from landlord controls', async () => {
    const workflow = {
      id: '55555555-5555-5555-5555-555555555555',
      applicationId: '33333333-3333-3333-3333-333333333333',
      status: 2,
      currentStep: 4,
      completenessScore: 75,
      recommendation: 'Manual review required',
      requiresHumanApproval: true,
      createdAt: '2026-09-12T08:00:00Z',
      updatedAt: '2026-09-12T08:04:00Z',
      steps: [],
      summary: {
        applicationData: {
          missingFields: ['Occupation history'],
          warnings: ['Move-in date is close.'],
        },
        documents: {
          missingDocumentTypes: ['IdentityDocument'],
          warnings: ['Income proof needs confirmation.'],
        },
        deterministicRules: {
          passedRules: ['Applicant income was provided.'],
          failedRules: ['Identity document is required.'],
          warnings: [],
        },
        agenticReview: {
          recommendation: 'Review documents',
          summary: 'The supplied income evidence requires a human check.',
          keyFindings: ['Income evidence was detected.'],
          warnings: ['Do not rely on extracted values without opening the source document.'],
          requiresHumanApproval: true,
          agentVersion: '1.0',
          supportingDocumentVerification: [
            {
              documentId: '44444444-4444-4444-4444-444444444444',
              documentType: 'IncomeProof',
              readable: true,
              detectedDocumentCategory: 'Payslip',
              extractedFacts: { applicantName: 'API Applicant', incomeAmount: 6500 },
              warnings: ['Employer name could not be confirmed.'],
              confidenceLabel: 'Medium',
              extractionMethod: 'Text extraction',
              requiresManualReview: true,
            },
          ],
          crossDocumentConsistency: {
            matchedFacts: [{ comparison: 'Name', message: 'Applicant name matched.' }],
            mismatches: [],
            warnings: [],
            requiresManualReview: true,
          },
        },
      },
    }
    mockApplicationApi([application()], { validationRuns: [workflow] })

    render(<RentalApplicationsPage />)

    const aiReview = await screen.findByRole('region', {
      name: 'Application validation',
    })
    expect(
      await within(aiReview).findByText('Awaiting human review'),
    ).toBeInTheDocument()
    expect(within(aiReview).getByText('Human decision required.')).toBeInTheDocument()
    expect(within(aiReview).getByText('IdentityDocument')).toBeInTheDocument()
    expect(within(aiReview).getByText('Applicant income was provided.')).toBeInTheDocument()
    expect(within(aiReview).getByText('Identity document is required.')).toBeInTheDocument()
    expect(within(aiReview).getByText('Employer name could not be confirmed.')).toBeInTheDocument()
    expect(within(aiReview).getByText('Manual review: Required')).toBeInTheDocument()

    const decision = screen.getByRole('region', { name: 'Landlord decision' })
    expect(within(decision).getByRole('button', { name: 'Approve' })).toBeInTheDocument()
    expect(within(decision).getByRole('button', { name: 'Reject' })).toBeInTheDocument()
  })

  it('shows retryable page errors and a genuine empty state', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse({}, 500))
      .mockResolvedValueOnce(jsonResponse([]))
    vi.stubGlobal('fetch', fetchMock)

    render(<RentalApplicationsPage />)
    expect(screen.getByText('Loading rental applications')).toBeInTheDocument()
    expect(
      await screen.findByRole('heading', { name: 'We could not load the applications' }),
    ).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))

    expect(
      await screen.findByRole('heading', { name: 'No rental applications yet' }),
    ).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('keeps decision feedback and action availability aligned with API state', async () => {
    const submitted = application()
    const approved = application({ status: 4, landlordResponse: 'Application approved after review.' })
    const fetchMock = mockApplicationApi([submitted], { actionResponse: approved })

    render(<RentalApplicationsPage />)
    await userEvent.click(await screen.findByRole('button', { name: 'Approve' }))
    await userEvent.type(
      screen.getByLabelText('Response (optional)'),
      'Application approved after review.',
    )
    await userEvent.click(screen.getByRole('button', { name: 'Confirm' }))

    expect(await screen.findByRole('status')).toHaveTextContent('Application approved.')
    expect(screen.getByLabelText('Application status: Approved')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Approve' })).not.toBeInTheDocument()
    const patchCall = fetchMock.mock.calls.find(([, request]) => request?.method === 'PATCH')
    expect(patchCall[0]).toContain(`/api/rental-applications/${submitted.id}/approve`)
    expect(JSON.parse(patchCall[1].body)).toEqual({
      landlordResponse: 'Application approved after review.',
    })
  })
})
