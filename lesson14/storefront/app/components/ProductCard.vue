<script setup lang="ts">
defineProps<{ product: Product, busy?: boolean }>()
defineEmits<{ add: [productId: string] }>()
</script>

<template>
  <article class="card product-card">
    <NuxtLink :to="`/products/${product.id}`">
      <img v-if="product.image_url" :src="product.image_url" :alt="product.name" class="product-img" loading="lazy">
      <div v-else class="product-img">No image</div>
    </NuxtLink>
    <NuxtLink :to="`/products/${product.id}`" class="name">{{ product.name }}</NuxtLink>
    <div class="row spread">
      <span class="price">{{ formatMoney(product.price_cents) }}</span>
      <button type="button" :disabled="busy" @click="$emit('add', product.id)">Add to cart</button>
    </div>
  </article>
</template>

<style scoped>
.product-card { display: flex; flex-direction: column; gap: .6rem; }
.name { font-weight: 600; color: #111827; }
</style>
