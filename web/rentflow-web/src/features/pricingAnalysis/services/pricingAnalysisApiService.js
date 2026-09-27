import { apiRequest } from '../../../core/api/apiClient.js'

export function startPricingAnalysis(propertyId) {
  return apiRequest(`/api/properties/${propertyId}/pricing-analysis-workflows`, {
    method: 'POST',
    errorMessage: 'Unable to start the pricing analysis. Please try again.',
  })
}

export function getPricingHistory(propertyId) {
  return apiRequest(`/api/properties/${propertyId}/pricing-analysis-workflows`, {
    errorMessage: 'Unable to load pricing analysis history.',
  })
}

export function getPricingWorkflow(workflowId) {
  return apiRequest(`/api/pricing-analysis-workflows/${workflowId}`, {
    errorMessage: 'Unable to load the pricing analysis.',
  })
}
