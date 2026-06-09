---
name: troubleshooting
description: "The common errors after moving an Astro app from Webflow Cloud to Vercel and how to fix them: a leftover @astrojs/cloudflare reference, locals.runtime reads throwing on Vercel, assets or routes returning 404 from a leftover base path, and env vars undefined at runtime."
keywords: [troubleshooting, @astrojs/cloudflare, cannot find module, locals.runtime.env, cannot read properties of undefined, base path, assetsPrefix, 404, environment variables undefined, process.env, vercel env pull, redeploy]
---

# Troubleshooting

## "Cannot find module '@astrojs/cloudflare'"

Your config or server code still references the Cloudflare adapter, which only resolves within the build that targets Cloudflare Workers. Search the project for `@astrojs/cloudflare` and `locals.runtime`, then remove the adapter import and `platformProxy` from `astro.config.mjs` and replace each binding call with its Vercel equivalent (see `service-mapping.md`):

```bash
grep -rnE "@astrojs/cloudflare|locals\.runtime|locals as" --include="*.ts" --include="*.tsx" --include="*.astro" --include="*.mjs" .
```

## Reading `runtime` throws "Cannot read properties of undefined"

Code still reads `locals.runtime.env` (or `Astro.locals.runtime.env`), which only exists when the Cloudflare adapter populates it. On Vercel that object isn't present. Replace `locals.runtime.env.VARIABLE` with `process.env.VARIABLE` for secrets and connection strings, and use the relevant SDK for storage (see `service-mapping.md`).

## Assets or routes return a 404

A leftover base path is usually the cause. Confirm you removed `base` and `build.assetsPrefix` from `astro.config.mjs`, and removed the manual base-path prefixing from client-side `fetch` calls, `<img>` tags, and your layout's favicon link. On Vercel the app is served from the root, so paths like `/api/users` and `/logo.png` resolve without a prefix.

## Environment variables are undefined at runtime

Confirm each variable exists in the right environment (production, preview, or development) in project settings, then redeploy. A variable added only to production is not available in preview or development unless it is added there too. For local runs, run `vercel env pull` again after changing variables.
