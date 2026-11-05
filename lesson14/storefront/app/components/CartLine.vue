<script setup lang="ts">
const props = defineProps<{ item: CartItem, product?: Product, busy?: boolean }>()
const emit = defineEmits<{ update: [productId: string, quantity: number] }>()

// Only a whole number 0..99 is sent. Anything else (empty, "1.5", "abc", 150) puts the input back to
// the current quantity and sends nothing.
function onChange(e: Event) {
  const input = e.target as HTMLInputElement
  const raw = input.value.trim()
  const qty = Number(raw)
  if (!/^\d+$/.test(raw) || qty > MAX_QUANTITY) {
    input.value = String(props.item.quantity)
    return
  }
  emit('update', props.item.product_id, qty)
}
</script>

<template>
  <div class="card row spread">
    <div>
      <NuxtLink :to="`/products/${item.product_id}`">{{ product?.name ?? item.product_id }}</NuxtLink>
      <div v-if="product" class="muted">{{ formatMoney(product.price_cents) }} each</div>
      <div v-else class="muted">Product no longer available</div>
    </div>
    <div class="row">
      <input
        type="number" min="0" :max="MAX_QUANTITY" :value="item.quantity" :disabled="busy"
        aria-label="Quantity" style="width: 5rem" @change="onChange"
      >
      <span v-if="product" class="price">{{ formatMoney(product.price_cents * item.quantity) }}</span>
      <button type="button" class="secondary" :disabled="busy" @click="emit('update', item.product_id, 0)">Remove</button>
    </div>
  </div>
</template>
