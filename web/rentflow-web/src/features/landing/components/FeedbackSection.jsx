import { useState } from 'react'
import { FeedbackTransportUnavailableError, sendFeedback } from '../feedbackService.js'

const initialValues = { name: '', email: '', message: '' }

function validate(values) {
  const errors = {}
  const name = values.name.trim()
  const email = values.email.trim()
  const message = values.message.trim()

  if (!name) errors.name = 'Enter your name.'
  else if (name.length > 80) errors.name = 'Name must be 80 characters or fewer.'
  if (!email) errors.email = 'Enter your email address.'
  else if (email.length > 160 || !/^\S+@\S+\.\S+$/.test(email)) errors.email = 'Enter a valid email address.'
  if (!message) errors.message = 'Enter your message.'
  else if (message.length > 1500) errors.message = 'Message must be 1500 characters or fewer.'

  return errors
}

export default function FeedbackSection({ service = sendFeedback }) {
  const [values, setValues] = useState(initialValues)
  const [errors, setErrors] = useState({})
  const [deliveryError, setDeliveryError] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)

  const update = (field) => (event) => {
    const value = event.target.value
    setValues((current) => ({ ...current, [field]: value }))
    setErrors((current) => ({ ...current, [field]: '' }))
    setDeliveryError('')
  }

  async function handleSubmit(event) {
    event.preventDefault()
    const validationErrors = validate(values)
    setErrors(validationErrors)
    setDeliveryError('')
    if (Object.keys(validationErrors).length) return

    setIsSubmitting(true)
    try {
      await service({ name: values.name.trim(), email: values.email.trim(), message: values.message.trim() })
    } catch (error) {
      setDeliveryError(error instanceof FeedbackTransportUnavailableError
        ? error.message
        : 'Your message could not be delivered. Please try again later.')
    } finally {
      setIsSubmitting(false)
    }
  }

  return <section id="feedback" className="landing-section landing-feedback" aria-labelledby="feedback-title">
    <div className="landing-container landing-feedback__layout">
      <div className="landing-feedback__copy">
        <p className="landing-eyebrow">Let&apos;s talk</p>
        <h2 id="feedback-title">Have a question or feedback?</h2>
        <p>We&apos;d love to hear about your RentFlow experience.</p>
      </div>
      <form className="landing-feedback__form" onSubmit={handleSubmit} noValidate>
        <div className="landing-feedback__field">
          <label htmlFor="feedback-name">Name</label>
          <input id="feedback-name" name="name" autoComplete="name" maxLength="80" value={values.name} onChange={update('name')} aria-invalid={Boolean(errors.name)} aria-describedby={errors.name ? 'feedback-name-error' : undefined} disabled={isSubmitting} />
          {errors.name && <span id="feedback-name-error" className="landing-feedback__error">{errors.name}</span>}
        </div>
        <div className="landing-feedback__field">
          <label htmlFor="feedback-email">Email</label>
          <input id="feedback-email" name="email" type="email" autoComplete="email" maxLength="160" value={values.email} onChange={update('email')} aria-invalid={Boolean(errors.email)} aria-describedby={errors.email ? 'feedback-email-error' : undefined} disabled={isSubmitting} />
          {errors.email && <span id="feedback-email-error" className="landing-feedback__error">{errors.email}</span>}
        </div>
        <div className="landing-feedback__field">
          <label htmlFor="feedback-message">Message</label>
          <textarea id="feedback-message" name="message" rows="5" maxLength="1500" value={values.message} onChange={update('message')} aria-invalid={Boolean(errors.message)} aria-describedby={errors.message ? 'feedback-message-error' : undefined} disabled={isSubmitting} />
          {errors.message && <span id="feedback-message-error" className="landing-feedback__error">{errors.message}</span>}
        </div>
        {deliveryError && <p className="landing-feedback__delivery-error" role="alert">{deliveryError}</p>}
        <button className="landing-button landing-feedback__submit" type="submit" disabled={isSubmitting}>{isSubmitting ? 'Sending…' : 'Send message'}</button>
      </form>
    </div>
  </section>
}
