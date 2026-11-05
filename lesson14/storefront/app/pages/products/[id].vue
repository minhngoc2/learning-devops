<script setup lang="ts">
const route = useRoute()
const { request } = useApi()
const { loggedIn } = useAuth()
const cart = useCart()

const product = ref<Product | null>(null)
const loading = ref(true)
const error = ref('')
const notice = ref('')
const busy = ref(false)

onMounted(async () => {
  try {
    product.value = await request<Product>(`/api/products/${encodeURIComponent(String(route.params.id))}`)
  } catch (e) {
    error.value = (e as Error).message
  } finally {
    loading.value = false
  }
})

async function add() {
  if (!product.value) return
  if (!loggedIn.value) return navigateTo({ path: '/login', query: { redirect: route.fullPath } })
  busy.value = true
  error.value = ''
  try {
    await cart.add(product.value.id)
    notice.value = 'Added to your cart.'
  } catch (e) {
    error.value = (e as Error).message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <section>
    <p><NuxtLink to="/">← All products</NuxtLink></p>
    <p v-if="loading" class="muted">Loading…</p>
    <p v-if="error" class="error">{{ error }}</p>
    <div v-if="product" class="detail">
      <img v-if="product.image_url" :src="product.image_url" :alt="product.name" class="product-img">
      <div v-else class="product-img">No image</div>
      <div>
        <h1>{{ product.name }}</h1>
        <p class="muted">{{ product.category }}</p>
        <p>{{ product.description }}</p>
        <p class="price">{{ formatMoney(product.price_cents) }}</p>
        <div class="row">
          <button type="button" :disabled="busy" @click="add">Add to cart</button>
          <span v-if="notice" class="ok">{{ notice }} <NuxtLink to="/cart">View cart</NuxtLink></span>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.detail { display: grid; grid-template-columns: minmax(0, 360px) 1fr; gap: 2rem; }
@media (max-width: 640px) { .detail { grid-template-columns: 1fr; } }
</style>
