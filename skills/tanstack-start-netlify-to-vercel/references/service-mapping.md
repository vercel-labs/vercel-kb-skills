---
name: service-mapping
description: "Before and after code for replacing each Netlify platform primitive with its Vercel equivalent (Netlify Blobs file storage to Vercel Blob, Blobs key/value to Redis or Edge Config, Netlify DB to Postgres, Netlify Image CDN, Netlify AI Gateway, Netlify Forms), plus notes on the store setup the user does in the dashboard. Read before step 4."
keywords: [Netlify Blobs, getStore, Vercel Blob, key/value, Redis, Upstash, Edge Config, Netlify DB, Postgres, Neon, Image CDN, Image Optimization, AI Gateway, Netlify Forms, process.env, store setup]
---

# Netlify to Vercel migration code

Read this before step 4 in SKILL.md. On Netlify, server code imports `getStore` from `@netlify/blobs` and calls methods such as `store.set()` and `store.get()`. On Vercel, connection details come from `process.env`, and each store is reached through its own SDK. For every Netlify primitive, remove the `@netlify/` import and replace the call.

Creating and connecting the stores themselves is a user step in the dashboard (see step 4 in SKILL.md). The code here assumes those stores exist and their env vars are present.

## Netlify Blobs (file storage) to Vercel Blob

Install the SDK:

```bash
npm i @vercel/blob
```

Before, a file upload with Netlify Blobs:

```ts
// Before (Netlify Blobs)
import { createServerFn } from '@tanstack/react-start';
import { getStore } from '@netlify/blobs';

const uploadFile = createServerFn({ method: 'POST' })
  .validator((data: { key: string; content: string }) => data)
  .handler(async ({ data }) => {
    const store = getStore('uploads');
    await store.set(data.key, data.content);
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

The `put()` call needs no token. Connecting the Blob store to the project adds `BLOB_STORE_ID` and a rotating `VERCEL_OIDC_TOKEN`, and the SDK pairs them. Keep Blob access inside server functions: with Vite, only variables prefixed with `VITE_` reach client code.

## Netlify Blobs (key/value data) to Redis or Edge Config

Netlify Blobs serves two roles. Map your usage based on how the app used it:

- For caching, session data, or general key/value app data, point the code at a Redis integration from the Marketplace (such as Upstash Redis). Replace `store.get(...)` and `store.set(...)` with the Redis client's `get` and `set`, reading the connection string from `process.env`.
- For small, read-heavy config, use Edge Config instead.

## Netlify DB to Postgres

Netlify DB is Postgres via Neon. Point the code at a Postgres database from the Marketplace (such as Neon). Use a Postgres client or ORM, reading the connection string from `process.env`. The store provisioning and the choice of client are the user's call; do not assume one.

## Netlify Image CDN to Vercel Image Optimization

Replace Netlify Image CDN usage with [Vercel Image Optimization](https://vercel.com/docs/image-optimization). This is a change in how images are requested and served rather than a config swap, so confirm the approach with the user.

## Netlify AI Gateway to Vercel AI Gateway

Replace Netlify AI Gateway calls with the AI SDK pointed at [Vercel AI Gateway](https://vercel.com/ai-gateway). This is a change in how the code calls the model, not a config swap, so raise it with the user and migrate the calls on purpose rather than mechanically.

## Netlify Forms: no direct equivalent

Netlify Forms has no direct Vercel feature. Use a form backend (such as Formspree from the Vercel Marketplace) or a server function that writes submissions to storage. This needs a real decision from the user, so flag it instead of guessing at the rewrite.
