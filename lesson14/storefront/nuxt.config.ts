// https://nuxt.com/docs/api/configuration/nuxt-config
// Static SPA: `nuxt generate` writes .output/public (index.html + 200.html) for S3 behind CloudFront,
// which serves /api/* from the same origin. In dev, /api is proxied to the compose router.
export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  ssr: false,
  devtools: { enabled: false },
  app: {
    head: {
      title: 'Lesson 14 Shop',
      htmlAttrs: { lang: 'en' },
      meta: [{ name: 'viewport', content: 'width=device-width, initial-scale=1' }]
    }
  },
  nitro: {
    devProxy: {
      '/api': { target: 'http://localhost:8000/api', changeOrigin: true }
    }
  }
})
