import { useEffect, useState } from 'react'
import {
  ApplicationValidationApiError,
  getApplicationValidationRuns,
  runApplicationValidation,
} from '../services/applicationValidationApiService.js'

const dateTimeFormatter = new Intl.DateTimeFormat(undefined, {
  dateStyle: 'medium',
  timeStyle: 'short',
})

const WORKFLOW_STATUS = [
  'Pending',
  'Running',
  'Awaiting human review',
  'Completed',
  'Failed',
]

const STEP_STATUS = ['Pending', 'Running', 'Completed', 'Failed', 'Skipped']

function enumLabel(value, labels) {
  if (typeof value === 'number') return labels[value] || 'Unknown'
  if (typeof value !== 'string') return 'Unknown'
  return value.replace(/([a-z])([A-Z])/g, '$1 $2')
}

function formatDateTime(value) {
  const date = new Date(value)
  return Number.isNaN(date.getTime())
    ? 'Date unavailable'
    : dateTimeFormatter.format(date)
}

function formatScore(value) {
  const score = Number(value)
  return Number.isFinite(score) ? `${score.toFixed(2).replace(/\.00$/, '')}%` : 'Pending'
}

function safeErrorMessage(error) {
  return error instanceof ApplicationValidationApiError
    ? error.message
    : 'Unable to load application validation. Please try again.'
}

function humanizeKey(value) {
  return value
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/^./, (letter) => letter.toUpperCase())
}

function displayValue(value) {
  if (typeof value === 'boolean') return value ? 'Yes' : 'No'
  if (value === null || value === undefined || value === '') return 'None'
  if (Array.isArray(value)) {
    const displayItems = value.filter(
      (item) => ['string', 'number', 'boolean'].includes(typeof item),
    )
    return displayItems.length ? displayItems.join(', ') : 'None'
  }
  if (typeof value === 'object') return 'See structured details below'
  return String(value)
}

function displayFinding(item) {
  if (typeof item === 'string') return item
  if (item && typeof item.message === 'string') return item.message
  return null
}

function FindingList({ title, items, emptyMessage, tone = '' }) {
  const findings = (Array.isArray(items) ? items : [])
    .map(displayFinding)
    .filter(Boolean)

  return (
    <div className={`validation-findings__group${tone ? ` validation-findings__group--${tone}` : ''}`}>
      <h5>{title}</h5>
      {findings.length ? (
        <ul>
          {findings.map((item, index) => (
            <li key={`${item}-${index}`}>{item}</li>
          ))}
        </ul>
      ) : (
        <p>{emptyMessage}</p>
      )}
    </div>
  )
}

const DOCUMENT_FACT_FIELDS = {
  IncomeProof: [
    ['applicantName', 'Applicant name'],
    ['incomeAmount', 'Income amount'],
    ['payPeriod', 'Pay period'],
    ['employerName', 'Employer name'],
    ['documentDate', 'Document date'],
  ],
  EmploymentLetter: [
    ['applicantName', 'Applicant name'],
    ['jobTitle', 'Job title'],
    ['employerName', 'Employer name'],
    ['documentDate', 'Document date'],
  ],
  IdentityDocument: [['applicantName', 'Applicant name']],
}

function formatFactValue(key, value) {
  if (key === 'incomeAmount') {
    const amount = Number(value)
    return Number.isFinite(amount)
      ? new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(amount)
      : displayValue(value)
  }
  return displayValue(value)
}

function SupportingDocumentCard({ document }) {
  const facts = document.extractedFacts || {}
  const factFields = DOCUMENT_FACT_FIELDS[document.documentType] || []
  const populatedFacts = factFields.filter(
    ([key]) => facts[key] !== null && facts[key] !== undefined && facts[key] !== '',
  )

  return (
    <article className="supporting-document-card">
      <div className="supporting-document-card__header">
        <h6>{document.documentType || 'Supporting document'}</h6>
        <span
          className={`supporting-document-card__review supporting-document-card__review--${document.requiresManualReview ? 'required' : 'clear'}`}
        >
          Manual review: {document.requiresManualReview ? 'Required' : 'Not required'}
        </span>
      </div>

      <dl className="supporting-document-card__metadata">
        <div><dt>Readable</dt><dd>{document.readable ? 'Yes' : 'No'}</dd></div>
        <div><dt>Detected category</dt><dd>{document.detectedDocumentCategory || 'Unknown'}</dd></div>
        <div><dt>Confidence</dt><dd>{document.confidenceLabel || 'Unknown'}</dd></div>
        <div><dt>Extraction method</dt><dd>{document.extractionMethod || 'None'}</dd></div>
      </dl>

      <div className="supporting-document-card__facts">
        <h6>Extracted allowed facts</h6>
        {populatedFacts.length ? (
          <dl>
            {populatedFacts.map(([key, label]) => (
              <div key={key}>
                <dt>{label}</dt>
                <dd>{formatFactValue(key, facts[key])}</dd>
              </div>
            ))}
          </dl>
        ) : (
          <p>No reliable allowed facts were extracted.</p>
        )}
      </div>

      <FindingList
        title="Warnings"
        items={document.warnings}
        emptyMessage="No document warnings were reported."
        tone={document.warnings?.length ? 'warning' : 'success'}
      />
    </article>
  )
}

