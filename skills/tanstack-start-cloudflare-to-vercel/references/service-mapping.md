---
name: service-mapping
description: "Before and after code for replacing each Cloudflare binding with its Vercel equivalent (R2 to Blob, Workers KV to Redis or Edge Config, D1 to Postgres, Durable Objects, Workers AI to AI Gateway), plus notes on the store setup the user does in the dashboard. Read before step 4."
keywords: [bindings, R2, Vercel Blob, Workers KV, Redis, Upstash, Edge Config, D1, Postgres, Neon, Durable Objects, Workers AI, AI Gateway, cloudflare:workers, process.env, store setup]
---

# Cloudflare to Vercel binding code

Read this before step 4 in SKILL.md. On Cloudflare, server code imports `env` from `cloudflare:workers` and calls bindings such as `env.MY_BUCKET`. On Vercel, connection details come from `process.env`, and each store is reached through its own SDK. For every binding, remove the `cloudflare:workers` import and replace the call.

Creating and connecting the stores themselves is a user step in the dashboard (see step 4 in SKILL.md). The code here assumes those stores exist and their env vars are present.

## R2 to Vercel Blob

Install the SDK:

```bash
npm i @vercel/blob
```

Before, an R2 upload on Cloudflare:

```ts
// Before (Cloudflare R2)
import { createServerFn } from '@tanstack/react-start';
import { env } from 'cloudflare:workers';

const uploadFile = createServerFn({ method: 'POST' })
  .validator((data: { key: string; content: string }) => data)
  .handler(async ({ data }) => {
    await env.MY_BUCKET.put(data.key, data.content);
    return { success: true };
  });
```

After, the same upload with Vercel Blob:

```ts
// After (Vercel Blob)
import { createServerFn } from '@tanstack/react-start';
import { put } from '@vercel/blob';

const uploadFile = createServerFn({ method: 'POST' })
  .validator((data: { key: string; content: string }) => data)
  .handler(async ({ data }) => {
    const blob = await put(data.key, data.content, { access: 'public' });
    return { url: blob.url };
  });
```

The `put()` call needs no token. Connecting the Blob store to the project adds `BLOB_STORE_ID` and a rotating `VERCEL_OIDC_TOKEN`, and the SDK pairs them.

## Workers KV to Redis or Edge Config

- For caching and session data, point the code at a Redis integration from the Marketplace (such as Upstash Redis). Replace `env.MY_KV.get(...)` and `.put(...)` with the Redis client's `get` and `set`, reading the connection string from `process.env`.
- For small, read-heavy config, use Edge Config instead.

## D1 to Postgres

Point the code at a Postgres database from the Marketplace (such as Neon). Replace D1's `env.DB.prepare(...).bind(...).run()` query API with a Postgres client or ORM, reading the connection string from `process.env`. The store provisioning and the choice of client are the user's call; do not assume one.

## Durable Objects: no direct equivalent

Durable Objects combine compute and per-object state, and there is no single Vercel feature that matches them. Move the shared state into a database or Redis and coordinate through it. This is the part most likely to need real code changes rather than a line-for-line swap, so flag it to the user instead of guessing at the rewrite. If a custom `src/server.ts` existed only to export Durable Objects, that export goes away.

## Workers AI (`env.AI`) to AI Gateway

Replace `env.AI` calls with the AI SDK pointed at Vercel AI Gateway. This is a change in how the code calls the model, not a config swap, so raise it with the user and migrate the calls on purpose rather than mechanically.