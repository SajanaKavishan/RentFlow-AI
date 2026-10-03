const stepLabels = {
  plan: 'Analysis Plan',
  collect_property_facts: 'Property Information',
  collect_rental_evidence: 'Comparable Rental Search',
  analyse_pricing_evidence: 'Rental Price Analysis',
  analyze_pricing_evidence: 'Rental Price Analysis',
  validate_result: 'Result Validation',
  finalize: 'Final Recommendation',
  gather_property_facts: 'Property Information',
  review_evidence: 'Comparable Rental Search',
}

const statuses = ['Pending', 'Running', 'Completed', 'Failed', 'Skipped']

export function friendlyStepLabel(name) {
  const key = String(name ?? '').trim().toLowerCase().replaceAll(' ', '_')
  return stepLabels[key] ?? stepLabels[String(name ?? '').trim().toLowerCase()] ?? String(name ?? 'Analysis step').replaceAll('_', ' ')
}

export function friendlyStepSummary(step) {
  const summary = step.outputSummary ?? ''
  if (/eligible comparable evidence collected:\s*0|sufficiency\s*=\s*INSUFFICIENT/i.test(summary)) {
    return 'No suitable comparable rental properties were found. There is not enough market evidence to produce a reliable pricing recommendation.'
  }
  if (step.status === 4 && /skipped because deterministic evidence sufficiency is INSUFFICIENT/i.test(summary)) {
    return 'Price analysis was skipped because there was not enough reliable rental-market evidence.'
  }
  return summary
}

export function workflowStepStatus(status) {
  return statuses[status] ?? 'Unknown'
}
