#!/usr/bin/env bash
# 根据最新 broadcast 写入前端 .env.local，然后启动 Vite 开发服务器。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT_DIR="$ROOT_DIR/contract"
FRONT_DIR="$ROOT_DIR/frontend"
BROADCAST_FILE="$CONTRACT_DIR/broadcast/DeployExchange.s.sol/31337/run-latest.json"
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
CHAIN_ID="${CHAIN_ID:-31337}"

if ! command -v jq >/dev/null 2>&1; then
  echo "需要 jq 来解析广播文件，请先安装 jq" >&2
  exit 1
fi

if [[ ! -f "$BROADCAST_FILE" ]]; then
  echo "未找到 $BROADCAST_FILE，请先运行 ./run-anvil-deploy.sh" >&2
  exit 1
fi

EXCHANGE_ADDR=$(jq -r '.transactions[] | select(.contractName=="MonadPerpExchange") | .contractAddress' "$BROADCAST_FILE" | tail -n 1)
PYTH_ADDR=$(jq -r '.transactions[] | select(.contractName=="MockPyth") | .contractAddress' "$BROADCAST_FILE" | tail -n 1)
BLOCK_HEX=$(jq -r --arg addr "$EXCHANGE_ADDR" '.receipts[] | select(.contractAddress==$addr) | .blockNumber' "$BROADCAST_FILE" | tail -n 1)
if [[ "$BLOCK_HEX" =~ ^0x ]]; then
  BLOCK_DEC=$((BLOCK_HEX))
else
  BLOCK_DEC="$BLOCK_HEX"
fi

cat > "$FRONT_DIR/.env.local" <<EOF
VITE_RPC_URL=$RPC_URL
VITE_CHAIN_ID=$CHAIN_ID
VITE_EXCHANGE_ADDRESS=$EXCHANGE_ADDR
VITE_EXCHANGE_DEPLOY_BLOCK=$BLOCK_DEC
EOF

echo "已写入 $FRONT_DIR/.env.local"
echo "Exchange: $EXCHANGE_ADDR"
echo "Pyth/MockPyth: $PYTH_ADDR"
echo "Deploy block: $BLOCK_DEC"

cd "$FRONT_DIR"
if [[ ! -d node_modules ]]; then
  echo "安装前端依赖..."
  npm install --no-fund --no-audit
fi

echo "启动前端 (Vite)..."
rm -rf node_modules/.vite
exec npm run dev -- --host --port 3000
