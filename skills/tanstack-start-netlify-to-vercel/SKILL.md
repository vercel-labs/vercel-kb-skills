---
name: tanstack-start-netlify-to-vercel
description: "Migrate a TanStack Start application from Netlify to Vercel. Use this skill when a user wants to move, migrate, or port a TanStack Start (or TanStack) app off Netlify onto Vercel. This covers swapping @netlify/vite-plugin-tanstack-start for Nitro, removing netlify.toml, repointing Netlify Blobs and Netlify DB to Vercel storage (Vercel Blob, Redis, Edge Config, Postgres), and moving Scheduled Functions and Background Functions to their Vercel equivalents (Cron Jobs and Queues), then deploying. Triggers include phrases like 'migrate to Vercel', 'move off Netlify', 'TanStack Start Netlify to Vercel', or the presence of netlify.toml, @netlify/vite-plugin-tanstack-start, or @netlify/blobs imports in a TanStack project. Do not use for non-TanStack frameworks or for migrations in the opposite direction (Vercel to Netlify)."
license: Apache-2.0
compatibility: Requires git or the Vercel CLI, and access to the internet
allowed-tools: Bash(git:*) Bash(vercel:*) Read
metadata:
  author: vercel
  version: "1.0.0"
  one-liner: "Migrate a TanStack Start app from Netlify to Vercel"
  guide: "https://vercel.com/kb/guide/migrate-a-tanstack-start-app-from-netlify-to-vercel"
---

# Migrate TanStack Start from Netlify to Vercel

## What this skill does

Moving a TanStack Start app from Netlify to Vercel mostly means swapping the deployment layer, not rewriting the app. The Netlify Vite plugin gets replaced with Nitro, the `netlify.toml` config is removed, and storage and scheduled work point at Vercel equivalents. On Vercel, TanStack Start runs on Vercel Functions with Fluid compute on by default, so the app scales with traffic on its own.

The app code (routes, components, server functions) mostly stays the same. The work sits in three places: the Vite and build config, the Netlify config that gets deleted, and any code that called Netlify platform primitives such as Blobs.

## The Vercel Plugin

