import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it } from 'vitest'
import usePropertyContext from './usePropertyContext.js'

const propertyId = '88888888-8888-8888-8888-888888888888'

function PropertyContextProbe() {
  const context = usePropertyContext()
  return <span>{context.propertyId ?? 'No property'}</span>
}

describe('property context', () => {
  it('accepts a property ID from router navigation state', () => {
    render(
      <MemoryRouter
        initialEntries={[{ pathname: '/workspace', state: { propertyId } }]}
      >
        <PropertyContextProbe />
      </MemoryRouter>,
    )

    expect(screen.getByText(propertyId)).toBeInTheDocument()
  })

  it('does not expose an invalid property ID', () => {
    render(
      <MemoryRouter initialEntries={['/workspace?propertyId=not-a-property-id']}>
        <PropertyContextProbe />
      </MemoryRouter>,
    )

    expect(screen.getByText('No property')).toBeInTheDocument()
  })
})
