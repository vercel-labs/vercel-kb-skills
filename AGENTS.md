# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project overview

This repo contains **Agent Skills** that act as companions to [Vercel Knowledge Base](https://vercel.com/kb) guides. Each guide explains how to do a task by hand; the matching skill lets an agent carry out that same task following the guide's steps.

Layout:

- `skills/<skill-name>/SKILL.md` — the skill itself, plus any `references/` and `scripts/` it needs.
- `dist/<skill-name>.skill` — the packaged, downloadable skill (a deterministic ZIP of the skill folder's contents). **Generated — do not edit by hand.**
- `scripts/sync-skills.js` — packages skills into `dist/` and regenerates the README table.
- `README.md` — the "Available skills" table between the `<!-- START:Available-Skills -->` / `<!-- END:Available-Skills -->` markers is **generated — do not edit by hand.**
- `.github/workflows/verify-skills.yml` — read-only CI that fails if `dist/` or `README.md` are out of sync.

## Skill syncing (required)

Whenever you add, edit, rename, or delete anything under `skills/`, you **must** regenerate the packaged archives and the README table before committing:

```bash
node scripts/sync-skills.js
# or: npm run sync
```

Then commit the resulting changes to `dist/` and `README.md` **in the same pull request** as the skill change.

Notes:

- Output is deterministic — an unchanged skill always produces byte-for-byte identical output, so re-running is safe and won't create spurious diffs.
- To repackage only specific skills, pass their directory names: `node scripts/sync-skills.js <skill-name> ...`. With no arguments it rebuilds everything and prunes orphaned archives.
- CI (`verify-skills.yml`) runs the script and fails the check if `dist/` or `README.md` differ from what's committed. A PR with stale or missing generated files will not pass.
- Never hand-edit `dist/` or the generated README table; edit the skill source and re-run the script.

## Skill conventions

- Each skill lives in its own directory under `skills/` and must contain a `SKILL.md` with YAML frontmatter.
- The README table is built from each skill's frontmatter: `name`, `metadata.one-liner`, and `metadata.guide`. Keep those fields accurate and current.

## Pull request guidance

Keep PR descriptions lightweight:

- **Do not** include a "Summary" heading.
- **Do not** include a test plan section.
- Write a short, plain description of what changed and why. Avoid boilerplate and ceremony.
- If a PR changes **both** skills and general repo tooling/config, split the description into separate sections (for example `### Skills` and `### Repo`) so each set of changes is clear. If only one kind of change is present, no section headings are needed.