function SupportingDocumentVerification({ documents }) {
  const verification = Array.isArray(documents) ? documents : []
  return (
    <section className="structured-validation-section" aria-label="Supporting document verification">
      <h4>Supporting document verification</h4>
      {verification.length ? (
        <div className="supporting-document-grid">
          {verification.map((document, index) => (
            <SupportingDocumentCard
              key={document.documentId || `${document.documentType}-${index}`}
              document={document}
            />
          ))}
        </div>
      ) : (
        <p className="structured-validation-section__empty">No supporting documents were analyzed.</p>
      )}
    </section>
  )
}

function CrossDocumentConsistency({ consistency }) {
  if (!consistency) return null
  return (
    <section className="structured-validation-section" aria-label="Cross document consistency">
      <h4>Cross-document consistency</h4>
      <div className="validation-findings">
        <FindingList
          title="Matched facts"
          items={consistency.matchedFacts}
          emptyMessage="No matched facts were reported."
          tone="success"
        />
        <FindingList
          title="Mismatches"
          items={consistency.mismatches}
          emptyMessage="No mismatches were reported."
          tone={consistency.mismatches?.length ? 'danger' : 'success'}
        />
        <FindingList
          title="Warnings"
          items={consistency.warnings}
          emptyMessage="No consistency warnings were reported."
          tone={consistency.warnings?.length ? 'warning' : 'success'}
        />
        <div className="validation-findings__group">
          <h5>Manual review</h5>
          <p>{consistency.requiresManualReview ? 'Required' : 'Not required'}</p>
        </div>
      </div>
    </section>
  )
}

function ValidationStep({ step }) {
  const entries =
    step.result && typeof step.result === 'object' && !Array.isArray(step.result)
      ? Object.entries(step.result).filter(([, value]) =>
          value === null || typeof value !== 'object' ||
          (Array.isArray(value) && value.every((item) => typeof item !== 'object')),
        )
      : []

  return (
    <li className="validation-step">
      <div className="validation-step__heading">
        <span className="validation-step__number">{step.stepOrder}</span>
        <div>
          <h5>{step.agentName}</h5>
          <p>{enumLabel(step.status, STEP_STATUS)}</p>
        </div>
      </div>

      {entries.length > 0 && (
        <dl className="validation-step__result">
          {entries.map(([key, value]) => (
            <div key={key}>
              <dt>{humanizeKey(key)}</dt>
              <dd>{displayValue(value)}</dd>
            </div>
          ))}
        </dl>
      )}

      {step.errorMessage && (
        <p className="validation-step__error" role="alert">
          {step.errorMessage}
        </p>
      )}

      <p className="validation-step__timing">
        {step.completedAt
          ? `Completed ${formatDateTime(step.completedAt)}`
          : step.startedAt
            ? `Started ${formatDateTime(step.startedAt)}`
            : 'Not started'}
      </p>
    </li>
  )
}

function WorkflowResult({ workflow }) {
  const summary = workflow.summary
  const warnings = summary
    ? [
        ...(summary.applicationData?.warnings || []),
        ...(summary.documents?.warnings || []),
        ...(summary.deterministicRules?.warnings || []),
      ].filter((warning, index, all) => all.indexOf(warning) === index)
    : []
  const orderedSteps = [...(workflow.steps || [])].sort(
    (left, right) => left.stepOrder - right.stepOrder,
  )
  const agenticReview = summary?.agenticReview

  return (
    <div className="validation-workflow">
      <div className="validation-workflow__summary">
        <div>
          <span>Completeness score</span>
          <strong>{formatScore(workflow.completenessScore)}</strong>
        </div>
        <div>
          <span>Automated recommendation</span>
          <strong>{workflow.recommendation || 'Validation incomplete'}</strong>
        </div>
        <div>
          <span>Workflow status</span>
          <strong>{enumLabel(workflow.status, WORKFLOW_STATUS)}</strong>
        </div>
        <div>
          <span>Human review</span>
          <strong>
            {workflow.requiresHumanApproval ? 'Required' : 'Not indicated'}
          </strong>
        </div>
      </div>

      {summary && (
        <div className="validation-findings" aria-label="Automated validation findings">
          <FindingList
            title="Missing application information"
            items={summary.applicationData?.missingFields}
            emptyMessage="No required application information is missing."
          />
          <FindingList
            title="Missing required documents"
            items={summary.documents?.missingDocumentTypes}
            emptyMessage="No required documents are missing."
          />
          <FindingList
            title="Warnings"
            items={warnings}
            emptyMessage="No warnings were reported."
            tone="warning"
          />
          <FindingList
            title="Deterministic rules passed"
            items={summary.deterministicRules?.passedRules}
            emptyMessage="No passing rule results were reported."
            tone="success"
          />
          <FindingList
            title="Deterministic rules requiring attention"
            items={summary.deterministicRules?.failedRules}
            emptyMessage="No deterministic rules failed."
            tone="danger"
          />
        </div>
      )}

      {agenticReview && (
        <>
          <SupportingDocumentVerification
            documents={agenticReview.supportingDocumentVerification}
          />
          <CrossDocumentConsistency
            consistency={agenticReview.crossDocumentConsistency}
          />
        </>
      )}

      <details className="validation-steps">
        <summary>View workflow steps ({orderedSteps.length})</summary>
        <ol>
          {orderedSteps.map((step) => (
            <ValidationStep key={`${step.stepOrder}-${step.agentName}`} step={step} />
          ))}
        </ol>
      </details>
    </div>
  )
}

