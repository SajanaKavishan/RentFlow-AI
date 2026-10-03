import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import ViewingAvailabilityEditor from './ViewingAvailabilityEditor.jsx'
import { getViewingAvailability, saveViewingAvailability } from '../services/viewingAvailabilityApi.js'

vi.mock('../services/viewingAvailabilityApi.js', () => ({ getViewingAvailability: vi.fn(), saveViewingAvailability: vi.fn() }))
const propertyId = '11111111-1111-1111-1111-111111111111'
const empty = { propertyId, timeZoneId: 'Asia/Colombo', slotDurationMinutes: 60, windows: [] }
const configured = { ...empty, windows: [{ dayOfWeek: 1, isEnabled: true, startTime: '09:00:00', endTime: '17:00:00' }] }

beforeEach(() => { vi.resetAllMocks(); getViewingAvailability.mockResolvedValue(empty) })
afterEach(cleanup)

describe('Viewing availability editor', () => {
  it('loads an empty schedule without inventing enabled days or hours', async () => {
    render(<ViewingAvailabilityEditor propertyId={propertyId} />)
    expect(await screen.findByText('No weekdays are enabled. Tenants will see no viewing times.')).toBeInTheDocument()
    expect(getViewingAvailability).toHaveBeenCalledWith(propertyId)
    expect(screen.getAllByRole('checkbox')).toHaveLength(7)
    expect(screen.getAllByRole('checkbox').every(box => !box.checked)).toBe(true)
    expect(screen.queryByLabelText('Monday start')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Save viewing availability' })).toBeDisabled()
  })
  it('loads the weekday contract and current hours', async () => {
    getViewingAvailability.mockResolvedValue(configured)
    render(<ViewingAvailabilityEditor propertyId={propertyId} />)
    expect(await screen.findByLabelText('Monday start')).toHaveValue('09:00')
    expect(screen.getByLabelText('Monday enabled')).toBeChecked()
    expect(screen.getByLabelText('Sunday enabled')).not.toBeChecked()
    expect(screen.getByText('Sri Lanka (Asia/Colombo)')).toBeInTheDocument()
  })
  it('requires actual times when enabling a weekday and validates window boundaries', async () => {
    render(<ViewingAvailabilityEditor propertyId={propertyId} />)
    fireEvent.click(await screen.findByLabelText('Monday enabled'))
    expect(screen.getByLabelText('Monday start')).toHaveValue('')
    expect(screen.getByRole('button', { name: 'Save viewing availability' })).toBeDisabled()
    expect(await screen.findByRole('alert')).toHaveTextContent('Choose a start time before the end time.')
    fireEvent.change(screen.getByLabelText('Monday start'), { target: { value: '17:00' } })
    fireEvent.change(screen.getByLabelText('Monday end'), { target: { value: '09:00' } })
    fireEvent.click(screen.getByRole('button', { name: 'Save viewing availability' }))
    expect(saveViewingAvailability).not.toHaveBeenCalled()
    fireEvent.change(screen.getByLabelText('Monday start'), { target: { value: '08:30' } })
    fireEvent.click(screen.getByRole('button', { name: 'Save viewing availability' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('one complete slot')
    expect(screen.getByRole('button', { name: 'Save viewing availability' })).toBeDisabled()
  })
  it('saves changed duration/hours only through API and acknowledges only API success', async () => {
    getViewingAvailability.mockResolvedValue(configured)
    let resolve
    saveViewingAvailability.mockImplementation(() => new Promise(done => { resolve = done }))
    const dirty = vi.fn()
    render(<ViewingAvailabilityEditor propertyId={propertyId} onDirtyChange={dirty} />)
    fireEvent.change(await screen.findByLabelText('Monday start'), { target: { value: '10:00' } })
    fireEvent.change(screen.getByLabelText('Slot duration'), { target: { value: '45' } })
    fireEvent.click(screen.getByRole('button', { name: 'Save viewing availability' }))
    expect(screen.queryByText('Viewing availability saved.')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Saving availability...' })).toBeDisabled()
    expect(saveViewingAvailability).toHaveBeenCalledWith(propertyId, expect.objectContaining({ slotDurationMinutes: 45,
      windows: expect.arrayContaining([expect.objectContaining({ dayOfWeek: 1, startTime: '10:00:00' })]) }))
    resolve({ ...configured, slotDurationMinutes: 45, windows: [{ ...configured.windows[0], startTime: '10:00:00' }] })
    expect((await screen.findByText('Viewing availability saved.')).closest('.property-toast'))
      .toHaveClass('property-toast--success')
    await waitFor(() => expect(dirty).toHaveBeenLastCalledWith(false))
  })
  it('preserves unsaved input on save failure and can retry', async () => {
    getViewingAvailability.mockResolvedValue(configured)
    saveViewingAvailability.mockRejectedValue(new Error('Schedule could not be saved'))
    render(<ViewingAvailabilityEditor propertyId={propertyId} />)
    fireEvent.change(await screen.findByLabelText('Monday end'), { target: { value: '18:00' } })
    fireEvent.click(screen.getByRole('button', { name: 'Save viewing availability' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Schedule could not be saved')
    expect(screen.getByRole('alert')).toHaveClass('property-toast--error')
    expect(screen.getByLabelText('Monday end')).toHaveValue('18:00')
    expect(screen.getByText('Unsaved viewing availability changes')).toBeInTheDocument()
    expect(screen.queryByText('Viewing availability saved.')).not.toBeInTheDocument()
  })
  it('clears disabled weekday times in the outgoing contract', async () => {
    getViewingAvailability.mockResolvedValue(configured)
    saveViewingAvailability.mockResolvedValue(empty)
    render(<ViewingAvailabilityEditor propertyId={propertyId} />)
    fireEvent.click(await screen.findByLabelText('Monday enabled'))
    fireEvent.click(screen.getByRole('button', { name: 'Save viewing availability' }))
    expect(await screen.findByText('Viewing availability saved.')).toBeInTheDocument()
    expect(saveViewingAvailability.mock.calls[0][1].windows[0]).toEqual({ dayOfWeek: 1, isEnabled: false, startTime: null, endTime: null })
  })
  it('rejects a response for a different property and retries a failed load', async () => {
    getViewingAvailability.mockResolvedValue({ ...configured, propertyId: 'other-property' })
    render(<ViewingAvailabilityEditor propertyId={propertyId} />)
    expect(await screen.findByRole('alert')).toHaveTextContent('could not be verified')
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
    getViewingAvailability.mockResolvedValue(empty)
    fireEvent.click(screen.getByRole('button', { name: 'Retry availability' }))
    expect(await screen.findByLabelText('Monday enabled')).not.toBeChecked()
  })
})
