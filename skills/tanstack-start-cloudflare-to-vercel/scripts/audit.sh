#!/usr/bin/env bash
# Audit a TanStack Start project for Cloudflare usage before moving to Vercel.
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
SRC_GLOBS=(--include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.mjs")
EXCLUDES=(--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=.output --exclude-dir=.vercel)

section() { printf '\n=== %s ===\n' "$1"; }
found()   { printf '  [FOUND] %s\n' "$1"; }
absent()  { printf '  [ok]    %s\n' "$1"; }

echo "TanStack Start -> Vercel migration audit"
echo "Project: $ROOT"

# --- Confirm it is TanStack Start ---
section "Framework check"
if grep -rqs "@tanstack/react-start" "$ROOT/package.json" 2>/dev/null; then
  found "@tanstack/react-start in package.json (TanStack Start confirmed)"
else
  found "Could NOT confirm @tanstack/react-start in package.json. Verify this is a TanStack Start app before proceeding"
fi

# --- Wrangler config ---
section "Wrangler configuration (Step 2)"
WRANGLER_HITS=0
for f in wrangler.jsonc wrangler.toml wrangler.json; do
  if [[ -f "$ROOT/$f" ]]; then found "$f -> delete this"; WRANGLER_HITS=1; fi
done
[[ "$WRANGLER_HITS" -eq 0 ]] && absent "no wrangler config file found"

if grep -rqs "compatibility_date\|compatibility_flags\|nodejs_compat" "$ROOT"/wrangler.* 2>/dev/null; then
  found "compatibility_date or flags present -> remove (no Vercel equivalent)"
fi

# --- Cloudflare Vite plugin (Step 1) ---
section "Vite plugin (Step 1)"
if grep -rqs "@cloudflare/vite-plugin\|cloudflare()" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
  found "Cloudflare Vite plugin referenced -> replace with nitro() from 'nitro/vite'"
  grep -rns "@cloudflare/vite-plugin\|cloudflare()" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null | sed 's/^/    /'
else
  absent "no Cloudflare Vite plugin reference found"
fi

# --- cloudflare:workers imports (Step 4) ---
section "Cloudflare bindings imports (Step 4)"
if grep -rqs "cloudflare:workers" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
  found "'cloudflare:workers' imports. Every one must be removed or replaced:"
  grep -rns "cloudflare:workers" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null | sed 's/^/    /'
else
  absent "no 'cloudflare:workers' imports found"
fi

# --- Binding type heuristics (Step 4) ---
section "Binding types in use (Step 4, see reference/service-mapping.md)"
detect() { # $1 = label, rest = patterns
  local label="$1"; shift
  local pat; pat="$(printf '%s\\|' "$@")"; pat="${pat%\\|}"
  if grep -rqsE "$pat" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" "$ROOT"/wrangler.* 2>/dev/null; then
    found "$label"
  fi
}
detect "R2 object storage -> Vercel Blob"             "\.put\(|\.get\(.*[Bb]ucket|r2_buckets|R2Bucket"
detect "Workers KV -> Redis or Edge Config"           "kv_namespaces|KVNamespace|\.MY_KV|env\.[A-Z_]*KV"
detect "D1 SQL -> Postgres"                            "d1_databases|D1Database|\.prepare\("
detect "Durable Objects -> database or Redis (refactor)" "durable_objects|DurableObject"
detect "Workers AI (env.AI) -> AI Gateway with AI SDK" "env\.AI|ai_binding|\[ai\]"
echo "  (binding detection is heuristic; confirm against the actual code)"

# --- Cron & Queues (Step 6) ---
section "Scheduled tasks and queues (Step 6)"
if grep -rqs "crons\|triggers" "$ROOT"/wrangler.* 2>/dev/null; then
  found "Cron Triggers likely configured in wrangler -> map to Nitro scheduledTasks"
else
  absent "no obvious Cron Triggers in wrangler config"
fi
if grep -rqs "queues\|queue_consumers\|queue_producers" "$ROOT"/wrangler.* 2>/dev/null; then
  found "Queues configured in wrangler -> map to Vercel Queues"
else
  absent "no obvious Queues in wrangler config"
fi

# --- Build scripts (Step 3) ---
section "Build scripts (Step 3)"
if grep -qs "wrangler deploy\|cf-typegen" "$ROOT/package.json" 2>/dev/null; then
  found "wrangler or cf-typegen scripts in package.json -> replace with vite dev/build"
else
  absent "no wrangler scripts in package.json"
fi

section "Summary"
echo "Work through SKILL.md steps 1 to 7 in order. Skip the parts of steps 4 and"
echo "6 marked [ok] above. Read reference/service-mapping.md before editing any"
echo "binding code, and use the links in SKILL.md for the dashboard steps."