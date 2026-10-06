export function jobDate(value, withTime = false) {
  if (!value || Number.isNaN(new Date(value).getTime())) return null
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', ...(withTime ? { timeStyle: 'short' } : {}) }).format(new Date(value))
}

export function technicianSummary(requests, now = new Date()) {
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const weekStart = new Date(today)
  weekStart.setDate(weekStart.getDate() - ((weekStart.getDay() + 6) % 7))
  const nextWeekStart = new Date(weekStart)
  nextWeekStart.setDate(nextWeekStart.getDate() + 7)
  const active = requests.filter((item) => !['Completed', 'Cancelled'].includes(item.status))
  const validDate = (value) => value && !Number.isNaN(Date.parse(value))
  const completedItems = requests.filter((item) => item.status === 'Completed')
  const datedCompletedItems = completedItems.filter((item) => validDate(item.completedAt))
  return {
    today: active.every((item) => validDate(item.scheduledAt))
      ? active.filter((item) => new Date(item.scheduledAt).toDateString() === today.toDateString()).length
      : null,
    progress: requests.filter((item) => item.status === 'InProgress').length,
    completed: completedItems.length > 0 && datedCompletedItems.length === 0
      ? null
      : datedCompletedItems.filter((item) => {
        const completedAt = new Date(item.completedAt)
        return completedAt >= weekStart && completedAt < nextWeekStart && completedAt <= now
      }).length,
  }
}

export function activeTechnicianWork(requests) {
  return requests.filter((item) => !['Completed', 'Cancelled', 'Rejected'].includes(item.status))
}

export function technicianAttentionWork(requests) {
  return requests.filter((item) => ['Assigned', 'EstimatePending', 'Approved', 'InProgress'].includes(item.status))
}
