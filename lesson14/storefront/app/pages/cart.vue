<script setup lang="ts">
definePageMeta({ middleware: 'auth' })

const view = useCartView()
const { products, items, totalCents, loading, error } = view
const { setQuantity } = useCart()
const busy = ref(false)

onMounted(view.load)

async function update(productId: string, quantity: number) {
  busy.value = true
  error.value = ''
  try {
    await view.setCart(await setQuantity(productId, quantity))
  } catch (e) {
    error.value = (e as Error).message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <section>
    <h1>Your cart</h1>
    <p v-if="error" class="error">{{ error }}</p>
    <p v-if="loading" class="muted">Loading…</p>
    <template v-else-if="items.length">
      <div class="lines">
        <CartLine
          v-for="item in items" :key="item.product_id"
          :item="item" :product="products[item.product_id]" :busy="busy" @update="update"
        />
      </div>
      <div class="row spread">
        <span class="price">Total: {{ formatMoney(totalCents) }}</span>
        <button type="button" :disabled="busy" @click="navigateTo('/checkout')">Checkout</button>
      </div>
    </template>
    <p v-else class="muted">Your cart is empty. <NuxtLink to="/">Browse products</NuxtLink></p>
  </section>
</template>
