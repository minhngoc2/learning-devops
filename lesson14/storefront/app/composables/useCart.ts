export const MAX_QUANTITY = 99

export function useCart() {
  const { request } = useApi()

  function setQuantity(productId: string, quantity: number) {
    return request<Cart>(`/api/cart/items/${encodeURIComponent(productId)}`, {
      method: 'PUT',
      body: { quantity }
    })
  }

  // The API sets absolute quantities, so "add" reads the cart first.
  async function add(productId: string, by = 1) {
    const cart = await request<Cart>('/api/cart')
    const current = cart.items.find(i => i.product_id === productId)?.quantity ?? 0
    return setQuantity(productId, Math.min(current + by, MAX_QUANTITY))
  }

  return { setQuantity, add }
}
