// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./utils/ExchangeFixture.sol";

// Day 3: 撮合与持仓更新
contract Day3MatchingTest is ExchangeFixture {
    function setUp() public override {
        super.setUp();
        _deposit(alice, 500 ether);
        _deposit(bob, 500 ether);
    }

    function testMatchingUpdatesPositions() public {
        // 用例：部分成交后，挂单剩余数量更新，双方持仓方向/价格正确
        vm.prank(alice);
        uint256 buyId = exchange.placeOrder(true, 100 ether, 2 ether, 0);
        vm.prank(bob);
        exchange.placeOrder(false, 90 ether, 1 ether, 0); // 部分吃单

        MonadPerpExchange.Order memory updatedBuy = exchange.getOrder(buyId);
        assertEq(updatedBuy.amount, 1 ether, "order should partially remain");

        MonadPerpExchange.Position memory pa = exchange.getPosition(alice);
        MonadPerpExchange.Position memory pb = exchange.getPosition(bob);
        assertEq(pa.size, int256(1 ether), "alice long size");
        assertEq(pb.size, -int256(1 ether), "bob short size");
        assertEq(pa.entryPrice, 100 ether, "entry recorded at maker price");
    }

    function testBuyBelowBestAskDoesNotMatch() public {
        // 用例：买价低于最优卖，双方订单应留在簿上不成交
        vm.prank(bob);
        uint256 askId = exchange.placeOrder(false, 150 ether, 1 ether, 0);

        vm.prank(alice);
        uint256 bidId = exchange.placeOrder(true, 100 ether, 1 ether, 0);

        assertEq(exchange.bestSellId(), askId, "ask should stay on book");
        assertEq(exchange.bestBuyId(), bidId, "bid should rest as best bid");
        MonadPerpExchange.Order memory ask = exchange.getOrder(askId);
        assertEq(ask.amount, 1 ether, "ask untouched");
    }

    function testClosingPositionRealizesPnl() public {
        // 用例：反向平仓应结算已实现盈亏并清空仓位
        vm.prank(bob);
        exchange.placeOrder(false, 100 ether, 1 ether, 0);
        vm.prank(alice);
        exchange.placeOrder(true, 100 ether, 1 ether, 0); // alice long @100

        vm.prank(alice);
        exchange.placeOrder(false, 150 ether, 1 ether, 0); // place closing ask
        vm.prank(bob);
        exchange.placeOrder(true, 150 ether, 1 ether, 0); // bob lifts

        MonadPerpExchange.Position memory pa = exchange.getPosition(alice);
        assertEq(pa.size, 0, "position closed");
        // Realized PnL is settled directly into margin, verify via margin check:
        assertEq(exchange.margin(alice), 500 ether + 50 ether, "margin credited with pnl");
    }

    function testTakerCrossesMultipleAsksAndReleasesLockedMargin() public {
        // 用例：taker 一次吃多档卖单，逐笔解锁锁定保证金且订单簿更新
        vm.prank(bob);
        exchange.placeOrder(false, 120 ether, 1 ether, 0); // ask1
        vm.prank(bob);
        exchange.placeOrder(false, 110 ether, 1 ether, 0); // ask2
        vm.prank(bob);
        exchange.placeOrder(false, 100 ether, 1 ether, 0); // ask3 (best)

        // uint256 lockedBefore = exchange.lockedMargin(bob); // No longer exists

        vm.prank(alice);
        exchange.placeOrder(true, 130 ether, 3 ether, 0); // taker crosses all

        assertEq(exchange.bestSellId(), 0, "orderbook cleared");
        // assertEq(exchange.lockedMargin(bob), 0, "locked margin released after fills"); // No longer exists

        MonadPerpExchange.Position memory pa = exchange.getPosition(alice);
        MonadPerpExchange.Position memory pb = exchange.getPosition(bob);
        assertEq(pa.size, int256(3 ether), "alice long 3");
        assertEq(pb.size, -int256(3 ether), "bob short 3");
        // assertGt(lockedBefore, 0, "initially locked"); // No longer exists
    }
}
