<script setup lang="ts">
definePageMeta({ middleware: 'auth' })

const POLL_MS = 2000
const POLL_LIMIT_MS = 5 * 60 * 1000
const MAX_FAILURES = 3
const route = useRoute()
const { request } = useApi()
const { setQuantity } = useCart()
const id = encodeURIComponent(String(route.params.id))

const order = ref<Order | null>(null)
const payment = ref<Payment | null>(null)
const error = ref('')
const timedOut = ref(false)
const readding = ref(false)
const readded = ref(false)
let timer: ReturnType<typeof setTimeout> | undefined
let stopped = false
let failures = 0
const deadline = Date.now() + POLL_LIMIT_MS

// Poll the order while payment is pending; once it settles, fetch the payment (404 until it exists).
// Stops on 401/403 (useApi has already sent a 401 to /login), after 3 server or network failures in a
// row, on a missing order, and after 5 minutes (then says the payment is still pending or not available yet).
async function poll() {
  try {
    order.value = await request<Order>(`/api/orders/${id}`)
    error.value = ''
    failures = 0
    if (order.value.status !== 'PENDING_PAYMENT') {
      payment.value = await request<Payment>(`/api/payments/${id}`)
      return
    }
  } catch (e) {
    const status = e instanceof ApiError ? e.status : 0
    if (status === 404 && order.value) {
      // The order has settled but Payment has not stored its record yet: keep polling.
    } else if (status >= 400 && status < 500) {
      // 401 (useApi is already redirecting), 403 (WAF), or an order that is not yours.
      error.value = (e as Error).message
      return
    } else if (++failures >= MAX_FAILURES) {
      error.value = (e as Error).message
      return
    }
  }
  if (Date.now() >= deadline) {
    // Still pending, or settled while the payment kept answering 404: the template says which.
    timedOut.value = true
    return
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
    // Absolute quantities (the order's), so pressing the button again after a failure is safe.
    for (const item of order.value.items) {
      await setQuantity(item.product_id, Math.min(item.quantity, MAX_QUANTITY))
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
        <p v-if="order.status === 'PENDING_PAYMENT' && timedOut" class="muted">
          Payment is still pending — refresh the page to check again.
        </p>
        <p v-else-if="order.status === 'PENDING_PAYMENT' && !error" class="muted">Waiting for the payment service… (checking every 2 s)</p>
        <p v-else-if="order.status === 'PENDING_PAYMENT'" class="muted">Payment is pending; checking stopped.</p>
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
        <p v-else-if="order.status !== 'PENDING_PAYMENT' && timedOut && !error" class="muted">
          Payment details are not available yet — refresh
        </p>
      </div>
    </template>
  </section>
</template>

<style scoped>
.outcome { margin-top: 1rem; }
</style>
