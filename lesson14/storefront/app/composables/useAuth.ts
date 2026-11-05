interface LoginResponse {
  id_token: string
  access_token: string
  refresh_token: string
  expires_in: number
}

export function useAuth() {
  const { token, request } = useApi()
  const customer = useState<Customer | null>('customer', () => null)
  const loggedIn = computed(() => !!token.value)

  function setToken(value: string | null) {
    token.value = value
    if (value) localStorage.setItem(TOKEN_KEY, value)
    else localStorage.removeItem(TOKEN_KEY)
  }

  // Loads the profile for a stored token; a rejected token (401/403) is dropped so the user logs in again.
  async function loadCustomer(): Promise<Customer | null> {
    if (!token.value) return null
    if (customer.value) return customer.value
    try {
      customer.value = await request<Customer>('/api/users/me')
    } catch (e) {
      if (e instanceof ApiError && (e.status === 401 || e.status === 403)) logout()
      else throw e
    }
    return customer.value
  }

  async function login(email: string, password: string) {
    const res = await request<LoginResponse>('/api/users/login', { method: 'POST', body: { email, password } })
    customer.value = null
    setToken(res.id_token)
    await loadCustomer()
  }

  async function register(email: string, password: string, displayName: string) {
    await request<Customer>('/api/users/register', {
      method: 'POST',
      body: { email, password, display_name: displayName }
    })
    await login(email, password)
  }

  function logout() {
    setToken(null)
    customer.value = null
  }

  return { token, customer, loggedIn, loadCustomer, login, register, logout }
}
