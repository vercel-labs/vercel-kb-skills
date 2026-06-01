---
name: troubleshooting
description: "The common errors after moving a TanStack Start app from Netlify to Vercel and how to fix them: leftover @netlify/ platform calls, env vars that are undefined at runtime, Vercel Blob auth failing in local dev, and API routes that return 404."
keywords: [troubleshooting, netlify error, @netlify/blobs, getStore, environment variables undefined, VERCEL_OIDC_TOKEN, blob auth, 404, api routes, routes/api, redeploy, vercel env pull]
---

# Troubleshooting

## Netlify platform calls fail at runtime

Server code still calls Netlify-only APIs such as Netlify Blobs, the Netlify Functions `Context` object, or edge function imports. These packages depend on Netlify's runtime and won't connect when the app runs on Vercel. Search the project for `@netlify/` and replace each call with its Vercel equivalent (see `service-mapping.md`):

```bash
grep -rn "@netlify/" --include="*.ts" --include="*.tsx" .
```

## Environment variables are undefined at runtime

Confirm each variable exists in the right environment (production, preview, or development) in project settings, then redeploy. A variable added only to production is not available in preview or development unless it is added there too. For local runs, run `vercel env pull` again after changing variables.

## Vercel Blob authentication fails during local development

Run `vercel env pull` to download a short-lived `VERCEL_OIDC_TOKEN` and `BLOB_STORE_ID` into the local `.env`, then keep Blob access inside server functions. With Vite, only variables prefixed with `VITE_` reach client code, so reading blob credentials from the client won't work.

## API routes return a 404

Nitro's `/api` directory convention does not work on Vercel. Move standalone API handlers to `routes/api/` so Nitro builds the right Vercel Functions.
