#!/usr/bin/env bash
# 一键启动 anvil、部署合约，最后把 anvil 留在前台（Ctrl+C 关闭）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT_DIR="$ROOT_DIR/contract"

# 默认参数（直接改这里即可，无需每次传参）
RPC_URL="http://127.0.0.1:8545"
CHAIN_ID="31337"
PORT="8545"
LOG_FILE="$ROOT_DIR/output/logs/anvil.log"

# anvil 默认私钥（账户 #0）
PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
# 前端用于本地签名的测试私钥（使用助记词索引 #1）
TEST_PRIVATE_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

# 部署脚本参数
USE_MOCK_PYTH="true"
MOCK_PRICE="2000"
MOCK_EXPO="0"

# Generate a random deployer key to avoid nonce collisions
PRIVATE_KEY=$(cast wallet new | grep -i "Private Key" | awk '{print $3}')
echo "Generated ephemeral deployer key: $PRIVATE_KEY"

# Kill any existing anvil processes using port 8545 to ensure clean slate
lsof -ti:8545 | xargs kill -9 >/dev/null 2>&1 || true
pkill -f "anvil --" >/dev/null 2>&1 || true
sleep 2

echo "启动 anvil (chain-id=$CHAIN_ID, port=$PORT)..."
# Reset log file
echo "Starting Anvil..." > "$LOG_FILE"
anvil --host 0.0.0.0 --chain-id "$CHAIN_ID" --port "$PORT" --block-time 1 >>"$LOG_FILE" 2>&1 &
ANVIL_PID=$!
echo "anvil PID: $ANVIL_PID (日志: $LOG_FILE)"

cleanup() {
  if ps -p "$ANVIL_PID" >/dev/null 2>&1; then
    echo "停止 anvil ($ANVIL_PID)..."
    kill "$ANVIL_PID"
  fi
}
trap cleanup EXIT

echo "等待 anvil 就绪..."
for _ in {1..30}; do
  if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
    break
  fi
  
  # Check if process is still alive
  if ! ps -p "$ANVIL_PID" >/dev/null 2>&1; then
    echo "Anvil process died unexpectedly!"
    echo "Last 20 lines of log:"
    tail -n 20 "$LOG_FILE"
    exit 1
  fi
  sleep 0.3
done

# Final check
if ! cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
    echo "Anvil failed to become ready."
    echo "Last 20 lines of log:"
    tail -n 20 "$LOG_FILE"
    exit 1
fi

echo "Funding ephemeral deployer key..."
ADDRESS=$(cast wallet address --private-key "$PRIVATE_KEY")
# Use Account #2 for funding to avoid potential conflicts with Account #0
FUNDING_KEY="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
cast send "$ADDRESS" --value 10ether --private-key "$FUNDING_KEY" --rpc-url "$RPC_URL" --gas-price 20000000000 >/dev/null

echo "开始部署 (USE_MOCK_PYTH=$USE_MOCK_PYTH, MOCK_PRICE=$MOCK_PRICE, MOCK_EXPO=$MOCK_EXPO)..."
cd "$CONTRACT_DIR"
rm -rf broadcast/ cache/
forge clean
USE_MOCK_PYTH="$USE_MOCK_PYTH" MOCK_PRICE="$MOCK_PRICE" MOCK_EXPO="$MOCK_EXPO" PRIVATE_KEY="$PRIVATE_KEY" \
forge script script/DeployExchange.s.sol:DeployExchangeScript --broadcast --rpc-url "$RPC_URL" --legacy --slow || exit 1

if command -v jq >/dev/null 2>&1; then
  BROADCAST_FILE="$CONTRACT_DIR/broadcast/DeployExchange.s.sol/$CHAIN_ID/run-latest.json"
  if [[ -f "$BROADCAST_FILE" ]]; then
    EXCHANGE_ADDR=$(jq -r '.transactions[] | select(.contractName=="MonadPerpExchange") | .contractAddress' "$BROADCAST_FILE" | tail -n 1)
    BLOCK_HEX=$(jq -r --arg addr "$EXCHANGE_ADDR" '.receipts[] | select(.contractAddress==$addr) | .blockNumber' "$BROADCAST_FILE" | tail -n 1)
    if [[ "$BLOCK_HEX" =~ ^0x ]]; then
      BLOCK_DEC=$((BLOCK_HEX))
    else
      BLOCK_DEC="$BLOCK_HEX"
    fi
    cat > "$ROOT_DIR/frontend/.env.local" <<EOF
VITE_RPC_URL=$RPC_URL
VITE_CHAIN_ID=$CHAIN_ID
VITE_EXCHANGE_ADDRESS=$EXCHANGE_ADDR
VITE_EXCHANGE_DEPLOY_BLOCK=$BLOCK_DEC
VITE_TEST_PRIVATE_KEY=$TEST_PRIVATE_KEY
EOF
    echo "已写入 frontend/.env.local (exchange=$EXCHANGE_ADDR, deploy_block=$BLOCK_DEC)"
    
    # Grant OPERATOR_ROLE to Alice (0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266) for seeding
    echo "Granting ROLES to Alice..."
    cast send "$EXCHANGE_ADDR" "setOperator(address)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" >/dev/null
    # Grant DEFAULT_ADMIN_ROLE (0x00) to Alice so user can manage params easily
    cast send "$EXCHANGE_ADDR" "grantRole(bytes32,address)" "0x0000000000000000000000000000000000000000000000000000000000000000" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" >/dev/null

    # Copy ABI JSON to frontend and convert to TS with 'as const'
    ABI_SOURCE="$CONTRACT_DIR/out/Exchange.sol/MonadPerpExchange.json"
    ABI_DEST_TS="$ROOT_DIR/frontend/onchain/ExchangeABI.ts"
    if [[ -f "$ABI_SOURCE" ]]; then
      # Extract only the 'abi' field from the JSON and wrap it in a TS export
      # Use printf to avoid extra newlines between ] and as const
      printf "export const EXCHANGE_ABI = %s as const;\n" "$(jq -c '.abi' "$ABI_SOURCE")" > "$ABI_DEST_TS"
      echo "已生成 ABI 到 frontend/onchain/ExchangeABI.ts"
    fi
    
    # Update Indexer config.yaml
    INDEXER_CONFIG="$ROOT_DIR/indexer/config.yaml"
    if [[ -f "$INDEXER_CONFIG" ]]; then
      # Use sed to replace the address (assuming standard formatting)
      # We look for the line with the address and replace it
      # Note: This is a simple replacement, assuming the file structure doesn't change drastically
      sed -i  "s/0x[a-fA-F0-9]\{40\}/$EXCHANGE_ADDR/" "$INDEXER_CONFIG"
      echo "已更新 indexer/config.yaml (exchange=$EXCHANGE_ADDR)"
    else
      echo "未找到 indexer/config.yaml，跳过更新"
    fi
  else
    echo "未找到广播文件 $BROADCAST_FILE，跳过前端 env 写入"
  fi
else
  echo "未安装 jq，跳过自动写入 frontend/.env.local"
fi

echo "部署完成。anvil 继续运行，按 Ctrl+C 退出。"
wait "$ANVIL_PID"
