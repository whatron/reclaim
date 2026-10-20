#!/bin/bash
# Creates a few real code projects on the build machine so the Projects page has something to show
# in screenshots. Two are made to look idle by backdating their source files.
set -uo pipefail
CODE="$HOME/Code"
mkdir -p "$CODE"

web() { # name, packages...
  local dir="$CODE/$1"; shift
  mkdir -p "$dir/src" && cd "$dir"
  npm init -y >/dev/null
  echo "export const hello = () => 'hi';" > src/index.ts
  npm install --silent --no-audit --no-fund "$@" >/dev/null 2>&1 || true
}
web storefront next react react-dom typescript @types/react eslint
web api-server express typescript zod @types/express vitest

mkdir -p "$CODE/scraper" && cd "$CODE/scraper"
printf "requests\npandas\n" > requirements.txt
echo "import requests" > main.py
python3 -m venv .venv && ./.venv/bin/pip install -q -r requirements.txt >/dev/null 2>&1 || true

cd "$CODE" && cargo new -q ledger 2>/dev/null && cd ledger \
  && cargo add -q serde serde_json >/dev/null 2>&1 && cargo build -q 2>/dev/null || true

# storefront and scraper haven't been touched since July.
for p in storefront scraper; do
  find "$CODE/$p" -maxdepth 1 -exec touch -h -t 202607140930 {} +
done
du -sh "$CODE"/*/node_modules "$CODE"/*/.venv "$CODE"/*/target 2>/dev/null || true
