#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "   Monad Exchange: Quickstart (Start + Seed)"
echo "=================================================="

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Start Services
"$ROOT_DIR/scripts/start.sh"

# 2. Wait for Indexer Readiness
echo "Waiting for Indexer to be ready..."
sleep 30 # Give Indexer time to initialize and sync

# 3. Seed Data
"$ROOT_DIR/scripts/seed.sh"

echo "=================================================="
echo "   Quickstart Complete!"
echo "   Frontend: http://localhost:3000"
echo "=================================================="
