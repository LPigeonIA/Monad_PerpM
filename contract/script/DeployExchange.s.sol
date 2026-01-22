// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Exchange.sol";
// import "../test/mocks/MockPyth.sol";

/// @notice Deploy MonadPerpExchange to a local anvil fork (or any RPC) and wire it to Pyth.
/// Usage:
/// PRIVATE_KEY=<anvil key> forge script script/DeployExchange.s.sol:DeployExchangeScript --broadcast --rpc-url http://127.0.0.1:8545
/// Optional env:
///   - PYTH_CONTRACT : existing Pyth address on fork (defaults to Monad public address)
///   - PYTH_PRICE_ID : priceId to read (defaults BTC/USDT)
///   - USE_MOCK_PYTH : set true to deploy MockPyth instead of using on-chain Pyth
///   - MOCK_PRICE    : initial mock price (int64)
///   - MOCK_EXPO     : mock price exponent (int32)
contract DeployExchangeScript is Script {
    // anvil 默认助记词 "test test test test test test test test test test test junk"，第 0 个私钥
    uint256 internal constant DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        
        MonadPerpExchange exchange = new MonadPerpExchange();
        
        // Optional: Set initial price if needed (e.g. 60000 ether)
        // exchange.updateIndexPrice(60000 ether);

        console2.log("Exchange deployed", address(exchange));
        vm.stopBroadcast();
    }
}
