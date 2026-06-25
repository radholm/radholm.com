#!/usr/bin/env bash
# Run Lighthouse on the local site: prints scores in the terminal and opens the HTML report.
# Usage: ./lighthouse.sh [port]
set -euo pipefail

PORT="${1:-8080}"
URL="http://localhost:${PORT}"
SITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/radholm" && pwd)"
OUT_DIR="$(mktemp -d)"
OUT_BASE="${OUT_DIR}/report"
HTML="${OUT_BASE}.report.html"
JSON="${OUT_BASE}.report.json"
EDGE="/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"

# Pick a Chromium browser for Lighthouse.
if [ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]; then
  export CHROME_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
elif [ -x "$EDGE" ]; then
  export CHROME_PATH="$EDGE"
else
  echo "No Chrome or Edge found. Install one." >&2
  exit 1
fi

# Start a static server if the port is free; remember if we own it so we can stop it.
STARTED_SERVER=0
if ! curl -s -o /dev/null "$URL"; then
  ( cd "$SITE_DIR" && python3 -m http.server "$PORT" >/dev/null 2>&1 ) &
  SERVER_PID=$!
  STARTED_SERVER=1
  for _ in $(seq 1 20); do
    curl -s -o /dev/null "$URL" && break
    sleep 0.25
  done
fi

cleanup() {
  [ "$STARTED_SERVER" -eq 1 ] && kill "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "Running Lighthouse on ${URL} ..."
npx --yes lighthouse "$URL" \
  --quiet --chrome-flags="--headless=new" \
  --output html --output json --output-path "$OUT_BASE" \
  --only-categories=performance,accessibility,best-practices,seo

# Print scores + any failing audits in the terminal.
node -e '
const r = require(process.argv[1]);
const color = (s) => s >= 90 ? "\x1b[32m" : s >= 50 ? "\x1b[33m" : "\x1b[31m";
const R = "\x1b[0m";
console.log("\n  Lighthouse  " + r.finalDisplayedUrl + "\n");
for (const c of Object.values(r.categories)) {
  const s = Math.round(c.score * 100);
  console.log("  " + color(s) + String(s).padStart(3) + R + "  " + c.title);
}
const fails = Object.values(r.audits)
  .filter(a => a.score !== null && a.score < 1 && a.scoreDisplayMode === "binary");
if (fails.length) {
  console.log("\n  Issues:");
  for (const a of fails) console.log("   \x1b[33m•\x1b[0m " + a.title);
}
console.log("");
' "$JSON"

# Open the full HTML report in the default browser.
open "$HTML"
echo "Report: ${HTML}"
