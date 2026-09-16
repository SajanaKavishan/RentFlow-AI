export class FeedbackTransportUnavailableError extends Error {
  constructor() {
    super('Message delivery is not connected yet. Please try again later.')
    this.name = 'FeedbackTransportUnavailableError'
  }
}

export async function sendFeedback() {
  throw new FeedbackTransportUnavailableError()
}
