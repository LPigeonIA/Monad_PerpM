// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/Exchange.sol";
import "./MonadPerpExchangeHarness.sol";

contract ExchangeFixture is Test {
    // 公用测试基类：初始化合约与三名账户并预充值 ETH
    MonadPerpExchangeHarness internal exchange;
    bytes32 internal constant DEFAULT_PRICE_ID = keccak256("DEFAULT");
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCAFE);

    function setUp() public virtual {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        // Deploy Exchange (no price feed arg)
        exchange = new MonadPerpExchangeHarness();
        
        // Initial price setup
        exchange.updateIndexPrice(100 ether);

        vm.deal(alice, 100_000 ether);
        vm.deal(bob, 100_000 ether);
        vm.deal(carol, 100_000 ether);
    }

    function _deposit(address trader, uint256 amount) internal {
        vm.prank(trader);
        exchange.deposit{value: amount}();
    }
}
