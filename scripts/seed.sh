#!/usr/bin/env bash
set -e

RPC_URL="http://localhost:8545"
# Load address from frontend/.env
ENV_FILE="$(dirname "${BASH_SOURCE[0]}")/../frontend/.env.local"
if [ -f "$ENV_FILE" ]; then
    EXCHANGE=$(grep VITE_EXCHANGE_ADDRESS "$ENV_FILE" | cut -d '=' -f2)
    echo "Using Exchange Address: $EXCHANGE"
else
    echo "Error: frontend/.env.local not found. Cannot determine Exchange address."
    exit 1
fi
ALICE_PK="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
BOB_PK="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

echo "=================================================="
echo "   Monad Exchange: Seeding Data (via Cast)"
echo "=================================================="

check_tx() {
    if [ $? -ne 0 ]; then
        echo "❌ Transaction Failed!"
        exit 1
    fi
}

# Helper to place order
# placeOrder(bool isBuy, uint256 price, uint256 amount, uint256 hintId)
place_order() {
    local pk=$1
    local is_buy=$2
    local price=$3
    local amount=$4
    echo "  -> Placing Order: Buy=$is_buy Price=$price Amount=$amount"
    # Use --async to submit without waiting (less likely to conflict on nonce reading if slow)
    # But better: Use --resubmit to auto-replace if underpriced
    cast send --rpc-url $RPC_URL --private-key $pk $EXCHANGE "placeOrder(bool,uint256,uint256,uint256)" $is_buy $price $amount 0 --gas-price 20gwei
    sleep 1
    check_tx
}

echo "[1/4] Depositing Funds..."
echo "  -> Alice Deposit 500 ETH"
cast send --rpc-url $RPC_URL --private-key $ALICE_PK $EXCHANGE "deposit()" --value 500ether --gas-price 20gwei
check_tx

echo "  -> Bob Deposit 500 ETH"
cast send --rpc-url $RPC_URL --private-key $BOB_PK $EXCHANGE "deposit()" --value 500ether --gas-price 20gwei
check_tx

echo "[1.5/4] Setting Initial Index Price..."
cast send --rpc-url $RPC_URL --private-key $ALICE_PK $EXCHANGE "updateIndexPrice(uint256)" 1500ether --gas-price 20gwei
check_tx

echo "[2/4] Executing Trades (Generating Candles)..."

# Candle 1: 1500
echo "  - Trade @ 1500"
place_order $BOB_PK false 1500ether 0.01ether
place_order $ALICE_PK true 1500ether 0.01ether

echo "  - Time Travel (1 minute)..."
cast rpc --rpc-url $RPC_URL evm_increaseTime 60 > /dev/null
cast rpc --rpc-url $RPC_URL evm_mine > /dev/null

# Candle 2: 1520
echo "  - Trade @ 1520"
place_order $BOB_PK false 1520ether 0.02ether
place_order $ALICE_PK true 1520ether 0.02ether

echo "  - Time Travel (1 minute)..."
cast rpc --rpc-url $RPC_URL evm_increaseTime 60 > /dev/null
cast rpc --rpc-url $RPC_URL evm_mine > /dev/null

# Candle 3: 1490
echo "  - Trade @ 1490"
place_order $BOB_PK false 1490ether 0.015ether
place_order $ALICE_PK true 1490ether 0.015ether

echo "  - Time Travel (1 minute)..."
cast rpc --rpc-url $RPC_URL evm_increaseTime 60 > /dev/null
cast rpc --rpc-url $RPC_URL evm_mine > /dev/null

# Candle 4: 1550
echo "  - Trade @ 1550"
place_order $BOB_PK false 1550ether 0.03ether
place_order $ALICE_PK true 1550ether 0.03ether

echo "[3/4] Placing Open Orders..."
place_order $ALICE_PK true 1400ether 0.01ether
place_order $ALICE_PK true 1450ether 0.02ether
place_order $BOB_PK false 1600ether 0.015ether
place_order $BOB_PK false 1650ether 0.025ether

echo "[3.5/4] Creating Partial Fills..."
# Scenario 1: Alice Buy 0.01 @ 1580, Bob Sell 0.003 @ 1580 -> Alice has 0.007 remaining
place_order $ALICE_PK true 1580ether 0.01ether
place_order $BOB_PK false 1580ether 0.003ether

# Scenario 2: Bob Sell 0.02 @ 1620, Alice Buy 0.005 @ 1620 -> Bob has 0.015 remaining
place_order $BOB_PK false 1620ether 0.02ether
place_order $ALICE_PK true 1620ether 0.005ether

echo "[4/4] Seeding Complete!"
