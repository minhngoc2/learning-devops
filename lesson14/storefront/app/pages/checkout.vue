<script setup lang="ts">
definePageMeta({ middleware: 'auth' })

const { request } = useApi()
const view = useCartView()
const { products, items, totalCents, loading, error } = view
const placing = ref(false)

onMounted(view.load)

async function placeOrder() {
  placing.value = true
  error.value = ''
  try {
    const order = await request<Order>('/api/orders', { method: 'POST' })
    await navigateTo(`/orders/${order.id}`)
  } catch (e) {
    error.value = (e as Error).message
  } finally {
    placing.value = false
  }
}
</script>

<template>
  <section>
    <h1>Checkout</h1>
    <p v-if="error" class="error">{{ error }}</p>
    <p v-if="loading" class="muted">Loading…</p>
    <template v-else-if="items.length">
      <div class="card">
        <table>
          <thead><tr><th>Product</th><th>Qty</th><th>Price</th><th>Subtotal</th></tr></thead>
          <tbody>
            <tr v-for="item in items" :key="item.product_id">
              <td>{{ products[item.product_id]?.name ?? item.product_id }}</td>
              <td>{{ item.quantity }}</td>
              <td>{{ products[item.product_id] ? formatMoney(products[item.product_id]!.price_cents) : '—' }}</td>
              <td>{{ products[item.product_id] ? formatMoney(products[item.product_id]!.price_cents * item.quantity) : '—' }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="row spread" style="margin-top: 1rem">
        <span class="price">Estimated total: {{ formatMoney(totalCents) }}</span>
        <button type="button" :disabled="placing" @click="placeOrder">Place order</button>
      </div>
      <p class="muted">The final price is confirmed by the order service when you place the order.</p>
    </template>
    <p v-else class="muted">Your cart is empty. <NuxtLink to="/">Browse products</NuxtLink></p>
  </section>
</template>
