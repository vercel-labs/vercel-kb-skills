---
name: troubleshooting
description: "The common errors after moving a TanStack Start app from Cloudflare to Vercel and how to fix them: a leftover cloudflare:workers import, env vars that are undefined at runtime, and API routes that return 404."
keywords: [troubleshooting, cloudflare:workers error, cannot find module, environment variables undefined, 404, api routes, routes/api, redeploy, vercel env pull]
---

# Troubleshooting

## "Cannot find module 'cloudflare:workers'"

Server code still imports the Cloudflare bindings module, which only resolves inside the Workers runtime. Search the project and replace each binding call with its Vercel equivalent (see `service-mapping.md`):

```bash
grep -rn "cloudflare:workers" --include="*.ts" --include="*.tsx" .
```

## Environment variables are undefined at runtime

Confirm each variable exists in the right environment (production, preview, or development) in project settings, then redeploy. A variable added only to production is not available in preview or development unless it is added there too. For local runs, run `vercel env pull` again after changing variables.

## API routes return a 404

Nitro's `/api` directory convention does not work on Vercel. Move standalone API handlers to `routes/api/` so Nitro builds the right Vercel Functions.