<script setup lang="ts">
const props = defineProps<{ status: OrderStatus }>()
const label = computed(() => ({
  PENDING_PAYMENT: 'Pending payment',
  PAID: 'Paid',
  PAYMENT_FAILED: 'Payment failed'
})[props.status] ?? props.status)
</script>

<template>
  <span class="status" :class="status">{{ label }}</span>
</template>
