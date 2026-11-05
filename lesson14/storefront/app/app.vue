<script setup lang="ts">
const { loggedIn, customer, loadCustomer, logout } = useAuth()

onMounted(() => {
  loadCustomer().catch(() => {})
})

async function signOut() {
  logout()
  await navigateTo('/')
}
</script>

<template>
  <div class="shell">
    <NuxtRouteAnnouncer />
    <header class="topbar">
      <NuxtLink to="/" class="brand">Lesson 14 Shop</NuxtLink>
      <nav>
        <NuxtLink to="/">Products</NuxtLink>
        <template v-if="loggedIn">
          <NuxtLink to="/cart">Cart</NuxtLink>
          <NuxtLink to="/orders">Orders</NuxtLink>
          <span class="who">{{ customer?.display_name || customer?.email }}</span>
          <button class="link" type="button" @click="signOut">Log out</button>
        </template>
        <template v-else>
          <NuxtLink to="/login">Log in</NuxtLink>
          <NuxtLink to="/register">Register</NuxtLink>
        </template>
      </nav>
    </header>
    <main>
      <NuxtPage />
    </main>
  </div>
</template>

<style>
* { box-sizing: border-box; }
body {
  margin: 0;
  font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  color: #1f2937;
  background: #f6f7f9;
}
a { color: #2563eb; text-decoration: none; }
a:hover { text-decoration: underline; }
h1 { font-size: 1.6rem; margin: 0 0 1rem; }
.shell { max-width: 1040px; margin: 0 auto; padding: 0 1rem 3rem; }
.topbar {
  display: flex; align-items: center; justify-content: space-between; gap: 1rem;
  padding: 1rem 0; margin-bottom: 1.5rem; border-bottom: 1px solid #e5e7eb;
}
.brand { font-weight: 700; font-size: 1.2rem; color: #111827; }
.topbar nav { display: flex; align-items: center; gap: 1rem; flex-wrap: wrap; }
.who { color: #6b7280; font-size: .9rem; }
button {
  font: inherit; cursor: pointer; border: 0; border-radius: 6px;
  padding: .5rem 1rem; background: #2563eb; color: #fff;
}
button:hover:not(:disabled) { background: #1d4ed8; }
button:disabled { opacity: .5; cursor: default; }
button.secondary { background: #e5e7eb; color: #111827; }
button.secondary:hover:not(:disabled) { background: #d1d5db; }
button.link { background: none; color: #2563eb; padding: 0; }
input {
  font: inherit; padding: .5rem .6rem; border: 1px solid #d1d5db; border-radius: 6px; background: #fff;
}
.card { background: #fff; border: 1px solid #e5e7eb; border-radius: 10px; padding: 1rem; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 1rem; }
.product-img {
  width: 100%; aspect-ratio: 1; object-fit: cover; border-radius: 8px; background: #eef0f3;
  display: flex; align-items: center; justify-content: center; color: #9ca3af;
}
.price { font-weight: 600; }
.muted { color: #6b7280; }
.error { color: #b91c1c; }
.ok { color: #047857; }
.form { display: flex; flex-direction: column; gap: .75rem; max-width: 360px; }
.form label { display: flex; flex-direction: column; gap: .25rem; font-size: .9rem; }
.row { display: flex; align-items: center; gap: .75rem; }
.spread { justify-content: space-between; }
.lines { display: flex; flex-direction: column; gap: .5rem; margin-bottom: 1rem; }
.status { display: inline-block; padding: .15rem .6rem; border-radius: 999px; font-size: .85rem; font-weight: 600; }
.status.PENDING_PAYMENT { background: #fef3c7; color: #92400e; }
.status.PAID { background: #d1fae5; color: #065f46; }
.status.PAYMENT_FAILED { background: #fee2e2; color: #991b1b; }
table { width: 100%; border-collapse: collapse; }
th, td { text-align: left; padding: .5rem; border-bottom: 1px solid #e5e7eb; }
</style>
