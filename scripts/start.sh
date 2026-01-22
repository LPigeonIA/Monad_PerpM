#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "   Monad Exchange: Start Services"
echo "=================================================="

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROCESS_DIR="$ROOT_DIR/output/process"

# 1. Cleanup
"$ROOT_DIR/scripts/stop.sh"

# Create process directory
mkdir -p "$PROCESS_DIR"

# 2. Start Anvil & Deploy
echo "[2/3] Starting Anvil and Deploying Contracts..."
"$ROOT_DIR/scripts/run-anvil-deploy.sh" > "$ROOT_DIR/output/logs/deploy.log" 2>&1 &
ANVIL_PID=$!
echo "$ANVIL_PID" > "$PROCESS_DIR/anvil.pid"

# Wait for deployment to finish (check for .env.local update)
echo "Waiting for deployment..."
rm -f "$ROOT_DIR/frontend/.env.local"
for i in {1..30}; do
    if ! ps -p "$ANVIL_PID" > /dev/null; then
        echo "Error: Anvil/Deploy process died unexpectedly."
        cat "$ROOT_DIR/output/logs/deploy.log"
        exit 1
    fi
    if [ -f "$ROOT_DIR/frontend/.env.local" ]; then
        echo "Deployment detected."
        break
    fi
    sleep 1
done
sleep 5 # Extra buffer for Anvil RPC to be fully responsive

# 3. Start Indexer
echo "[3/3] Starting Indexer..."
cd "$ROOT_DIR/indexer"

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "Installing Indexer dependencies..."
    npm install
fi

# Generate code (creates docker-compose.yaml)
echo "Generating indexer code..."
npm run codegen

# Start Docker services
# Clean up old data to ensure fresh state for Anvil reset
if [ -f "generated/docker-compose.yaml" ]; then
    docker compose -f generated/docker-compose.yaml down -v
    docker compose -f generated/docker-compose.yaml up -d
else
    echo "Error: docker-compose.yaml not generated."
    exit 1
fi

echo "Waiting for Postgres to initialize..."
sleep 5

# Start Envio indexer in background
echo "Starting Envio Indexer..."
TUI_OFF=true HASURA_CONSOLE_ENABLED=false BROWSER=none npm run dev > "$ROOT_DIR/output/logs/indexer.log" 2>&1 &
INDEXER_PID=$!
echo "$INDEXER_PID" > "$PROCESS_DIR/indexer.pid"
cd "$ROOT_DIR"

# 4. Start Frontend
echo "[4/5] Starting Frontend..."
"$ROOT_DIR/scripts/start-frontend.sh" > "$ROOT_DIR/output/logs/frontend.log" 2>&1 &
FRONTEND_PID=$!
echo "$FRONTEND_PID" > "$PROCESS_DIR/frontend.pid"

# 5. Start Keeper
echo "[5/5] Starting Keeper..."
"$ROOT_DIR/keeper/start-keeper.sh" > "$ROOT_DIR/output/logs/keeper.log" 2>&1 &
KEEPER_PID=$!
echo "$KEEPER_PID" > "$PROCESS_DIR/keeper.pid"

echo "Services started. PIDs saved in $PROCESS_DIR"
