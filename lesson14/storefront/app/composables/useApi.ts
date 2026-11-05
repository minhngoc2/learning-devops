export const TOKEN_KEY = 'lesson14.idToken'

export interface Customer {
  sub: string
  email: string
  display_name: string
  created_at: string
}

export interface Product {
  id: string
  name: string
  description: string
  price_cents: number
  currency: string
  category: string
  image_key: string
  image_url: string
  created_at: string
}

export interface CartItem {
  product_id: string
  quantity: number
}

export interface Cart {
  customer_sub: string
  items: CartItem[]
  updated_at: string
}

export type OrderStatus = 'PENDING_PAYMENT' | 'PAID' | 'PAYMENT_FAILED'

export interface OrderItem {
  product_id: string
  name: string
  unit_price_cents: number
  quantity: number
}

export interface Order {
  id: string
  customer_sub: string
  status: OrderStatus
  total_cents: number
  currency: string
  items: OrderItem[]
  created_at: string
  updated_at: string
}

export interface Payment {
  id: string
  order_id: string
  customer_sub: string
  amount_cents: number
  status: string
  reason: string
  created_at: string
}

export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message)
  }
}

export function formatMoney(cents: number): string {
  return Math.round(cents / 100).toLocaleString('vi-VN') + ' ₫'
}

// Cognito ID token → Bearer (API Gateway's authorizer turns it into X-Customer-*). Local compose tokens
// are "local:<sub>:<email>" and nothing verifies them, so the headers are sent directly instead.
function authHeaders(token: string | null): Record<string, string> {
  if (!token) return {}
  if (!token.startsWith('local:')) return { Authorization: `Bearer ${token}` }
  const rest = token.slice('local:'.length)
  const i = rest.indexOf(':')
  return i < 0
    ? { 'X-Customer-Sub': rest }
    : { 'X-Customer-Sub': rest.slice(0, i), 'X-Customer-Email': rest.slice(i + 1) }
}

export function useApi() {
  const token = useState<string | null>('idToken', () => (import.meta.client ? localStorage.getItem(TOKEN_KEY) : null))
  const loggedIn = useState<boolean>('loggedIn', () => !!token.value)
  const customer = useState<Customer | null>('customer', () => null)
  // Captured now: request() runs after an await, outside the setup context navigateTo needs.
  const nuxtApp = useNuxtApp()

  function setToken(value: string) {
    token.value = value
    loggedIn.value = true
    localStorage.setItem(TOKEN_KEY, value)
  }

  function clearToken() {
    token.value = null
    loggedIn.value = false
    customer.value = null
    localStorage.removeItem(TOKEN_KEY)
  }

  // public: login and register, which answer 401 for bad credentials and must not end a session.
  async function request<T>(path: string, opts: { method?: string, body?: unknown, public?: boolean } = {}): Promise<T> {
    const sent = opts.public ? null : token.value
    const headers: Record<string, string> = { Accept: 'application/json', ...authHeaders(sent) }
    if (opts.body !== undefined) headers['Content-Type'] = 'application/json'
    const res = await fetch(path, {
      method: opts.method ?? 'GET',
      headers,
      body: opts.body === undefined ? undefined : JSON.stringify(opts.body)
    })
    const text = await res.text()
    let data: unknown = null
    if (text) {
      try {
        data = JSON.parse(text)
      } catch {
        data = null
      }
    }
    if (!res.ok) {
      const msg = (data as { error?: string } | null)?.error ?? `${res.status} ${res.statusText}`
      // An expired or invalid token: drop the session and log in again. A 403 (WAF block, origin check)
      // says nothing about the token, so it keeps the session. A stale request (sent before a newer login)
      // must not drop the newer session.
      if (res.status === 401 && sent && sent === token.value) {
        clearToken()
        const here = nuxtApp.$router.currentRoute.value
        if (here.path !== '/login') {
          void nuxtApp.runWithContext(() => navigateTo({ path: '/login', query: { redirect: here.fullPath } }))
        }
        throw new ApiError(401, 'Your session has expired. Please log in again.')
      }
      throw new ApiError(res.status, msg)
    }
    return data as T
  }

  return { token, loggedIn, customer, setToken, clearToken, request }
}