The user will have installed the [Vercel Plugin](https://vercel.com/docs/agent-resources/vercel-plugin.md) already, which among other things includes a number of helpful skills that can assist you and the user with this migration. Prefer those skills for current, detailed product guidance, and let this skill drive the order of work. The ones that line up with these steps:

- `vercel-storage` and `marketplace`: step 4 (Blob, Edge Config, Neon, Upstash, and Marketplace provisioning).
- `env-vars`: steps 4 and 5 (`vercel env`, `.env` files, OIDC tokens).
- `vercel-cli` and `deployments-cicd`: steps 5 and 7 (env vars and deploy).
- `vercel-functions` and `workflow`: step 6 (Cron Jobs and Workflows).

There are other skills included that may assist with the migration.

## Steps the user completes manually

You handle most of the migration directly by editing files and running commands. A few actions need the Vercel dashboard, a Vercel account, or secret values, so the user has to do those:

- Creating the Vercel account (see Before you start).
- Creating and connecting the backing stores in step 4.
- Adding environment variables in step 5, and the `CRON_SECRET` in step 6.
- Deploying in step 7.

Guide the user through each of these. Give clear, specific instructions, then wait for them to confirm before moving on. Do not report any of them as done while the user still has to do it.

If you are unsure about a dashboard flow or whether a detail is still current, use an applicable Vercel skill when one is available (see "The Vercel Plugin" above), and check the latest with a web search scoped to the vercel.com domain (for example, `site:vercel.com vercel blob oidc token`).

## Service mapping (quick reference)

| Netlify | Vercel |
| --- | --- |
| Netlify Functions (serverless) | [Vercel Functions](https://vercel.com/docs/functions) (Fluid compute) |
| Netlify Edge Functions | [Vercel Functions](https://vercel.com/docs/functions) (Fluid compute), or Routing Middleware for request-time logic |
| `@netlify/vite-plugin-tanstack-start` | [Nitro Vite plugin](https://v3.nitro.build/) (`nitro/vite`) |
| `netlify.toml` | `vercel.json` (optional) and `nitro.config.ts` |
| Netlify CLI (`netlify deploy`) | Git push or the `vercel` CLI |
| Netlify environment variables | Vercel environment variables (`process.env`) |
| Netlify Blobs (file storage) | [Vercel Blob](https://vercel.com/storage/blob) |
| Netlify Blobs (key/value data) | [Redis on the Vercel Marketplace](https://vercel.com/marketplace?search=Redis), or [Edge Config](https://vercel.com/storage/edge-config) for read-heavy config |
| Netlify DB (Postgres via Neon) | [Postgres on the Vercel Marketplace](https://vercel.com/marketplace?search=postgres) |
| Scheduled Functions | [Vercel Cron Jobs](https://vercel.com/docs/cron-jobs) |
| Background Functions and Async Workloads | [Vercel Queues](https://vercel.com/docs/queues) |
| Netlify Image CDN | [Vercel Image Optimization](https://vercel.com/docs/image-optimization) |
| Cache API (fine-grained caching) | Vercel CDN caching with `Cache-Control` headers and Nitro route rules |
| Netlify AI Gateway | [Vercel AI Gateway](https://vercel.com/ai-gateway) with the [AI SDK](https://ai-sdk.dev/) |
| Netlify Forms | No direct equivalent. Use a form backend (e.g., Formspree) or a function that writes to storage |

## Before you start

Check the repo for these, and ask the user to confirm anything the repo cannot show:

- A working TanStack Start app on Netlify. Look for `@tanstack/react-start` in `package.json` to confirm the framework before changing anything.
- Node.js 20 or later.
- A Vercel account (the user confirms this; you cannot create one).
- The Vercel CLI, for the env and deploy steps: `npm i -g vercel`.

Do not use this skill for a different framework, a brand-new app (set it up for Vercel directly instead), or a move in the other direction (Vercel to Netlify).

## Steps

Work through these in order. Step 0 tells you which of steps 4 to 6 apply, so you can skip what the app does not use.

### Step 0: Audit the current Netlify setup

Run the audit script from the project root:

```bash
bash scripts/audit.sh /path/to/project
```

It reports the Netlify config, every `@netlify/` import, which platform features are in use (Blobs, Netlify DB, Functions, Edge Functions), whether Scheduled Functions or Background Functions are set up, any older `target: 'netlify'` or `preset: 'netlify'` setting, and where the Netlify Vite plugin is referenced. Use the output to pick which later steps apply, then show the user a short checklist. Skipping this leads to missed Netlify calls and runtime errors.

### Step 1: Replace the Netlify Vite plugin with Nitro

Install Nitro:

```bash
npm i nitro
```

In `vite.config.ts`, replace the `netlify()` plugin with `nitro()` from `nitro/vite`, and remove the import from `@netlify/vite-plugin-tanstack-start`:

```ts
import { defineConfig } from 'vite';
import { tanstackStart } from '@tanstack/react-start/plugin/vite';
import { nitro } from 'nitro/vite';
import viteReact from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [tanstackStart(), nitro(), viteReact()],
});
```

Nitro detects Vercel during a Vercel build and applies the `vercel` preset, so no extra config is needed.

If the app is on an older TanStack Start version, remove its Netlify target too. Versions 1.121.0 to 1.131.x set `tanstackStart({ target: 'netlify' })` in `vite.config.ts`, and versions before 1.121.0 set `preset: 'netlify'` in `app.config.ts`. Delete either setting so Nitro can apply the `vercel` preset instead.

### Step 2: Remove the Netlify configuration

- Delete `netlify.toml`, including its `publish = "dist/client"` setting. Vercel auto-detects the TanStack Start output through Nitro.
- Uninstall the Netlify packages: `npm uninstall @netlify/vite-plugin-tanstack-start`. Also remove any `@netlify/functions`, `@netlify/blobs`, or `@netlify/edge-functions` packages once you've migrated the code that used them.
- If `netlify.toml` contained redirects, rewrites, or custom headers (or you used `_redirects` and `_headers` files), recreate them as Nitro route rules or in `vercel.json`.

If the app used a `netlify/functions` or `netlify/edge-functions` directory for standalone functions, or relied on Background Functions and Scheduled Functions, see step 6 and `references/service-mapping.md` for the Vercel approach.

### Step 3: Update the build scripts

In `package.json`, replace any Netlify-specific scripts (such as one that calls `netlify deploy`) with plain Vite commands:

```json
{
  "scripts": {
    "dev": "vite dev",
    "build": "vite build"
  }
}
```

Vercel detects TanStack Start on import and sets the build command and output directory, so the remaining scripts mainly support local development.

### Step 4: Replace Netlify Blobs with Vercel storage

This is the main code change. On Netlify, server code imports `getStore` from `@netlify/blobs` and calls methods such as `store.set()` and `store.get()`. On Vercel, connection details come from `process.env` and each store is reached through its own SDK. For every Netlify Blobs usage the audit found, remove the `import { getStore } from "@netlify/blobs"` line and replace the blob calls. Read `references/service-mapping.md` for the before and after code, then install the SDK you need, for example:

```bash
npm i @vercel/blob
```

Have the user create and connect the backing stores. This is what adds the env vars the code reads, so it has to be done before the app will run:

- File storage to Blob: create a Blob store on the [Storage page](https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fstores), then connect it to the project from the store's Projects tab. Vercel adds `BLOB_STORE_ID` and a short-lived `VERCEL_OIDC_TOKEN` that it rotates automatically. The SDK pairs the two, so `put()` needs no token in code. This [OIDC approach](https://vercel.com/docs/vercel-blob/using-blob-sdk) is recommended over the long-lived `BLOB_READ_WRITE_TOKEN`, which is only for code that runs outside Vercel.
- Key/value Blobs to Redis: add a Redis integration such as [Upstash Redis](https://vercel.com/marketplace/upstash/upstash-kv) for caching and session data, or use [Edge Config](https://vercel.com/storage/edge-config) for small, read-heavy config.
- Netlify DB to Postgres: add a Postgres database such as [Neon](https://vercel.com/marketplace/neon).

Provisioning a store from the Marketplace adds its connection string and credentials as env vars, which the code reads from `process.env`.

### Step 5: Move environment variables and secrets

Netlify keeps these in the dashboard, CLI, or API. Vercel keeps them per environment: production, preview, and development. Variables set only in `netlify.toml` were never available to Netlify Functions, so check the dashboard or run `netlify env:list` to find the full set before moving them.

> **Never handle the user's secrets.** Do not ask the user for secret values, and do not accept secrets pasted into the chat. Do not offer to save, enter, or store environment variables or secrets for the user, and refuse if asked to do so. Setting the actual values is the user's job, done in the dashboard or in their own terminal. Your part is to prepare the list of variable names and the exact commands.

You can list every variable and secret to recreate and write out the exact commands, but you cannot supply secret values or sign the CLI in, and you must not make up values.

The user adds each variable, either on the [project's Environment Variables page](https://vercel.com/d?to=%2F%5Bteam%5D%2F%5Bproject%5D%2Fsettings%2Fenvironment-variables) or with the CLI after `vercel login`:

```bash
vercel env add DATABASE_URL production
```

Once the user has signed in, you can link the project and pull the values into a local `.env`:

```bash
vercel link
vercel env pull
```

`vercel env pull` writes a `.env` file with the [development environment variables](https://vercel.com/docs/environment-variables#development-environment-variables). Vercel allows up to 64 KB of environment variables per deploy across all variables combined. A variable added to production is not available in preview or development unless it is added there too.

### Step 6: Move scheduled functions and background work (only if the audit found them)

Nitro maps the scheduled side to Vercel Cron Jobs at build time, and you use Vercel Queues for background message processing. Skip this step if the app uses neither.

On Netlify, a schedule is set by exporting a `config` object with a `schedule` cron expression from a function, or by declaring it in `netlify.toml`. On Vercel, define Nitro scheduled tasks in `nitro.config.ts`. Nitro turns them into Vercel Cron Jobs at build, so there is no need to write any `vercel.json` cron config by hand:

```ts
import { defineConfig } from 'nitro';

export default defineConfig({
  experimental: {
    tasks: true,
  },
  scheduledTasks: {
    // Run the cms:update task every hour
    '0 * * * *': ['cms:update'],
  },
});
```

The user sets a `CRON_SECRET` env var in the project (same as step 5). When `CRON_SECRET` is set, Nitro checks the `Authorization` header on every cron call.

For message processing, replace Netlify Background Functions and Async Workloads with Vercel Queues. Define topics under `vercel.queues` in `nitro.config.ts`:

```ts
import { defineConfig } from 'nitro';

export default defineConfig({
  vercel: {
    queues: {
      triggers: [{ topic: 'orders' }],
    },
  },
});
```

Handle incoming messages with the `vercel:queue` hook in a Nitro plugin under `server/plugins/`:

```ts
export default defineNitroPlugin((nitro) => {
  nitro.hooks.hook('vercel:queue', ({ message, metadata }) => {
    console.log(`[${metadata.topicName}] Message ${metadata.messageId}:`, message);
  });
});
```

To send messages, install `@vercel/queue` and call `send()` from a server function:

```bash
npm i @vercel/queue
```

```ts
const { messageId } = await send('orders', order);
```

For long-running, multi-step work that Netlify background work handled, look at [Vercel Workflows](https://vercel.com/workflows), which run durable steps on Vercel Functions and Vercel Queues.

### Step 7: Deploy

You cannot import a project, confirm the framework preset, sign in, or select Deploy, so walk the user through one of these paths. Both build the app with Nitro's Vercel preset and run it on Vercel Functions.

Deploy with Git (recommended):

1. Push the project to GitHub, GitLab, or Bitbucket.
2. In the [Vercel dashboard](https://vercel.com), select Add New > Project, then import the repo.
3. Vercel detects TanStack Start and sets the build command and output directory. Confirm the framework preset, add the environment variables from step 5, and select Deploy.

After the first import, every push to the production branch creates a production deploy, and every pull request gets its own preview URL.

Deploy with the CLI: after `vercel login`, run `vercel` for a preview or `vercel --prod` for production.

If the `vercel-deploy` skill is available, you can use it to create a preview deploy and a claim URL without the user signing in first, which is a good way to check the build before wiring up a connected project.

## After the move: check these

You can grep for the code issues; ask the user to check anything in the dashboard. See `references/troubleshooting.md` for fixes.

- No `@netlify/` imports remain anywhere in server code.
- Each env var exists in the right environment, not only production.
- Standalone API handlers live under `routes/api/`. Nitro's `/api` convention does not work on Vercel and returns 404.

## Tune after migrating (optional)

- Recreate Netlify redirects, rewrites, and headers as Nitro route rules or in `vercel.json` so requests resolve the same way.
- Set function resources per route with `vercel.functionRules` in `nitro.config.ts` to override `maxDuration`, `memory`, or `regions` for the routes that need more than the default.
- Put functions near the data: set `regions` in `functionRules` or project settings close to the Marketplace database to cut latency.

## References

- [service-mapping](references/service-mapping.md): Before and after code for replacing each Netlify primitive (Blobs file storage to Blob, Blobs key/value to Redis or Edge Config, Netlify DB to Postgres, Image CDN, AI Gateway, Forms), plus the store setup notes. Read before step 4.
- [troubleshooting](references/troubleshooting.md): The common errors after the move and how to fix them.
