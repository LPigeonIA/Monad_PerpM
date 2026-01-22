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
sleep 15 # Give Indexer time to initialize and sync

# 3. Seed Leaderboard Data
echo "Seeding Leaderboard Data..."
"$ROOT_DIR/scripts/seed_leaderboard.sh"

echo "=================================================="
echo "   Quickstart Complete!"
echo "   Frontend: http://localhost:3000"
echo "   Indexer GraphQL: http://localhost:8080"
echo "=================================================="
