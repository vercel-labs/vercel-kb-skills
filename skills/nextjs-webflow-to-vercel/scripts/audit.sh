#!/usr/bin/env bash
# Audit a Next.js project for Webflow Cloud usage before moving to Vercel.
# Usage: bash scripts/audit.sh [project_path]   (defaults to current directory)
#
# Output is a plain checklist of what needs moving. It is deliberately
# conservative: it reports what it finds and lets the agent decide.

set -uo pipefail

ROOT="${1:-.}"
if [[ ! -d "$ROOT" ]]; then
  echo "Error: '$ROOT' is not a directory." >&2
  exit 1
fi

# Search source files only; skip dependency, build, and VCS dirs.
SRC_GLOBS=(--include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.mjs")
EXCLUDES=(--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=.next --exclude-dir=.open-next --exclude-dir=.vercel --exclude-dir=.wrangler)

section() { printf '\n=== %s ===\n' "$1"; }
found()   { printf '  [FOUND] %s\n' "$1"; }
absent()  { printf '  [ok]    %s\n' "$1"; }

echo "Next.js (Webflow Cloud) -> Vercel migration audit"
echo "Project: $ROOT"

# --- Confirm it is Next.js ---
section "Framework check"
if grep -rqs "\"next\"" "$ROOT/package.json" 2>/dev/null; then
  found "next in package.json (Next.js confirmed)"
else
  found "Could NOT confirm next in package.json. Verify this is a Next.js app before proceeding"
fi

# --- Webflow Cloud & Wrangler config (Step 2) ---
section "Webflow Cloud configuration (Step 2)"
CFG_HITS=0
for f in webflow.json wrangler.json wrangler.jsonc wrangler.toml open-next.config.ts open-next.config.js open-next.config.mjs cloudflare-env.d.ts cloudflare.env.ts; do
  if [[ -f "$ROOT/$f" ]]; then found "$f -> delete this"; CFG_HITS=1; fi
done
[[ "$CFG_HITS" -eq 0 ]] && absent "no webflow.json, wrangler config, open-next config, or cloudflare-env types found"

if grep -rqs "compatibility_date\|compatibility_flags\|nodejs_compat" "$ROOT"/wrangler.* 2>/dev/null; then
  found "compatibility_date or flags in wrangler config -> remove (no Vercel equivalent)"
fi

# --- OpenNext Cloudflare adapter (Step 1) ---
section "OpenNext Cloudflare adapter (Step 1)"
if grep -rqs "@opennextjs/cloudflare" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" "$ROOT/package.json" 2>/dev/null; then
  found "@opennextjs/cloudflare referenced -> remove (Next.js runs natively on Vercel, no adapter)"
  grep -rns "@opennextjs/cloudflare" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null | sed 's/^/    /'
else
  absent "no @opennextjs/cloudflare reference found"
fi
if grep -rqs "initOpenNextCloudflareForDev" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
  found "initOpenNextCloudflareForDev() dev hook -> remove from next.config (Workers-only local dev setting)"
fi

# --- Base path / mount path (Step 3) ---
section "Base path and asset prefix (Step 3)"
if grep -rqsE "assetPrefix|basePath" "$ROOT"/next.config.* 2>/dev/null; then
  found "basePath or assetPrefix in next.config -> remove when serving from the root"
  grep -rnsE "assetPrefix|basePath" "$ROOT"/next.config.* 2>/dev/null | sed 's/^/    /'
else
  absent "no basePath or assetPrefix in next.config"
fi
# Manual prefixing has no canonical token in Next.js (it's ad-hoc basePath vars in
# fetch()/<img>), so this is heuristic: it flags candidate references to review by hand.
if grep -rqsE "basePath|assetPrefix" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
  found "possible manual base-path prefixing (basePath / assetPrefix in source) -> review fetch calls and <img> tags by hand; remove the prefix (heuristic, confirm each)"
  grep -rnsE "basePath|assetPrefix" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null | sed 's/^/    /'
fi

# --- Edge runtime directives (Step 3) ---
# Next.js routes and middleware opt into the Edge runtime with
# `export const runtime = 'edge'`. Match the assignment form (and a colon form
# just in case) so middleware.ts isn't missed.
section "Edge runtime directives (Step 3)"
if grep -rqsE "runtime[[:space:]]*[:=][[:space:]]*['\"]edge['\"]" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
  found "runtime = 'edge' on routes or middleware -> remove to run on Node.js"
  grep -rnsE "runtime[[:space:]]*[:=][[:space:]]*['\"]edge['\"]" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null | sed 's/^/    /'
else
  absent "no runtime = 'edge' directives found"
fi

# --- Storage binding access (Step 5) ---
# Webflow Cloud Next.js apps reach bindings through getCloudflareContext().env
# from @opennextjs/cloudflare. Each call reads a Cloudflare binding.
section "Storage binding access (Step 5)"
if grep -rqs "getCloudflareContext" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
  found "getCloudflareContext() access. Each one reads a Cloudflare binding and must be replaced:"
  grep -rns "getCloudflareContext" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null | sed 's/^/    /'
else
  absent "no getCloudflareContext access found"
fi

# --- Binding types declared in wrangler config (Step 5) ---
section "Storage bindings in wrangler config (Step 5, see references/service-mapping.md)"
detect() { # $1 = label, rest = patterns
  local label="$1"; shift
  local pat; pat="$(printf '%s\\|' "$@")"; pat="${pat%\\|}"
  if grep -rqsE "$pat" "$ROOT"/wrangler.* 2>/dev/null; then
    found "$label"
  fi
}
detect "Object Storage (R2) -> Vercel Blob"                   "r2_buckets|R2Bucket"
detect "Key Value Store (Workers KV) -> Redis or Edge Config" "kv_namespaces|KVNamespace"
detect "SQLite (D1) -> Postgres"                              "d1_databases|D1Database"
echo "  (binding detection is heuristic; confirm against wrangler.json and the actual code)"

# --- Local env vars (Step 6) ---
# Optional: the create-cloudflare/OpenNext setup uses .dev.vars for local runtime
# variables. The guide doesn't require deleting it, but Next.js loads .env files,
# so it's safe to drop once values are pulled with vercel env pull.
section "Local environment variables (Step 6)"
if [[ -f "$ROOT/.dev.vars" ]]; then
  found ".dev.vars -> optional cleanup (Next.js loads .env; pull values with vercel env pull)"
else
  absent "no .dev.vars file found"
fi

# --- Build scripts (Step 4) ---
section "Build scripts (Step 4)"
if grep -qs "opennextjs-cloudflare\|wrangler\|webflow cloud" "$ROOT/package.json" 2>/dev/null; then
  found "opennextjs-cloudflare, wrangler, or webflow cloud scripts in package.json -> replace with next dev/build/start"
else
  absent "no Webflow Cloud, OpenNext, or wrangler scripts in package.json"
fi

section "Summary"
echo "Work through SKILL.md steps 1 to 7 in order. Skip the parts marked [ok]"
echo "above. Read references/service-mapping.md before editing any binding code,"
echo "and use the links in SKILL.md for the dashboard steps."
