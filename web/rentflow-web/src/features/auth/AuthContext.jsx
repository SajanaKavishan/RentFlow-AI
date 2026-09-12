import { useCallback, useEffect, useMemo, useState } from 'react'
import { setUnauthorizedHandler } from '../../core/api/apiClient.js'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import * as authApi from './authApi.js'
import { AuthContext } from './useAuth.js'

export function AuthProvider({ children, api = authApi }) {
  const [user, setUser] = useState(null)
  const [isLoading, setIsLoading] = useState(true)
  const clearSession = useCallback(() => { tokenStorage.clearToken(); setUser(null) }, [])

  const refreshCurrentUser = useCallback(async () => {
    if (!tokenStorage.getToken()) { setUser(null); return null }
    try {
      const currentUser = await api.getCurrentUser()
      setUser(currentUser)
      return currentUser
    } catch (error) {
      clearSession()
      throw error
    }
  }, [api, clearSession])

  useEffect(() => setUnauthorizedHandler(clearSession), [clearSession])
  useEffect(() => {
    let active = true
    async function restoreSession() {
      try {
        if (!tokenStorage.getToken()) return
        const currentUser = await api.getCurrentUser()
        if (active) setUser(currentUser)
      } catch {
        tokenStorage.clearToken()
        if (active) setUser(null)
      } finally {
        if (active) setIsLoading(false)
      }
    }
    restoreSession()
    return () => { active = false }
  }, [api])

  const authenticate = useCallback(async (operation, payload) => {
    const result = await operation(payload)
    tokenStorage.setToken(result.accessToken)
    try {
      const currentUser = await api.getCurrentUser()
      setUser(currentUser)
      return currentUser
    } catch (error) {
      clearSession()
      throw error
    }
  }, [api, clearSession])
  const login = useCallback((credentials) => authenticate(api.login, credentials), [api, authenticate])
  const register = useCallback((details) => authenticate(api.register, details), [api, authenticate])
  const value = useMemo(() => ({ user, token: tokenStorage.getToken(),
    isAuthenticated: Boolean(user && tokenStorage.getToken()), isLoading, login, register,
    logout: clearSession, refreshCurrentUser }),
  [clearSession, isLoading, login, refreshCurrentUser, register, user])
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
