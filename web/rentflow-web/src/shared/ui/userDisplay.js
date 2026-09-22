export function initialsForName(name) {
  return (name || '').trim().split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0].toLocaleUpperCase()).join('') || '?'
}
