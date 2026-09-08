const ACCESS_TOKEN_KEY = 'rentflow.accessToken'

export const tokenStorage = {
  getToken() {
    return sessionStorage.getItem(ACCESS_TOKEN_KEY)
  },
  setToken(token) {
    if (typeof token !== 'string' || !token.trim()) {
      throw new TypeError('A valid access token is required.')
    }
    sessionStorage.setItem(ACCESS_TOKEN_KEY, token)
  },
  clearToken() {
    sessionStorage.removeItem(ACCESS_TOKEN_KEY)
  },
}
