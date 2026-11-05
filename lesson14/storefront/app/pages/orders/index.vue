<script setup lang="ts">
definePageMeta({ middleware: 'auth' })

const { request } = useApi()
const orders = ref<Order[]>([])
const loading = ref(true)
const error = ref('')

onMounted(async () => {
  try {
    orders.value = await request<Order[]>('/api/orders')
  } catch (e) {
    error.value = (e as Error).message
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <section>
    <h1>Your orders</h1>
    <p v-if="error" class="error">{{ error }}</p>
    <p v-if="loading" class="muted">Loading…</p>
    <div v-else-if="orders.length" class="card">
      <table>
        <thead><tr><th>Order</th><th>Placed</th><th>Items</th><th>Total</th><th>Status</th></tr></thead>
        <tbody>
          <tr v-for="o in orders" :key="o.id">
            <td><NuxtLink :to="`/orders/${o.id}`">{{ o.id }}</NuxtLink></td>
            <td>{{ new Date(o.created_at).toLocaleString() }}</td>
            <td>{{ o.items.reduce((n, i) => n + i.quantity, 0) }}</td>
            <td>{{ formatMoney(o.total_cents) }}</td>
            <td><OrderStatus :status="o.status" /></td>
          </tr>
        </tbody>
      </table>
    </div>
    <p v-else-if="!error" class="muted">No orders yet. <NuxtLink to="/">Browse products</NuxtLink></p>
  </section>
</template>
