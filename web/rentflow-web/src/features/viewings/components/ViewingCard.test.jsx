import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import ViewingCard from './ViewingCard.jsx'

afterEach(cleanup)

const phone = '+94 77 123 4567'
const viewing = {
  id: 'viewing',
  tenantId: '4f631888-ca78-4787-aaaa-aaaaaaaaaaaa',
  propertyId: 'property',
  requestedDateTime: '2030-01-02T10:00:00Z',
  createdAt: '2026-09-14T10:00:00Z',
  tenant: { displayName: 'Chamodya Sayanjali', phoneNumber: phone },
}

describe('Viewing tenant identity', () => {
  it.each([0, 2, 3, 4])('shows the name and hides contact for status %s even with stale contact data', (status) => {
    render(<ViewingCard viewing={{ ...viewing, status }} />)
    expect(screen.getByText('Tenant')).toBeInTheDocument()
    expect(screen.getByText('Chamodya Sayanjali')).toBeInTheDocument()
    expect(screen.queryByText(viewing.tenantId)).not.toBeInTheDocument()
    expect(screen.queryByText('Tenant ID')).not.toBeInTheDocument()
    expect(screen.queryByText(phone)).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /call/i })).not.toBeInTheDocument()
  })

  it('shows an approved phone only as plain text and preserves property context', () => {
    const { container } = render(<ViewingCard viewing={{ ...viewing, status: 1 }}
      property={{ title: 'Harbour view residences', address: 'Kureepoththa, Pothuhera', city: 'Kurunegala' }} />)
    expect(screen.getByText(phone).tagName).toBe('SMALL')
    expect(container.querySelector('a[href^="tel:"]')).toBeNull()
    expect(screen.queryByRole('button', { name: /call|message/i })).not.toBeInTheDocument()
    expect(screen.getByText('Chamodya Sayanjali')).toBeInTheDocument()
    expect(screen.getByText('Harbour view residences')).toBeInTheDocument()
    expect(screen.getByText('Kureepoththa, Pothuhera, Kurunegala')).toBeInTheDocument()
  })

  it.each([null, '', '   '])('remains valid with missing phone %s', (phoneNumber) => {
    render(<ViewingCard viewing={{ ...viewing, status: 1, tenant: { ...viewing.tenant, phoneNumber } }} />)
    expect(screen.getByText('Chamodya Sayanjali')).toBeInTheDocument()
    expect(screen.queryByText(phone)).not.toBeInTheDocument()
  })

  it('uses Tenant when the summary name is missing', () => {
    render(<ViewingCard viewing={{ ...viewing, status: 0, tenant: { displayName: ' ' } }} />)
    expect(screen.getAllByText('Tenant')).toHaveLength(2)
    expect(screen.queryByText(viewing.tenantId)).not.toBeInTheDocument()
  })
})
