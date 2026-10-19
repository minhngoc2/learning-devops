# Lesson 12 app

Single-page React/Vite counter demo used to verify the S3/CloudFront deployment. It has no API, environment variables, or client-side router.

From this directory, use Node.js 22.13+ on the 22.x line, or Node.js 24+, with npm:

```sh
npm ci
npm run dev
```

Open the URL printed by Vite (normally `http://localhost:5173`). Edit `src/App.jsx` to change the page.

```sh
npm run lint
npm run build
npm run preview
```

The build goes into `dist/`. Preview serves that build locally, normally at `http://localhost:4173`; it does not reproduce CloudFront caching or S3 permissions.

Vite emits hashed files under `dist/assets/` and copies `public/` files to the build root without hashing their names. See the [quickstart](../quickstart.md) for upload order, cache headers, invalidation, and cleanup.
