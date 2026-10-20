# Nuxt app

The default Nuxt welcome page is the Lesson 12 app. Follow the [quickstart](../quickstart.md) for deployment and cleanup.

## Local development

Run from `nuxt-app/`:

```sh
pnpm install --frozen-lockfile
pnpm dev
```

Open the printed URL, usually `http://localhost:3000`. The default `app/app.vue` needs no changes.

## Static generation and preview

Stop the development server, then run:

```sh
pnpm generate
pnpm preview
```

`generate` prerenders HTML into `.output/public/`; keep the default rendering configuration. Preview uses `pnpm dlx serve` and may download it on first use. Stop with Ctrl+C.

Upload only `.output/public/` contents. Request-time server routes and SSR need a server. Generated HTML and payloads are public.

## Routing

CloudFront maps `/` to `index.html`. Nested URLs need a rewrite to their generated HTML; local preview does not test CloudFront routing. Nuxt’s `200.html` and `404.html` do not enable fallbacks. Include dynamic pages in prerendering.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Root returns 403 | Upload root `index.html`, confirm the OAC bucket policy, and invalidate CloudFront. |
| Old page appears | Check the Terraform destination and wait for invalidation completion. |
| JS/CSS fails | Confirm `/_nuxt/` uploaded before HTML and the app uses the default root base URL. |
| Nested URL returns 403/404 | Add CloudFront URL handling for generated directory indexes. |
| AWS access denied | Check the profile, account, session expiry, and permissions; keep S3 private. |

Keep `pnpm-lock.yaml` in Git. See [Nuxt static hosting](https://nuxt.com/docs/4.x/getting-started/deployment#static-hosting) for rendering options.
