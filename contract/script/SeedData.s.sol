// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Exchange.sol";

contract SeedDataScript is Script {
    // Anvil Account #0 (Deployer / Alice)
    uint256 internal constant ALICE_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address internal constant ALICE = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    // Anvil Account #1 (Bob)
    uint256 internal constant BOB_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    address internal constant BOB = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    // Exchange Address (Deterministic for Anvil)
    // Exchange Address (Deterministic for Anvil - First Contract)
    address internal constant HARDCODED_EXCHANGE_ADDR = 0x5FbDB2315678afecb367f032d93F642f64180aa3;

    function run() external {
        address exchangeAddr = vm.envOr("VITE_EXCHANGE_ADDRESS", HARDCODED_EXCHANGE_ADDR);
        MonadPerpExchange exchange = MonadPerpExchange(exchangeAddr);

        // 0. Set Initial Price (Operator)
        vm.startBroadcast(ALICE_PK); // Alice is deployer/operator
        exchange.updateIndexPrice(1500 ether);
        console.log("Index Price set to 1500");
        vm.stopBroadcast();

        // 1. Deposits
        vm.startBroadcast(ALICE_PK);
        exchange.deposit{value: 1000 ether}();
        console.log("Alice deposited 1000 ETH");
        vm.stopBroadcast();

        vm.startBroadcast(BOB_PK);
        exchange.deposit{value: 1000 ether}();
        console.log("Bob deposited 1000 ETH");
        vm.stopBroadcast();

        // 2. Create Candle History (manipulating time)
        // Candle 1: Price 1500 -> 1510
        _trade(exchange, 1500 ether, 10 ether); // Alice buys from Bob
        
        // Move forward 1 hour
        vm.warp(block.timestamp + 3600);
        vm.startBroadcast(ALICE_PK);
        exchange.updateIndexPrice(1520 ether);
        vm.stopBroadcast();
        _trade(exchange, 1520 ether, 20 ether);

        // Move forward 1 hour
        vm.warp(block.timestamp + 3600);
        vm.startBroadcast(ALICE_PK);
        exchange.updateIndexPrice(1490 ether);
        vm.stopBroadcast();
        _trade(exchange, 1490 ether, 15 ether);

        // Move forward 1 hour
        vm.warp(block.timestamp + 3600);
        vm.startBroadcast(ALICE_PK);
        exchange.updateIndexPrice(1550 ether);
        vm.stopBroadcast();
        _trade(exchange, 1550 ether, 30 ether);

        // 3. Place Open Orders (Orderbook)
        vm.startBroadcast(ALICE_PK);
        exchange.placeOrder(true, 1400 ether, 10 ether, 0); // Buy @ 1400
        exchange.placeOrder(true, 1450 ether, 20 ether, 0); // Buy @ 1450
        console.log("Alice placed buy orders");
        vm.stopBroadcast();

        vm.startBroadcast(BOB_PK);
        exchange.placeOrder(false, 1600 ether, 15 ether, 0); // Sell @ 1600
        exchange.placeOrder(false, 1650 ether, 25 ether, 0); // Sell @ 1650
        console.log("Bob placed sell orders");
        vm.stopBroadcast();
    }

    function _trade(MonadPerpExchange exchange, uint256 price, uint256 amount) internal {
        // Bob places a sell order
        vm.startBroadcast(BOB_PK);
        exchange.placeOrder(false, price, amount, 0);
        vm.stopBroadcast();

        // Alice buys it
        vm.startBroadcast(ALICE_PK);
        exchange.placeOrder(true, price, amount, 0);
        vm.stopBroadcast();
        
        console.log("Executed trade at", price / 1e18);
    }
}
