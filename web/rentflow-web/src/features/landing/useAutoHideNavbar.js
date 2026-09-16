import { useEffect, useRef, useState } from 'react'

const TOP_THRESHOLD = 12
const HIDE_AFTER = 100
const DIRECTION_THRESHOLD = 8

export function useAutoHideNavbar() {
  const initialY = typeof window === 'undefined' ? 0 : window.scrollY
  const [isVisible, setIsVisible] = useState(true)
  const [isAtTop, setIsAtTop] = useState(initialY <= TOP_THRESHOLD)
  const visibleState = useRef(true)
  const topState = useRef(initialY <= TOP_THRESHOLD)
  const lastMeaningfulY = useRef(initialY)
  const frame = useRef(null)

  useEffect(() => {
    const requestFrame = window.requestAnimationFrame || ((callback) => window.setTimeout(callback, 16))
    const cancelFrame = window.cancelAnimationFrame || window.clearTimeout

    const updateNavbar = () => {
      const currentY = Math.max(window.scrollY, 0)
      const atTop = currentY <= TOP_THRESHOLD
      const delta = currentY - lastMeaningfulY.current

      const updateVisibility = (nextVisible) => {
        if (visibleState.current === nextVisible) return
        visibleState.current = nextVisible
        setIsVisible(nextVisible)
      }

      if (topState.current !== atTop) {
        topState.current = atTop
        setIsAtTop(atTop)
      }

      if (atTop) {
        updateVisibility(true)
        lastMeaningfulY.current = currentY
      } else if (Math.abs(delta) >= DIRECTION_THRESHOLD) {
        if (delta > 0 && currentY > HIDE_AFTER) updateVisibility(false)
        if (delta < 0) updateVisibility(true)
        lastMeaningfulY.current = currentY
      }

      frame.current = null
    }

    const onScroll = () => {
      if (frame.current === null) frame.current = requestFrame(updateNavbar)
    }

    window.addEventListener('scroll', onScroll, { passive: true })
    return () => {
      window.removeEventListener('scroll', onScroll)
      if (frame.current !== null) cancelFrame(frame.current)
    }
  }, [])

  return { isAtTop, isVisible }
}
