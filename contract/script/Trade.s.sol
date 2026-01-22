// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Exchange.sol";

contract TradeScript is Script {
    function run() external {
        uint256 privateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        address exchangeAddr = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
        
        vm.startBroadcast(privateKey);
        
        MonadPerpExchange exchange = MonadPerpExchange(exchangeAddr);
        
        // Deposit 10 ETH
        exchange.deposit{value: 10 ether}();
        console.log("Deposited 10 ETH");
        
        // Place Buy Order: 0.001 ETH @ 1500
        uint256 price = 1500;
        uint256 amount = 1e15;
        exchange.placeOrder(true, price, amount, 0);
        console.log("Placed Buy Order");
        
        // Place Sell Order: 1 ETH @ 1500
        exchange.placeOrder(false, price, amount, 0);
        console.log("Placed Sell Order");
        
        vm.stopBroadcast();
    }
}
