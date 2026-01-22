#!/usr/bin/env bash
set -e

# Configuration
RPC_URL="http://localhost:8545"
# Try to find .env.local, fallback to standard path
ENV_FILE="$(dirname "${BASH_SOURCE[0]}")/../frontend/.env.local"

if [ -f "$ENV_FILE" ]; then
    # Extract address using grep/cut to avoid sourcing potential js/ts syntax
    EXCHANGE=$(grep VITE_EXCHANGE_ADDRESS "$ENV_FILE" | cut -d '=' -f2)
    echo "Using Exchange Address: $EXCHANGE"
else
    echo "Error: frontend/.env.local not found. Please ensure frontend is configured."
    exit 1
fi

# Test Accounts (Anvil Defaults)
ALICE_PK="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
BOB_PK="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
CAROL_PK="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"

echo "=================================================="
echo "   Monad Exchange: Seeding Leaderboard Data"
echo "=================================================="

check_tx() {
    if [ $? -ne 0 ]; then
        echo "❌ Transaction Failed!"
        exit 1
    fi
}

place_order() {
    local pk=$1
    local is_buy=$2
    local price=$3
    local amount=$4
    echo "  -> Order: Buy=$is_buy Price=$price Amount=$amount"
    cast send --rpc-url $RPC_URL --private-key $pk $EXCHANGE "placeOrder(bool,uint256,uint256,uint256)" $is_buy $price $amount 0 --gas-price 20gwei
    check_tx
    sleep 1
}

echo "[1/4] Setting Index Price..."
# Reset price to known state to avoid markPrice issues
cast send --rpc-url $RPC_URL --private-key $ALICE_PK $EXCHANGE "updateIndexPrice(uint256)" 2000ether --gas-price 20gwei
check_tx

echo "[2/4] Depositing Funds (Safe Whale Mode)..."
# Anvil accounts usually have 10,000 ETH. Let's use 5,000 to be safe but strong.
echo "  -> Alice Deposit 5,000 ETH"
cast send --rpc-url $RPC_URL --private-key $ALICE_PK $EXCHANGE "deposit()" --value 5000ether --gas-price 20gwei
check_tx

echo "  -> Bob Deposit 5,000 ETH"
cast send --rpc-url $RPC_URL --private-key $BOB_PK $EXCHANGE "deposit()" --value 5000ether --gas-price 20gwei
check_tx

echo "  -> Carol Deposit 5,000 ETH"
cast send --rpc-url $RPC_URL --private-key $CAROL_PK $EXCHANGE "deposit()" --value 5000ether --gas-price 20gwei
check_tx

echo "[3/4] Generating Profitable Trades (Realized PnL)..."

# Scenario A: Alice Wins, Bob Loses
# 1. Open Position @ 2000
echo "  -> Opening: Alice Long 1 ETH, Bob Short 1 ETH @ 2000"
place_order $BOB_PK false 2000ether 1ether
place_order $ALICE_PK true 2000ether 1ether

# 2. Close Position @ 2100
# Alice (Long) sells @ 2100 -> Profit +100
# Bob (Short) buys @ 2100 -> Loss -100
echo "  -> Closing: Alice Sells, Bob Buys @ 2100"
place_order $ALICE_PK false 2100ether 1ether
place_order $BOB_PK true 2100ether 1ether

echo "[4/4] Generating More Activity..."

# Update Index Price to support higher trading range
echo "  -> Updating Index Price to 3000..."
cast send --rpc-url $RPC_URL --private-key $ALICE_PK $EXCHANGE "updateIndexPrice(uint256)" 3000ether --gas-price 20gwei
check_tx

# Scenario B: Carol Wins Big
# 1. Carol Shorts @ 3000
echo "  -> Opening: Carol Short 5 ETH, Alice Long 5 ETH @ 3000"
place_order $ALICE_PK true 3000ether 5ether
place_order $CAROL_PK false 3000ether 5ether

# Update Index Price to reflect market crash
echo "  -> Updating Index Price to 2500..."
cast send --rpc-url $RPC_URL --private-key $ALICE_PK $EXCHANGE "updateIndexPrice(uint256)" 2500ether --gas-price 20gwei
check_tx

# 2. Close @ 2500
# Carol (Short) buys @ 2500 -> Profit (3000-2500)*5 = +2500
# Alice (Long) sells @ 2500 -> Loss -2500
echo "  -> Closing: Carol Buys, Alice Sells @ 2500"
place_order $CAROL_PK true 2500ether 5ether
place_order $ALICE_PK false 2500ether 5ether

echo "✅ Leaderboard Data Seeded!"
echo "Alice should have mixed PnL."
echo "Bob should be negative."
echo "Carol should be top of leaderboard."
