#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROCESS_DIR="$ROOT_DIR/output/process"

echo "=================================================="
echo "   Monad Exchange: Stop Services"
echo "=================================================="

# Stop Envio indexer gracefully first
if [ -d "$ROOT_DIR/indexer" ]; then
    echo "Stopping Envio indexer..."
    cd "$ROOT_DIR/indexer"
    pnpm stop 2>/dev/null || true
    cd "$ROOT_DIR"
fi

if [ -d "$PROCESS_DIR" ]; then
    for pid_file in "$PROCESS_DIR"/*.pid; do
        if [ -f "$pid_file" ]; then
            PID=$(cat "$pid_file")
            NAME=$(basename "$pid_file" .pid)

            if ps -p "$PID" > /dev/null 2>&1; then
                echo "Stopping $NAME (PID: $PID)..."
                # Use SIGTERM to allow traps (like in run-anvil-deploy.sh) to run
                kill "$PID" || true

                # Wait a bit for it to exit
                for i in {1..5}; do
                    if ! ps -p "$PID" > /dev/null 2>&1; then
                        break
                    fi
                    sleep 0.5
                done

                # Force kill if still running
                if ps -p "$PID" > /dev/null 2>&1; then
                    echo "Force killing $NAME..."
                    kill -9 "$PID" || true
                fi
            else
                echo "$NAME (PID: $PID) is not running."
            fi
            rm "$pid_file"
        fi
    done
else
    echo "No process directory found."
fi

# Fallback: Port-based cleanup (Safe defaults)
# Only run if PIDs didn't catch everything or for extra safety
echo "Running port-based cleanup check..."
lsof -ti:8545 | xargs kill -9 2>/dev/null || true
lsof -ti:3000 | xargs kill -9 2>/dev/null || true
lsof -ti:9898 | xargs kill -9 2>/dev/null || true

echo "All services stopped."
