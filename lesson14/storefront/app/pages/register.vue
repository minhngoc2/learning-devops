<script setup lang="ts">
const { register } = useAuth()
const route = useRoute()

const displayName = ref('')
const email = ref('')
const password = ref('')
const error = ref('')
const busy = ref(false)

function target(): string {
  const r = route.query.redirect
  return typeof r === 'string' && r.startsWith('/') && !r.startsWith('//') ? r : '/'
}

async function submit() {
  busy.value = true
  error.value = ''
  try {
    await register(email.value.trim(), password.value, displayName.value.trim())
    await navigateTo(target())
  } catch (e) {
    error.value = (e as Error).message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <section>
    <h1>Register</h1>
    <form class="form" @submit.prevent="submit">
      <label>Display name <input v-model="displayName" type="text" autocomplete="name" required></label>
      <label>Email <input v-model="email" type="email" autocomplete="email" required></label>
      <label>Password <input v-model="password" type="password" autocomplete="new-password" minlength="8" required></label>
      <button type="submit" :disabled="busy">Create account</button>
      <p v-if="error" class="error">{{ error }}</p>
      <p class="muted">Already registered? <NuxtLink :to="{ path: '/login', query: route.query }">Log in</NuxtLink></p>
    </form>
  </section>
</template>
