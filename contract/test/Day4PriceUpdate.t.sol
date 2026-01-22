// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./utils/ExchangeFixture.sol";
import "../src/core/ExchangeStorage.sol";
// import "./mocks/MockPyth.sol";

// Day 4: Pyth 价格更新（模板级别，使用本地 mock）
contract Day4PriceUpdateTest is ExchangeFixture {
    function setUp() public override {
        super.setUp();
        // Grant operator role to this test contract for testing
        exchange.grantRole(exchange.OPERATOR_ROLE(), address(this));
    }

    function testOperatorCanUpdatePrice() public {
        uint256 newPrice = 250 ether;
        exchange.updateIndexPrice(newPrice);

        assertEq(exchange.indexPrice(), newPrice, "index price updated");
        assertEq(exchange.markPrice(), newPrice, "mark price follows index (empty book)");
    }

    function testNonOperatorCannotUpdatePrice() public {
        vm.prank(alice);
        vm.expectRevert();
        exchange.updateIndexPrice(300 ether);
    }

    function testUpdatePriceEmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit ExchangeStorage.MarkPriceUpdated(300 ether, 300 ether);
        exchange.updateIndexPrice(300 ether);
    }

    // ============================================================
    // 以下测试从 Day1Margin.t.sol 移入
    // 原因：它们依赖 placeOrder (Day2/3) 和 updateIndexPrice (Day4)
    // ============================================================

    function testWithdrawWhilePositionOpenUsesFreshPrice() public {
        // 用例：有持仓时提现前拉取最新价，保证金充足则允许提现
        _deposit(alice, 1 ether);
        _deposit(bob, 1 ether);

        vm.prank(alice);
        exchange.placeOrder(true, 1 ether, 1 ether, 0); // Alice 多头
        vm.prank(bob);
        exchange.placeOrder(false, 1 ether, 1 ether, 0); // Bob 做空，成交

        // 价格不变，无盈亏，保证金充足
        exchange.updateIndexPrice(1 ether);

        vm.prank(alice);
        exchange.withdraw(0.5 ether);
        assertLt(exchange.margin(alice), 1 ether, "margin should reduce");
        assertGt(exchange.margin(alice), 0, "margin remains positive");
    }

    function testWithdrawWithExcessMarginAllowed() public {
        // 用例：持仓但保证金充足时允许部分提现
        _deposit(alice, 10 ether);
        _deposit(bob, 10 ether);

        vm.prank(alice);
        exchange.placeOrder(true, 100 ether, 1 ether, 0); // notional 100
        vm.prank(bob);
        exchange.placeOrder(false, 100 ether, 1 ether, 0);

        // 标记价有利于多头，未实现收益增加可提现空间
        exchange.updateIndexPrice(150 ether);
        vm.prank(alice);
        exchange.withdraw(5 ether); // 应允许部分提现
        assertEq(exchange.margin(alice), 5 ether, "remaining margin tracked");
    }
}
