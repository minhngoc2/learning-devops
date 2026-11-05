<script setup lang="ts">
const { request } = useApi()
const { loggedIn } = useAuth()
const cart = useCart()
const route = useRoute()

const products = ref<Product[]>([])
const loading = ref(true)
const error = ref('')
const notice = ref('')
const busy = ref<string | null>(null)

onMounted(async () => {
  try {
    products.value = await request<Product[]>('/api/products')
  } catch (e) {
    error.value = (e as Error).message
  } finally {
    loading.value = false
  }
})

async function add(productId: string) {
  if (!loggedIn.value) return navigateTo({ path: '/login', query: { redirect: route.fullPath } })
  busy.value = productId
  error.value = ''
  notice.value = ''
  try {
    await cart.add(productId)
    notice.value = `Added ${products.value.find(p => p.id === productId)?.name ?? productId} to your cart.`
  } catch (e) {
    error.value = (e as Error).message
  } finally {
    busy.value = null
  }
}
</script>

<template>
  <section>
    <h1>Products</h1>
    <p v-if="notice" class="ok">{{ notice }} <NuxtLink to="/cart">View cart</NuxtLink></p>
    <p v-if="error" class="error">{{ error }}</p>
    <p v-if="loading" class="muted">Loading…</p>
    <p v-else-if="!products.length && !error" class="muted">No products yet.</p>
    <div class="grid">
      <ProductCard v-for="p in products" :key="p.id" :product="p" :busy="busy === p.id" @add="add" />
    </div>
  </section>
</template>
