// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./utils/ExchangeFixture.sol";

// Day 1: 基础保证金流
contract Day1MarginTest is ExchangeFixture {
    function testDepositTracksMargin() public {
        // 用例：充值后保证金应准确增加
        _deposit(alice, 1 ether);
        assertEq(exchange.margin(alice), 1 ether, "margin after deposit");
    }

    function testWithdrawReducesMargin() public {
        // 用例：正常提现应减少保证金
        _deposit(alice, 1 ether);
        vm.prank(alice);
        exchange.withdraw(0.4 ether);
        assertEq(exchange.margin(alice), 0.6 ether, "margin after withdraw");
    }

    function testWithdrawMoreThanMarginReverts() public {
        // 用例：超额提现应 revert
        _deposit(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(bytes("not enough margin"));
        exchange.withdraw(2 ether);
    }

    function testWithdrawZeroReverts() public {
        // 用例：零金额提现应 revert
        _deposit(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(bytes("amount=0"));
        exchange.withdraw(0);
    }

    // NOTE: 以下两个测试依赖 Day 2-4 的功能 (placeOrder, updateIndexPrice)
    // 已移动到 Day4PriceUpdate.t.sol:
    // - testWithdrawWhilePositionOpenUsesFreshPrice
    // - testWithdrawWithExcessMarginAllowed
}
