#!/usr/bin/env bash
# Audit a TanStack Start project for Netlify usage before moving to Vercel.
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
EXCLUDES=(--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=.output --exclude-dir=.vercel --exclude-dir=.netlify)

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

# --- Netlify config (Step 2) ---
section "Netlify configuration (Step 2)"
NETLIFY_CFG=0
for f in netlify.toml _redirects _headers; do
  if [[ -f "$ROOT/$f" ]]; then found "$f -> delete or recreate as Nitro route rules / vercel.json"; NETLIFY_CFG=1; fi
done
[[ "$NETLIFY_CFG" -eq 0 ]] && absent "no netlify.toml, _redirects, or _headers found"

if grep -rqs "publish" "$ROOT/netlify.toml" 2>/dev/null; then
  found "publish setting in netlify.toml -> remove (Vercel auto-detects output via Nitro)"
fi

# --- Netlify Vite plugin / target (Step 1) ---
section "Vite plugin and Netlify target (Step 1)"
if grep -rqs "@netlify/vite-plugin-tanstack-start\|netlify()" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
  found "Netlify Vite plugin referenced -> replace with nitro() from 'nitro/vite'"
  grep -rns "@netlify/vite-plugin-tanstack-start\|netlify()" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null | sed 's/^/    /'
else
  absent "no Netlify Vite plugin reference found"
fi
if grep -rqs "target:[[:space:]]*['\"]netlify['\"]\|preset:[[:space:]]*['\"]netlify['\"]" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
  found "older Netlify target/preset set (target: 'netlify' or preset: 'netlify') -> remove so Nitro applies the vercel preset"
  grep -rns "target:[[:space:]]*['\"]netlify['\"]\|preset:[[:space:]]*['\"]netlify['\"]" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null | sed 's/^/    /'
fi

# --- @netlify/ imports (Step 4) ---
section "Netlify platform imports (Step 4)"
if grep -rqs "@netlify/" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
  found "'@netlify/' imports. Every one must be removed or replaced:"
  grep -rns "@netlify/" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null | sed 's/^/    /'
else
  absent "no '@netlify/' imports found"
fi

# --- Platform feature heuristics (Step 4) ---
section "Netlify features in use (Step 4, see references/service-mapping.md)"
detect() { # $1 = label, rest = patterns
  local label="$1"; shift
  local pat; pat="$(printf '%s\\|' "$@")"; pat="${pat%\\|}"
  if grep -rqsE "$pat" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
    found "$label"
  fi
}
detect "Netlify Blobs -> Vercel Blob (files) or Redis/Edge Config (key/value)" "@netlify/blobs|getStore\("
detect "Netlify DB (Postgres via Neon) -> Postgres on the Marketplace"          "@netlify/neon|netlify\.toml.*\[db\]|NETLIFY_DATABASE_URL"
detect "Netlify Functions -> Vercel Functions"                                  "@netlify/functions"
detect "Netlify Edge Functions -> Vercel Functions / Routing Middleware"        "@netlify/edge-functions"
detect "Netlify Image CDN -> Vercel Image Optimization"                          "/\.netlify/images"
echo "  (feature detection is heuristic; confirm against the actual code)"

# --- Scheduled & Background Functions (Step 6) ---
section "Scheduled and background work (Step 6)"
if grep -rqsE "schedule[[:space:]]*[:=]|\[\[scheduled" "$ROOT/netlify.toml" 2>/dev/null \
   || grep -rqs "schedule" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
  found "Scheduled Functions likely present -> map to Nitro scheduledTasks (Vercel Cron Jobs)"
else
  absent "no obvious Scheduled Functions"
fi
# Netlify background functions use a "*-background" filename suffix; async
# workloads import the @netlify/async-workloads package.
if find "$ROOT" \( -name node_modules -o -name .git -o -name .netlify -o -name .vercel \) -prune -o \
     -type f \( -name '*-background.ts' -o -name '*-background.js' -o -name '*-background.mjs' \) -print 2>/dev/null | grep -q . \
   || grep -rqs "@netlify/async-workloads" "$ROOT" "${SRC_GLOBS[@]}" "${EXCLUDES[@]}" 2>/dev/null; then
  found "Background Functions or Async Workloads likely present -> map to Vercel Queues"
else
  absent "no obvious Background Functions or Async Workloads"
fi

# --- Standalone function directories (Step 2 / 6) ---
section "Netlify function directories (Step 2 / 6)"
FN_DIRS=0
for d in netlify/functions netlify/edge-functions; do
  if [[ -d "$ROOT/$d" ]]; then found "$d -> move handlers to routes/api/ or map to the Vercel equivalent"; FN_DIRS=1; fi
done
[[ "$FN_DIRS" -eq 0 ]] && absent "no netlify/functions or netlify/edge-functions directory"

# --- Build scripts (Step 3) ---
section "Build scripts (Step 3)"
if grep -qs "netlify deploy\|netlify dev\|netlify build" "$ROOT/package.json" 2>/dev/null; then
  found "netlify scripts in package.json -> replace with vite dev/build"
else
  absent "no netlify scripts in package.json"
fi

section "Summary"
echo "Work through SKILL.md steps 1 to 7 in order. Skip the parts of steps 4 and"
echo "6 marked [ok] above. Read references/service-mapping.md before editing any"
echo "Netlify Blobs or storage code, and use the links in SKILL.md for the"
echo "dashboard steps."
