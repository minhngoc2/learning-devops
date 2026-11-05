<script setup lang="ts">
const { login } = useAuth()
const route = useRoute()

const email = ref('')
const password = ref('')
const error = ref('')
const busy = ref(false)

// Only same-site paths, so ?redirect= cannot send the user to another origin.
function target(): string {
  const r = route.query.redirect
  return typeof r === 'string' && r.startsWith('/') && !r.startsWith('//') ? r : '/'
}

async function submit() {
  busy.value = true
  error.value = ''
  try {
    await login(email.value.trim(), password.value)
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
    <h1>Log in</h1>
    <form class="form" @submit.prevent="submit">
      <label>Email <input v-model="email" type="email" autocomplete="email" required></label>
      <label>Password <input v-model="password" type="password" autocomplete="current-password" required></label>
      <button type="submit" :disabled="busy">Log in</button>
      <p v-if="error" class="error">{{ error }}</p>
      <p class="muted">No account? <NuxtLink :to="{ path: '/register', query: route.query }">Register</NuxtLink></p>
    </form>
  </section>
</template>
