---
name: troubleshooting
description: "The common errors after moving a Next.js app from Webflow Cloud to Vercel and how to fix them: a leftover @opennextjs/cloudflare reference, getCloudflareContext throwing on Vercel, assets or routes returning 404 from a leftover base path, and env vars undefined at runtime."
keywords: [troubleshooting, "@opennextjs/cloudflare", cannot find module, getCloudflareContext, base path, basePath, assetPrefix, 404, environment variables undefined, process.env, vercel env pull, redeploy]
---

# Troubleshooting

## "Cannot find module '@opennextjs/cloudflare'"

Server code still imports the adapter or calls `getCloudflareContext()`, which only resolves within the build that targets Cloudflare Workers. Search the project for `@opennextjs/cloudflare` and `getCloudflareContext`, then remove the adapter import and the `initOpenNextCloudflareForDev()` dev hook from `next.config.ts`, and replace each binding call with its Vercel equivalent (see `service-mapping.md`):

```bash
grep -rnE "@opennextjs/cloudflare|getCloudflareContext" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.mjs" .
```

## `getCloudflareContext()` throws on Vercel

Code still calls `getCloudflareContext()` to read a binding off the Cloudflare `env`. That context only exists when the OpenNext adapter populates it; on Vercel it isn't present. Replace `getCloudflareContext().env.VARIABLE` with `process.env.VARIABLE` for secrets and connection strings, and use the relevant SDK for storage (see `service-mapping.md`).

## Assets or routes return a 404

A leftover base path is usually the cause. Confirm you removed `basePath` and `assetPrefix` from `next.config.ts`, and removed the manual base-path prefixing from client-side `fetch` calls and `<img>` tags. On Vercel the app is served from the root, so paths like `/api/users` and `/logo.png` resolve without a prefix.

## Environment variables are undefined at runtime

Confirm each variable exists in the right environment (production, preview, or development) in project settings, then redeploy. A variable added only to production is not available in preview or development unless it is added there too. For local runs, run `vercel env pull` again after changing variables.
