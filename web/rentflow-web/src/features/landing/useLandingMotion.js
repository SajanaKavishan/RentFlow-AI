import { useEffect, useRef } from 'react'

export function useLandingMotion() {
  const rootRef = useRef(null)

  useEffect(() => {
    const root = rootRef.current
    const reduceMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
    if (!root || reduceMotion || !('IntersectionObserver' in window)) return undefined

    const revealNodes = [...root.querySelectorAll('[data-reveal]')]
    root.classList.add('landing-motion-ready')

    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return
        entry.target.classList.add('is-visible')
        observer.unobserve(entry.target)
      })
    }, { rootMargin: '0px 0px -10% 0px', threshold: 0.12 })

    revealNodes.forEach((node) => observer.observe(node))

    return () => {
      observer.disconnect()
      root.classList.remove('landing-motion-ready')
    }
  }, [])

  return rootRef
}
