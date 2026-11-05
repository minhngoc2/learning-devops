<script setup lang="ts">
definePageMeta({ middleware: 'auth' })

const POLL_MS = 2000
const route = useRoute()
const { request } = useApi()
const { setQuantity } = useCart()
const id = encodeURIComponent(String(route.params.id))

const order = ref<Order | null>(null)
const payment = ref<Payment | null>(null)
const error = ref('')
const readding = ref(false)
const readded = ref(false)
let timer: ReturnType<typeof setTimeout> | undefined
let stopped = false

// Poll the order while payment is pending; once it settles, fetch the payment (404 until it exists).
async function poll() {
  try {
    order.value = await request<Order>(`/api/orders/${id}`)
    error.value = ''
    if (order.value.status !== 'PENDING_PAYMENT') {
      payment.value = await request<Payment>(`/api/payments/${id}`)
      return
    }
  } catch (e) {
    const notFound = e instanceof ApiError && e.status === 404
    if (!(notFound && order.value)) {
      error.value = (e as Error).message
      if (notFound) return
    }
  }
  if (!stopped) timer = setTimeout(poll, POLL_MS)
}

onMounted(poll)
onBeforeUnmount(() => {
  stopped = true
  clearTimeout(timer)
})

async function addBackToCart() {
  if (!order.value) return
  readding.value = true
  error.value = ''
  try {
    const cart = await request<Cart>('/api/cart')
    for (const item of order.value.items) {
      const current = cart.items.find(i => i.product_id === item.product_id)?.quantity ?? 0
      await setQuantity(item.product_id, Math.min(current + item.quantity, MAX_QUANTITY))
    }
    readded.value = true
  } catch (e) {
    error.value = (e as Error).message
  } finally {
    readding.value = false
  }
}
</script>

<template>
  <section>
    <p><NuxtLink to="/orders">← All orders</NuxtLink></p>
    <p v-if="error" class="error">{{ error }}</p>
    <p v-if="!order && !error" class="muted">Loading…</p>
    <template v-if="order">
      <div class="row">
        <h1 style="margin: 0">Order {{ order.id }}</h1>
        <OrderStatus :status="order.status" />
      </div>
      <p class="muted">Placed {{ new Date(order.created_at).toLocaleString() }}</p>

      <div class="card">
        <table>
          <thead><tr><th>Product</th><th>Qty</th><th>Price</th><th>Subtotal</th></tr></thead>
          <tbody>
            <tr v-for="item in order.items" :key="item.product_id">
              <td><NuxtLink :to="`/products/${item.product_id}`">{{ item.name }}</NuxtLink></td>
              <td>{{ item.quantity }}</td>
              <td>{{ formatMoney(item.unit_price_cents) }}</td>
              <td>{{ formatMoney(item.unit_price_cents * item.quantity) }}</td>
            </tr>
          </tbody>
        </table>
        <p class="price">Total: {{ formatMoney(order.total_cents) }}</p>
      </div>

      <div class="card outcome">
        <p v-if="order.status === 'PENDING_PAYMENT'" class="muted">Waiting for the payment service… (checking every 2 s)</p>
        <template v-else-if="order.status === 'PAID'">
          <p class="ok">Payment succeeded. Thank you for your order!</p>
        </template>
        <template v-else>
          <p class="error">Payment failed<span v-if="payment?.reason">: {{ payment.reason }}</span>.</p>
          <div class="row">
            <button type="button" :disabled="readding || readded" @click="addBackToCart">Add these items to your cart again</button>
            <span v-if="readded" class="ok">Added. <NuxtLink to="/cart">Go to cart</NuxtLink></span>
          </div>
        </template>
        <p v-if="payment" class="muted">
          Payment {{ payment.id }} · {{ payment.status }} · {{ formatMoney(payment.amount_cents) }}
        </p>
      </div>
    </template>
  </section>
</template>

<style scoped>
.outcome { margin-top: 1rem; }
</style>
