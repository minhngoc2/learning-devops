// Cart items joined with their products (one GET /api/products?ids=... call), shared by /cart and /checkout.
export function useCartView() {
  const { request } = useApi()
  const cart = ref<Cart | null>(null)
  const products = ref<Record<string, Product>>({})
  const loading = ref(true)
  const error = ref('')

  async function loadProducts(items: CartItem[]) {
    const missing = items.map(i => i.product_id).filter(id => !products.value[id])
    if (!missing.length) return
    const list = await request<Product[]>(`/api/products?ids=${missing.map(encodeURIComponent).join(',')}`)
    for (const p of list) products.value[p.id] = p
  }

  async function setCart(c: Cart) {
    cart.value = c
    await loadProducts(c.items)
  }

  async function load() {
    loading.value = true
    error.value = ''
    try {
      await setCart(await request<Cart>('/api/cart'))
    } catch (e) {
      error.value = (e as Error).message
    } finally {
      loading.value = false
    }
  }

  const items = computed(() => cart.value?.items ?? [])
  const totalCents = computed(() =>
    items.value.reduce((sum, i) => sum + (products.value[i.product_id]?.price_cents ?? 0) * i.quantity, 0))

  return { cart, products, items, totalCents, loading, error, load, setCart }
}
