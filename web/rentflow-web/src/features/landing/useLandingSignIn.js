import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { authenticatedHomePathForRole } from '../auth/authModel.js'
import { useAuth } from '../auth/useAuth.js'

export function useLandingSignIn() {
  const { isAuthenticated, isLoading, user } = useAuth()
  const navigate = useNavigate()
  const [signInRequested, setSignInRequested] = useState(false)

  useEffect(() => {
    if (!signInRequested || isLoading) return
    navigate(isAuthenticated ? authenticatedHomePathForRole(user?.role) : '/login')
  }, [isAuthenticated, isLoading, navigate, signInRequested, user?.role])

  return {
    onSignIn: () => setSignInRequested(true),
    isSignInPending: signInRequested && isLoading,
  }
}
