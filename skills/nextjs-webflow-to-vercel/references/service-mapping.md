---
name: service-mapping
description: "Before and after code for replacing each Webflow Cloud storage binding with its Vercel equivalent (Object Storage/R2 to Vercel Blob, Key Value Store/Workers KV to Redis or Edge Config, SQLite/D1 to Postgres), plus notes on the store setup the user does in the dashboard. Read before step 5."
keywords: [bindings, getCloudflareContext, Object Storage, R2, Vercel Blob, Key Value Store, Workers KV, Redis, Upstash, Edge Config, SQLite, D1, Postgres, Neon, process.env, store setup, Route Handler]
---

# Webflow Cloud to Vercel storage code

Read this before step 5 in SKILL.md. On Webflow Cloud, server code reads storage bindings off the Cloudflare `env`, accessed in a Route Handler with `getCloudflareContext()` from `@opennextjs/cloudflare`. On Vercel, connection details come from `process.env`, and each store is reached through its own SDK or client. For every binding, remove the `getCloudflareContext()` access and replace the call.

Creating and connecting the stores themselves is a user step in the dashboard (see step 5 in SKILL.md). The code here assumes those stores exist and their env vars are present.

## Object Storage (R2) to Vercel Blob

Install the SDK:

```bash
npm i @vercel/blob
```

Before, an Object Storage upload on Webflow Cloud. Note the binding read off `getCloudflareContext()`:

```ts
// Before (Webflow Cloud Object Storage, R2 binding)
import { getCloudflareContext } from "@opennextjs/cloudflare";

export async function POST(request: Request) {
  const { key, content } = await request.json();
  const { env } = getCloudflareContext();
  await env.MEDIA_BUCKET.put(key, content);
  return Response.json({ success: true });
}
```

After, the same upload with Vercel Blob. The `getCloudflareContext()` call is gone and the binding is replaced by the SDK:

```ts
// After (Vercel Blob)
import { put } from "@vercel/blob";

export async function POST(request: Request) {
  const { key, content } = await request.json();
  const blob = await put(key, content, { access: "public" });
  return Response.json({ url: blob.url });
}
```

The `put()` call needs no token. Connecting the Blob store to the project adds the store's environment variables, including a short-lived `VERCEL_OIDC_TOKEN` that Vercel rotates, and the SDK uses them automatically. This OIDC approach is recommended over the long-lived `BLOB_READ_WRITE_TOKEN`, which is only for code that runs outside Vercel.

## Key Value Store (Workers KV) to Redis or Edge Config

- For caching and session data, point the code at a Redis integration from the Marketplace (such as Upstash Redis). Replace `env.MY_KV.get(...)` and `.put(...)` with the Redis client's `get` and `set`, reading the connection string from `process.env`.
- For small, read-heavy config, use Edge Config instead.

## SQLite (D1) to Postgres

Point the code at a Postgres database from the Marketplace (such as Neon). Replace D1's `env.DB.prepare(...).bind(...).run()` query API with a Postgres client or ORM, reading the connection string from `process.env`. The store provisioning and the choice of client are the user's call; do not assume one.