function ApplicationValidationSection({ applicationId, canRun }) {
  const [state, setState] = useState({
    status: 'loading',
    runs: [],
    selectedId: null,
    error: '',
  })
  const [isRunning, setIsRunning] = useState(false)

  useEffect(() => {
    let isActive = true

    getApplicationValidationRuns(applicationId)
      .then((runs) => {
        if (!isActive) return
        setState({
          status: 'success',
          runs,
          selectedId: runs[0]?.id || null,
          error: '',
        })
      })
      .catch((error) => {
        if (!isActive) return
        setState({
          status: 'error',
          runs: [],
          selectedId: null,
          error: safeErrorMessage(error),
        })
      })

    return () => {
      isActive = false
    }
  }, [applicationId])

  async function runValidation() {
    if (isRunning || !canRun) return

    setIsRunning(true)
    setState((current) => ({ ...current, error: '' }))
    try {
      const workflow = await runApplicationValidation(applicationId)
      setState((current) => ({
        status: 'success',
        runs: [workflow, ...current.runs.filter((run) => run.id !== workflow.id)],
        selectedId: workflow.id,
        error: '',
      }))
    } catch (error) {
      setState((current) => ({
        ...current,
        status: current.runs.length ? 'success' : 'error',
        error: safeErrorMessage(error),
      }))
    } finally {
      setIsRunning(false)
    }
  }

  const selectedRun =
    state.runs.find((workflow) => workflow.id === state.selectedId) ||
    state.runs[0]

  return (
    <section className="application-validation" aria-label="Application validation">
      <div className="application-validation__header">
        <div>
          <p className="application-validation__eyebrow">Automated findings</p>
          <h3>Application validation</h3>
          <p>Check application completeness, documents, and deterministic rules.</p>
        </div>
        <button
          type="button"
          className="application-button application-button--validation"
          onClick={runValidation}
          disabled={isRunning || !canRun}
        >
          {isRunning ? 'Running validation...' : 'Run validation'}
        </button>
      </div>

      <p className="application-validation__boundary">
        Automated validation supports review only. Final rental decisions require
        landlord approval.
      </p>

      {!canRun && (
        <p className="application-validation__unavailable">
          New validation runs are available only for submitted applications or
          applications under review.
        </p>
      )}

      {state.status === 'loading' && (
        <div className="application-validation__state" aria-live="polite">
          <span className="applications-spinner" aria-hidden="true" />
          Loading validation history...
        </div>
      )}

      {state.error && (
        <p className="application-form-error" role="alert">
          {state.error}
        </p>
      )}

      {state.status === 'success' && state.runs.length === 0 && (
        <p className="application-validation__empty">
          No validation runs yet. Run validation to create automated review findings.
        </p>
      )}

      {selectedRun && (
        <>
          {state.runs.length > 1 && (
            <div className="validation-history">
              <label htmlFor={`validation-run-${applicationId}`}>
                Validation history
              </label>
              <select
                id={`validation-run-${applicationId}`}
                value={selectedRun.id}
                onChange={(event) =>
                  setState((current) => ({
                    ...current,
                    selectedId: event.target.value,
                  }))
                }
              >
                {state.runs.map((workflow, index) => (
                  <option key={workflow.id} value={workflow.id}>
                    {index === 0 ? 'Latest — ' : ''}
                    {formatDateTime(workflow.createdAt)} —{' '}
                    {enumLabel(workflow.status, WORKFLOW_STATUS)}
                  </option>
                ))}
              </select>
            </div>
          )}
          <WorkflowResult workflow={selectedRun} />
        </>
      )}
    </section>
  )
}

export default ApplicationValidationSection
