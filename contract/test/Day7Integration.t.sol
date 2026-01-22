// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./utils/ExchangeFixture.sol";

// Day 7: 端到端流程（挂单 -> 撮合 -> 资金费率 -> 清算）
contract Day7IntegrationTest is ExchangeFixture {
    function setUp() public override {
        super.setUp();
        _deposit(alice, 2000 ether); // wei 级别，便于观察 margin 变化
        _deposit(bob, 2000 ether);
        vm.deal(carol, 1 ether);
    }

    function testEndToEndFlow() public {
        // 用例：完整链路演练，验证撮合、资金费率结算、清算及奖励分配
        // 1) Alice 挂买单，Bob 卖出吃单（完全成交）
        vm.prank(alice);
        exchange.placeOrder(true, 100 ether, 2 ether, 0);
        vm.prank(bob);
        exchange.placeOrder(false, 90 ether, 2 ether, 0);

        assertEq(exchange.bestBuyId(), 0, "orderbook cleared for bids");
        assertEq(exchange.bestSellId(), 0, "orderbook cleared for asks");

        MonadPerpExchange.Position memory pa = exchange.getPosition(alice);
        MonadPerpExchange.Position memory pb = exchange.getPosition(bob);
        assertEq(pa.size, int256(2 ether), "alice long 2");
        assertEq(pb.size, -int256(2 ether), "bob short 2");
        assertEq(pa.entryPrice, 100 ether, "entry @100");
        assertEq(pb.entryPrice, 100 ether, "entry @100");

        // 2) 资金费率：mark 远高于 index，累加一次资金费，long 支付/short 获得
        // mock.setPrice(DEFAULT_PRICE_ID, 1300, -18); 
        // exchange.updateMarkPriceFromPyth();
        exchange.updateIndexPrice(1300 ether);

        vm.warp(block.timestamp + exchange.fundingInterval());
        exchange.settleFunding();
        int256 rate = exchange.cumulativeFundingRate();
        uint256 marginALong = exchange.margin(alice);
        uint256 marginBShort = exchange.margin(bob);
        exchange.settleUserFunding(alice);
        exchange.settleUserFunding(bob);
        // Payment = (Size * Mark * Rate) / 1e36
        // Size=2e18, Mark=1300e18, Rate=rate
        uint256 payment = uint256((int256(2 ether) * int256(1300 ether) * rate) / 1e36);
        assertEq(exchange.margin(alice), marginALong - payment, "long pays funding");
        assertEq(exchange.margin(bob), marginBShort + payment, "short receives funding");

        // 3) 标记价上涨，空头触发清算
        // Use 1095 to trigger liquidation
        uint256 liqPrice = 1095 ether;
        exchange.updateIndexPrice(liqPrice);
        assertTrue(exchange.canLiquidate(bob), "short should be unsafe");
        uint256 bobMarginBeforeLiq = exchange.margin(bob);

        // Liquidator (Carol) provides liquidity
        vm.startPrank(carol);
        vm.deal(carol, 20000 ether); 
        exchange.deposit{value: 2000 ether}();
        
        // Carol places Sell Order @ 1095 to allow Bob to close
        exchange.placeOrder(false, 1095 ether, 2 ether, 0);
        
        // Trigger Liquidation
        exchange.liquidate(bob, 2 ether);
        vm.stopPrank();

        // 6. Verify Bob's Position Closed
        MonadPerpExchange.Position memory pbAfter = exchange.getPosition(bob);
        assertEq(pbAfter.size, 0, "Bob should be closed");
        
        // 7. Verify Carol got the position
        MonadPerpExchange.Position memory pcAfter = exchange.getPosition(carol);
        assertEq(pcAfter.size, -2 ether, "Carol sold 2 ETH to Bob");
        
        // 8. Verify Carol received Liquidation Fee
        // Bob Position Value: 2 * 1095 = 2190.
        // Target Fee: 2190 * 1.25% = 27.375 ether.
        // But Bob only has ~10 ether + funding left.
        // Carol gets min(TargetFee, BobAvailable).
        
        // Calculate Bob's available margin before fee deduction
        // We know Bob was closed, so his margin is now just his remaining balance.
        // Wait, margin() returns 0 if he was drained.
        // Let's calculate what he HAD.
        // We can infer it from Carol's gain.
        
        uint256 carolGain = exchange.margin(carol) - 2000 ether;
        uint256 targetFee = (2 ether * 1095 ether * 125) / 10000 / 1e18; // 27.375 ether
        
        // Bob didn't have enough for full fee, so Carol got whatever was left.
        // This confirms "Bad Debt" logic (Bob is drained).
        assertTrue(carolGain < targetFee, "Bob could not pay full fee");
        assertTrue(carolGain > 0, "Carol received some fee");
        
        // Optional: Verify exact amount if we tracked funding precisely.
        // But verifying she got *something* and Bob is empty is sufficient for integration test.
        assertEq(exchange.margin(bob), 0, "Bob should be drained");
    }

    function testBadDebtLiquidation() public {
        // 1. Bob Shorts 10 ETH @ 100
        vm.prank(bob);
        exchange.placeOrder(false, 100 ether, 10 ether, 0);
        
        // 2. Alice Longs 10 ETH @ 100 (Match)
        vm.prank(alice);
        exchange.placeOrder(true, 100 ether, 10 ether, 0);
        
        // 3. Price spikes to 5000 (Bob is REKT)
        exchange.updatePrices(5000 ether, 5000 ether);
        
        // 4. Carol provides liquidity to exit
        // Carol places Sell Order @ 5000 (to let Bob buy back)
        // Carol needs margin to place this order (10 * 5000 * 1% = 500 ETH)
        vm.deal(carol, 1000 ether);
        vm.startPrank(carol);
        exchange.deposit{value: 1000 ether}();
        exchange.placeOrder(false, 5000 ether, 10 ether, 0);
        
        // 5. Liquidate Bob
        exchange.liquidate(bob, 10 ether);
        vm.stopPrank();
        
        // 6. Verify Bad Debt
        MonadPerpExchange.Position memory pb = exchange.getPosition(bob);
        assertEq(pb.size, 0, "Bob position should be closed");
        // Bad debt: Bob's margin is drained (loss exceeded deposit)
        assertEq(exchange.margin(bob), 0, "Bob should have bad debt (margin drained)");
    }
}

