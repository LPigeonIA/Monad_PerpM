// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./utils/ExchangeFixture.sol";

// Day 6: 清算
contract Day6LiquidationTest is ExchangeFixture {
    function setUp() public override {
        super.setUp();
        _deposit(alice, 300 ether); 
        _deposit(bob, 2000 ether);
        // Carol no longer needs margin to liquidate, she just triggers it.
        // But she needs margin to place the BUY orders that Alice will match against.
        _deposit(carol, 2000 ether); 
        exchange.setManualPriceMode(true);
    }

    function testLiquidationMarketClose() public {
        // Scenario: Alice Longs, Price Drops, Liquidated into Carol's Bids.
        
        // 1. Alice Longs 10 @ 100
        vm.prank(alice);
        exchange.placeOrder(true, 100 ether, 10 ether, 0);
        
        // 2. Bob Shorts 10 @ 100 (Match)
        vm.prank(bob);
        exchange.placeOrder(false, 100 ether, 10 ether, 0);
        
        // 3. Carol places Buy Orders at 80 (Liquidity for liquidation)
        vm.prank(carol);
        exchange.placeOrder(true, 80 ether, 20 ether, 0);
        
        // 4. Price Drops to 50
        exchange.updatePrices(50 ether, 50 ether);
        
        // Check if liquidatable
        assertTrue(exchange.canLiquidate(alice), "Alice should be liquidatable");
        
        // 5. Liquidate Alice
        // Bob triggers liquidation. Bob gets the reward.
        vm.prank(bob); 
        exchange.liquidate(alice, 10 ether);
        
        // 6. Verify Results
        // Alice's position should be 0 (Sold 10 to Carol)
        MonadPerpExchange.Position memory pAlice = exchange.getPosition(alice);
        assertEq(pAlice.size, 0, "Alice position should be closed");
        
        // Carol's position should be +10 (Bought from Alice)
        // Carol already had 0. Now +10.
        MonadPerpExchange.Position memory pCarol = exchange.getPosition(carol);
        assertEq(pCarol.size, 10 ether, "Carol should have bought Alice's position");
        assertEq(pCarol.entryPrice, 80 ether, "Carol entry price should be her bid price");
        
        // Alice's Margin
        // Loss: (100 - 80) * 10 = 200 ether.
        // Initial Margin: 2000. Remaining: 1800. (Wait, Alice deposit 300)
        // Alice Deposit: 300. Loss: 200. Remaining: 100.
        // Fee: Notional * 1.25% = (10 * 50) * 1.25% = 500 * 0.0125 = 6.25 ether.
        // Alice Final: 100 - 6.25 = 93.75 ether.
        
        // Bob (Liquidator) Reward: +6.25 ether.
        // Bob started with 2000 - 1000 (margin for short) = 1000 free?
        // Bob Short 10 @ 100. Price 50. Bob Unrealized PnL +500.
        // Bob Free Margin should increase by reward.
        
        uint256 fee = (10 ether * 50 ether * 125) / 10000 / 1e18; // 6.25 ether
        assertEq(exchange.margin(alice), 100 ether - fee, "Alice margin after loss and fee");
        
        // Verify Bob (Liquidator) received the fee
        // Bob Initial: 2000.
        // Bob Short 10 @ 100. Price 50. Unrealized PnL: (100 - 50) * 10 = +500.
        // Bob Margin = Initial + Unrealized + Fee?
        // Wait, exchange.margin(bob) returns margin.
        // Bob's margin includes realizedPnl (none yet) and unrealized?
        // No, margin is balance. Unrealized is separate.
        // Bob received fee into margin.
        // Bob paid nothing (he just triggered).
        // So Bob's margin should be Initial + Fee.
        assertEq(exchange.margin(bob), 2000 ether + fee, "Bob received fee");
    }

    function testLiquidationPartialFillRevertsIfStillUnhealthy() public {
        // H-1 Fix Test: Partial liquidation should revert if remaining position is still unhealthy
        // This prevents attackers from repeatedly liquidating tiny amounts to extract fees
        
        vm.prank(alice);
        exchange.placeOrder(true, 100 ether, 10 ether, 0);
        vm.prank(bob);
        exchange.placeOrder(false, 100 ether, 10 ether, 0);
        
        // Carol places Buy Order for only 5 @ 80
        vm.prank(carol);
        exchange.placeOrder(true, 80 ether, 5 ether, 0);
        
        exchange.updatePrices(50 ether, 50 ether);
        assertTrue(exchange.canLiquidate(alice), "Alice should be liquidatable");
        
        // Try to partial liquidate - should REVERT because remaining 5 ETH position is still unhealthy
        vm.prank(carol);
        vm.expectRevert("must fully liquidate unhealthy position");
        exchange.liquidate(alice, 5 ether);
    }

    function testCannotLiquidateHealthyPosition() public {
        vm.prank(alice);
        exchange.placeOrder(true, 100 ether, 10 ether, 0);
        vm.prank(bob);
        exchange.placeOrder(false, 100 ether, 10 ether, 0);
        
        exchange.updatePrices(110 ether, 110 ether); // Price up, Long is happy
        assertFalse(exchange.canLiquidate(alice), "Should be safe");
        
        vm.expectRevert(bytes("position healthy"));

        exchange.liquidate(alice, 10 ether);
    }
    
    function testLiquidationClearsOrders() public {
        // Alice has open orders that lock margin. Liquidation should cancel them to free margin.
        vm.prank(alice);
        exchange.placeOrder(true, 100 ether, 10 ether, 0); // Long 10
        vm.prank(bob);
        exchange.placeOrder(false, 100 ether, 10 ether, 0); // Match
        
        // Alice places another order
        vm.prank(alice);
        uint256 orderId = exchange.placeOrder(true, 90 ether, 5 ether, 0); // Buy 5 @ 90. Locks margin.
        
        // Verify order exists
        (uint256 id, , , , , , , ) = exchange.orders(orderId);
        assertEq(id, orderId, "Order should exist");
        
        
        // uint256 lockedBefore = exchange.lockedMargin(alice); // No longer exists
        // assertTrue(lockedBefore > 0, "Should have locked margin"); // No longer exists
        
        // Price crash
        exchange.updatePrices(50 ether, 50 ether);
        
        // Carol provides liquidity
        vm.prank(carol);
        exchange.placeOrder(true, 60 ether, 20 ether, 0);
        
        vm.prank(carol);
        exchange.liquidate(alice, 10 ether);
        
        // Locked margin should be 0
        // assertEq(exchange.lockedMargin(alice), 0, "Locked margin should be cleared");
        // Position closed
        assertEq(exchange.getPosition(alice).size, 0, "Position closed");
        
        // Verify order cleared
        (uint256 idAfter, , , , , , , ) = exchange.orders(orderId);
        assertEq(idAfter, 0, "Order should be deleted");
    }

    function testFuzzLiquidationPnL(uint256 executionPrice) public {
        // Fuzzing the execution price (Carol's Bid)
        // Constraints: Price must be > 0 and < Entry Price (100) to cause loss.
        // Also needs to be low enough to trigger liquidation.
        
        // Clamp price between 1 and 99 ether
        executionPrice = bound(executionPrice, 1 ether, 99 ether);
        
        // Setup
        uint256 size = 10 ether;
        uint256 entryPrice = 100 ether;
        uint256 initialMargin = 2000 ether;
        
        _deposit(alice, initialMargin);
        _deposit(bob, initialMargin);
        _deposit(carol, initialMargin * 10); // Rich Carol
        
        // 1. Alice Longs 10 @ 100
        vm.prank(alice);
        exchange.placeOrder(true, entryPrice, size, 0);
        vm.prank(bob);
        exchange.placeOrder(false, entryPrice, size, 0);
        
        // 2. Carol places Buy Order at fuzzed price
        vm.prank(carol);
        exchange.placeOrder(true, executionPrice, size, 0);
        
        // 3. Update Oracle Price to executionPrice (or slightly below to ensure trigger)
        exchange.updatePrices(executionPrice, executionPrice);
        
        // 4. Check Liquidation Condition
        bool unsafe = exchange.canLiquidate(alice);
        
        // Calculate expected values
        // Value = Price * Size
        // Maintenance = Value * 0.5%
        // PnL = (Price - Entry) * Size
        // Margin = Initial + PnL
        
        int256 pnl = (int256(executionPrice) - int256(entryPrice)) * int256(size) / 1e18;
        int256 marginBalance = int256(initialMargin) + pnl;
        uint256 positionValue = (executionPrice * size) / 1e18;
        uint256 maintenance = (positionValue * 50) / 10000; // 50 bps
        
        if (marginBalance < int256(maintenance)) {
            // Should be liquidatable
            assertTrue(unsafe, "Should be liquidatable");
            
            // Execute Liquidation
            vm.prank(bob);
            exchange.liquidate(alice, size);
            
            // Verify Alice's Margin
            // Alice sold at executionPrice (Market Close)
            // Realized PnL = (executionPrice - entryPrice) * size
            // Free Margin = Initial + Realized PnL - Fee
            
            uint256 fee = (size * executionPrice * 125) / 10000 / 1e18;
            uint256 expectedMargin = uint256(int256(initialMargin) + pnl) - fee;
            
            // If bad debt (margin < 0), expectedMargin is 0 in exchange.margin() view?
            // exchange.margin() returns account margin.
            // If bad debt, margin is 0.
            if (int256(initialMargin) + pnl - int256(fee) < 0) {
                 assertEq(exchange.margin(alice), 0, "Alice should be broke");
            } else {
                 assertEq(exchange.margin(alice), expectedMargin, "Alice margin mismatch");
            }
            
            // Verify Carol's Entry
            MonadPerpExchange.Position memory pCarol = exchange.getPosition(carol);
            assertEq(pCarol.size, int256(size), "Carol size mismatch");
            assertEq(pCarol.entryPrice, executionPrice, "Carol entry price mismatch");
        } else {
            // Should NOT be liquidatable
            assertFalse(unsafe, "Should not be liquidatable");
            vm.expectRevert(bytes("position healthy"));
            vm.prank(bob);
            exchange.liquidate(alice, size);
        }
    }
}
