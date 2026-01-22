// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./utils/ExchangeFixture.sol";

// Day 2: 订单簿插入与优先级
contract Day2OrderbookTest is ExchangeFixture {
    function setUp() public override {
        super.setUp();
        _deposit(alice, 100 ether);
        _deposit(bob, 100 ether);
    }

    function testOrderInsertionMaintainsPriority() public {
        // 用例：买单价格高者优先，链表顺序保持 120 > 110 > 100
        vm.prank(alice);
        uint256 low = exchange.placeOrder(true, 100, 2, 0);
        vm.prank(bob);
        uint256 high = exchange.placeOrder(true, 120, 1, 0);
        vm.prank(alice);
        uint256 mid = exchange.placeOrder(true, 110, 1, 0);

        assertEq(exchange.bestBuyId(), high, "highest price should be head");
        MonadPerpExchange.Order memory best = exchange.getOrder(high);
        MonadPerpExchange.Order memory second = exchange.getOrder(best.next);
        MonadPerpExchange.Order memory tail = exchange.getOrder(second.next);

        assertEq(second.id, mid, "mid price follows best");
        assertEq(tail.id, low, "lowest price at tail");
    }

    function testFuzzHigherBidBecomesHead(uint80 highPrice, uint80 lowPrice, uint64 amountA, uint64 amountB) public {
        // Fuzz：任何更高买价都应成为链表头
        vm.assume(highPrice > lowPrice);
        vm.assume(lowPrice > 0);
        vm.assume(amountA > 0 && amountB > 0);
        vm.assume(uint256(highPrice) * amountB <= 50 ether);
        vm.assume(uint256(lowPrice) * amountA <= 50 ether);

        vm.prank(alice);
        exchange.placeOrder(true, lowPrice, amountA, 0);
        vm.prank(bob);
        uint256 hid = exchange.placeOrder(true, highPrice, amountB, 0);

        assertEq(exchange.bestBuyId(), hid, "higher price wins head");
    }

    function testSellInsertionMaintainsPriority() public {
        vm.prank(alice);
        uint256 high = exchange.placeOrder(false, 150, 1, 0);
        vm.prank(bob);
        uint256 low = exchange.placeOrder(false, 120, 2, 0);
        vm.prank(alice);
        uint256 mid = exchange.placeOrder(false, 140, 1, 0);

        assertEq(exchange.bestSellId(), low, "lowest ask should be head");
        MonadPerpExchange.Order memory head = exchange.getOrder(low);
        MonadPerpExchange.Order memory next = exchange.getOrder(head.next);
        MonadPerpExchange.Order memory tail = exchange.getOrder(next.next);

        assertEq(next.id, mid, "middle ask next");
        assertEq(tail.id, high, "highest ask last");
    }

    function testFuzzLowerAskBecomesHead(uint80 lowPrice, uint80 highPrice, uint64 amountA, uint64 amountB) public {
        vm.assume(lowPrice < highPrice);
        vm.assume(lowPrice > 0);
        vm.assume(amountA > 0 && amountB > 0);
        vm.assume(uint256(highPrice) * amountA <= 50 ether);
        vm.assume(uint256(lowPrice) * amountB <= 50 ether);

        vm.prank(alice);
        exchange.placeOrder(false, highPrice, amountA, 0);
        vm.prank(bob);
        uint256 lid = exchange.placeOrder(false, lowPrice, amountB, 0);

        assertEq(exchange.bestSellId(), lid, "lower ask becomes head");
    }

    function testInsertWithValidHintAppendsSamePriceTail() public {
        // 用例：同价位使用 hint 插到尾部
        vm.prank(alice);
        uint256 first = exchange.placeOrder(true, 100, 1, 0);
        vm.prank(bob);
        uint256 second = exchange.placeOrder(true, 100, 1, first);

        MonadPerpExchange.Order memory head = exchange.getOrder(first);
        assertEq(head.next, second, "second should follow first at same price");
    }

    function testInsertWithSamePriceNonTailReverts() public {
        // 用例：hint 不是同价尾部时应 revert，防止恶意插队
        vm.prank(alice);
        uint256 first = exchange.placeOrder(false, 120, 1, 0);
        vm.prank(bob);
        uint256 second = exchange.placeOrder(false, 120, 1, 0);

        vm.prank(alice);
        vm.expectRevert(bytes("hint not last"));
        exchange.placeOrder(false, 120, 1, first);

        vm.prank(alice);
        exchange.placeOrder(false, 120, 1, second);
    }

    function testInsertPriceBetterThanHintReverts() public {
        // 用例：价格优于 hint 但仍试图从 hint 之后插入，应 revert
        vm.prank(alice);
        uint256 low = exchange.placeOrder(true, 100, 1, 0);

        vm.prank(bob);
        vm.expectRevert(bytes("hint too deep"));
        exchange.placeOrder(true, 150, 1, low);
    }

    function testNonexistentHintReverts() public {
        // 用例：不存在的 hint 直接 revert
        vm.prank(alice);
        vm.expectRevert(bytes("invalid hint"));
        exchange.placeOrder(true, 100, 1, 123456); // hint 未存在
    }
}
