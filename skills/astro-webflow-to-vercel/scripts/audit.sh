#!/usr/bin/env bash
# Audit an Astro project for Webflow Cloud usage before moving to Vercel.
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

# Search source files only; skip dependency and VCS dirs.
SRC_GLOBS=(--include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.mjs" --include="*.astro")
EXCLUDES=(--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=.output --exclude-dir=.vercel --exclude-dir=.astro --exclude-dir=.wrangler)

section() { printf '\n=== %s ===\n' "$1"; }
found()   { printf '  [FOUND] %s\n' "$1"; }
absent()  { printf '  [ok]    %s\n' "$1"; }

echo "Astro (Webflow Cloud) -> Vercel migration audit"
echo "Project: $ROOT"

# --- Confirm it is Astro ---
section "Framework check"
if grep -rqs "\"astro\"" "$ROOT/package.json" 2>/dev/null; then
  found "astro in package.json (Astro confirmed)"
else
  found "Could NOT confirm astro in package.json. Verify this is an Astro app before proceeding"
fi

# --- Webflow Cloud & Wrangler config (Step 2) ---
section "Webflow Cloud configuration (Step 2)"
CFG_HITS=0
for f in webflow.json wrangler.json wrangler.jsonc wrangler.toml worker-configuration.d.ts; do
  if [[ -f "$ROOT/$f" ]]; then found "$f -> delete this"; CFG_HITS=1; fi
done
[[ "$CFG_HITS" -eq 0 ]] && absent "no webflow.json, wrangler config, or worker-configuration.d.ts found"

if grep -rqs "compatibility_date\|compatibility_flags\|nodejs_compat" "$ROOT"/wrangler.* 2>/dev/null; then
  found "compatibility_date or flags in wrangler config -> remove (no Vercel equivalent)"
fi

# --- Cloudflare adapter (Step 1) ---
section "Astro adapter (Step 1)"
if grep -rqs "@astrojs/cloudflare" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" "$ROOT/package.json" 2>/dev/null; then
  found "@astrojs/cloudflare referenced -> replace with @astrojs/vercel"
  grep -rns "@astrojs/cloudflare" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null | sed 's/^/    /'
else
  absent "no @astrojs/cloudflare reference found"
fi
if grep -rqs "platformProxy" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
  found "platformProxy adapter option -> remove (Workers-only local dev setting)"
fi
if grep -rqs "react-dom/server.edge" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
  found "react-dom/server.edge Vite alias -> remove (not needed on Node.js)"
fi

# --- Base path / mount path (Step 3) ---
section "Base path and asset prefix (Step 3)"
if grep -rqsE "assetsPrefix|^[[:space:]]*base[[:space:]]*:" "$ROOT"/astro.config.* 2>/dev/null; then
  found "base or build.assetsPrefix in astro.config -> remove when serving from the root"
  grep -rnsE "assetsPrefix|^[[:space:]]*base[[:space:]]*:" "$ROOT"/astro.config.* 2>/dev/null | sed 's/^/    /'
else
  absent "no base or assetsPrefix in astro.config"
fi
if grep -rqs "import.meta.env.BASE_URL\|import.meta.env.ASSETS_PREFIX" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
  found "manual base-path prefixing (import.meta.env.BASE_URL / ASSETS_PREFIX) -> remove from fetch calls, <img> tags, favicon link"
  grep -rns "import.meta.env.BASE_URL\|import.meta.env.ASSETS_PREFIX" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null | sed 's/^/    /'
fi

# --- Edge runtime directives (Step 3) ---
section "Edge runtime directives (Step 3)"
if grep -rqsE "runtime:[[:space:]]*['\"]edge['\"]" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
  found "runtime: 'edge' on routes -> remove to run on Node.js"
  grep -rnsE "runtime:[[:space:]]*['\"]edge['\"]" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null | sed 's/^/    /'
else
  absent "no runtime: 'edge' directives found"
fi

# --- Storage binding access (Step 5) ---
# Webflow Cloud apps reach bindings through Astro's locals: `locals.runtime.env`,
# `Astro.locals.runtime.env`, or a cast such as `(locals as any).runtime`. Match
# the dotted form and the cast so the destructuring pattern isn't missed.
section "Storage binding access (Step 5)"
if grep -rqsE "locals\.runtime|locals as" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
  found "locals.runtime / Astro.locals.runtime / (locals as any).runtime access. Each one reads a Cloudflare binding and must be replaced:"
  grep -rnsE "locals\.runtime|locals as" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null | sed 's/^/    /'
else
  absent "no locals.runtime access found"
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
section "Local environment variables (Step 6)"
if [[ -f "$ROOT/dev.vars" ]]; then
  found "dev.vars -> delete (Astro loads .env; pull values with vercel env pull)"
else
  absent "no dev.vars file found"
fi

# --- Build scripts (Step 4) ---
section "Build scripts (Step 4)"
if grep -qs "webflow cloud\|wrangler" "$ROOT/package.json" 2>/dev/null; then
  found "webflow cloud or wrangler scripts in package.json -> replace with astro dev/build/preview"
else
  absent "no Webflow Cloud or wrangler scripts in package.json"
fi

section "Summary"
echo "Work through SKILL.md steps 1 to 7 in order. Skip the parts marked [ok]"
echo "above. Read references/service-mapping.md before editing any binding code,"
echo "and use the links in SKILL.md for the dashboard steps."
