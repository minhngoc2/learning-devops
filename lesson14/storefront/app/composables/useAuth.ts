interface LoginResponse {
  id_token: string
  access_token: string
  refresh_token: string
  expires_in: number
}

export function useAuth() {
  // loggedIn is a ref that setToken/clearToken keep in step with the token; useApi clears both on a 401.
  const { token, loggedIn, customer, setToken, clearToken, request } = useApi()

  // Loads the profile for a stored token. A rejected token (401) is already dropped by useApi.
  async function loadCustomer(): Promise<Customer | null> {
    if (!token.value) return null
    if (customer.value) return customer.value
    customer.value = await request<Customer>('/api/users/me')
    return customer.value
  }

  async function login(email: string, password: string) {
    const res = await request<LoginResponse>('/api/users/login', { method: 'POST', body: { email, password }, public: true })
    customer.value = null
    setToken(res.id_token)
    await loadCustomer()
  }

  async function register(email: string, password: string, displayName: string) {
    await request<Customer>('/api/users/register', {
      method: 'POST',
      body: { email, password, display_name: displayName },
      public: true
    })
    await login(email, password)
  }

  function logout() {
    clearToken()
  }

  return { token, customer, loggedIn, loadCustomer, login, register, logout }
}
