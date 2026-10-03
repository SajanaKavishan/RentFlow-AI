export function usablePublicContactPhone(value) {
  const phone = typeof value === 'string' ? value.trim() : ''
  const digits = phone.replace(/[^0-9]/g, '').length
  return /^[+0-9][0-9\s().-]{6,31}$/.test(phone) && digits >= 7 && digits <= 15 ? phone : null
}
