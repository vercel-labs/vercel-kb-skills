# Vercel Knowledge Base Agent Skills

A collection of Agent Skills that pair with [Vercel Knowledge Base](https://vercel.com/kb) guides. Each guide explains how to do a task by hand. The matching skill lets an AI agent carry out that same task with the user, following the guide's steps and using applicable resources.

## Available skills

<!-- START:Available-Skills -->
| Skill | What it does | Companion guide | Download |
| --- | --- | --- | --- |
| [`astro-webflow-to-vercel`](./skills/astro-webflow-to-vercel) | Migrate an Astro app from Webflow Cloud to Vercel | [Read the guide](https://vercel.com/kb/guide/migrate-an-astro-app-from-webflow-cloud-to-vercel) | [`astro-webflow-to-vercel.skill`](https://raw.githubusercontent.com/vercel-labs/vercel-kb-skills/main/dist/astro-webflow-to-vercel.skill) |
| [`tanstack-start-cloudflare-to-vercel`](./skills/tanstack-start-cloudflare-to-vercel) | Migrate a TanStack Start app from Cloudflare Workers to Vercel | [Read the guide](https://vercel.com/kb/guide/migrate-a-tanstack-start-app-from-cloudflare-to-vercel) | [`tanstack-start-cloudflare-to-vercel.skill`](https://raw.githubusercontent.com/vercel-labs/vercel-kb-skills/main/dist/tanstack-start-cloudflare-to-vercel.skill) |
| [`tanstack-start-netlify-to-vercel`](./skills/tanstack-start-netlify-to-vercel) | Migrate a TanStack Start app from Netlify to Vercel | [Read the guide](https://vercel.com/kb/guide/migrate-a-tanstack-start-app-from-netlify-to-vercel) | [`tanstack-start-netlify-to-vercel.skill`](https://raw.githubusercontent.com/vercel-labs/vercel-kb-skills/main/dist/tanstack-start-netlify-to-vercel.skill) |
<!-- END:Available-Skills -->

## Using a skill

Each skill is published as a downloadable `.skill` archive (a ZIP of the skill's files) under [`dist/`](./dist), linked from the **Download** column above.

### Upload to Claude.ai

The `.skill` file is a ZIP archive you can upload to Claude directly.

1. Download the `.skill` file from the **Download** column above.
2. Make sure **Code execution and file creation** is enabled in [Settings → Capabilities](https://claude.ai/settings/capabilities).
3. Go to [Customize → Skills](https://claude.ai/customize/skills).
4. Click the "+" button, then **+ Create skill**.
5. Select **Upload a skill**.
6. Upload the `.skill` file.
7. Toggle the skill on.

### Add via the `skills` CLI

For Cursor, OpenAI Codex, Claude Code, and other agents, use the [`skills` CLI](https://www.skills.sh/docs/cli) to install a skill straight from this repo:

```bash
# Install a specific skill
npx skills add vercel-labs/vercel-kb-skills --skill tanstack-start-cloudflare-to-vercel

# Install all skills
npx skills add vercel-labs/vercel-kb-skills
```

Replace the `--skill` value with any skill name from the table above. You can also browse a skill's source directly under [`skills/`](./skills).

## Recommended: the Vercel Plugin

When using these skills with a coding agent, we strongly recommend also installing the [Vercel Plugin](https://vercel.com/docs/agent-resources/vercel-plugin). It gives supported agents (Claude Code, Cursor, and more) Vercel-specific context and expert guidance: a relational knowledge graph of the Vercel ecosystem, 25+ deep-dive product skills, specialist agents, and slash commands. So the agent has accurate, up-to-date Vercel knowledge to draw on while it works.

```bash
npx plugins add vercel/vercel-plugin
```

The skills in this repo are designed to pair with the plugin: they drive the order of work for a given guide, and defer to the plugin's skills for current, detailed product guidance.

## Contributing

When you add or edit a skill under `skills/`, regenerate the packaged archives and the table above before committing:

```bash
node scripts/sync-skills.js
# or: npm run sync
```

This rebuilds `dist/*.skill` and the **Available skills** table. Commit those changes as part of your pull request, CI verifies they're in sync and fails the check if they're missing or stale. Don't edit `dist/` or the generated table by hand.

## License

[Apache-2.0](./LICENSE).
