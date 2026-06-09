---
name: service-mapping
description: "Before and after code for replacing each Webflow Cloud storage binding with its Vercel equivalent (Object Storage/R2 to Vercel Blob, Key Value Store/Workers KV to Redis or Edge Config, SQLite/D1 to Postgres), plus notes on the store setup the user does in the dashboard. Read before step 5."
keywords: [bindings, locals.runtime.env, Astro.locals.runtime.env, Object Storage, R2, Vercel Blob, Key Value Store, Workers KV, Redis, Upstash, Edge Config, SQLite, D1, Postgres, Neon, Drizzle, process.env, store setup]
---

# Webflow Cloud to Vercel storage code

Read this before step 5 in SKILL.md. On Webflow Cloud, server code reads storage bindings off the Cloudflare runtime through Astro's `locals` object — `locals.runtime.env` in Server Endpoints and `Astro.locals.runtime.env` in components. On Vercel, connection details come from `process.env`, and each store is reached through its own SDK. For every binding, remove the `locals.runtime.env` access and replace the call.

Creating and connecting the stores themselves is a user step in the dashboard (see step 5 in SKILL.md). The code here assumes those stores exist and their env vars are present.

## Object Storage (R2) to Vercel Blob

Install the SDK:

```bash
npm i @vercel/blob
```

Before, an Object Storage upload on Webflow Cloud. Note the Edge runtime directive and the binding read off `locals.runtime`:

```ts
// Before (Webflow Cloud Object Storage, R2 binding)
export const config = { runtime: "edge" };

import type { APIRoute } from "astro";

export const POST: APIRoute = async ({ request, locals }) => {
  const { key, content } = await request.json();
  const { env } = (locals as any).runtime;
  await env.MEDIA_BUCKET.put(key, content);
  return new Response(JSON.stringify({ success: true }));
};
```

After, the same upload with Vercel Blob. The Edge directive is gone and the binding is replaced by the SDK:

```ts
// After (Vercel Blob)
import type { APIRoute } from "astro";
import { put } from "@vercel/blob";

export const POST: APIRoute = async ({ request }) => {
  const { key, content } = await request.json();
  const blob = await put(key, content, { access: "public" });
  return new Response(JSON.stringify({ url: blob.url }));
};
```

The `put()` call needs no token. Connecting the Blob store to the project adds the store's environment variables, including a short-lived `VERCEL_OIDC_TOKEN` that Vercel rotates, and the SDK uses them automatically. This OIDC approach is recommended over the long-lived `BLOB_READ_WRITE_TOKEN`, which is only for code that runs outside Vercel.

## Key Value Store (Workers KV) to Redis or Edge Config

- For caching and session data, point the code at a Redis integration from the Marketplace (such as Upstash Redis). Replace `env.MY_KV.get(...)` and `.put(...)` with the Redis client's `get` and `set`, reading the connection string from `process.env`.
- For small, read-heavy config, use Edge Config instead.

## SQLite (D1) to Postgres

Point the code at a Postgres database from the Marketplace (such as Neon). Replace D1's `env.DB.prepare(...).bind(...).run()` query API with a Postgres client or ORM, reading the connection string from `process.env`. If you used Drizzle ORM with SQLite on Webflow Cloud, Drizzle supports Postgres too, so you keep your schema-first workflow. The store provisioning and the choice of client are the user's call; do not assume one.
