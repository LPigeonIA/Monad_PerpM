// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./utils/ExchangeFixture.sol";

// Day 6: 资金费率
contract Day6FundingTest is ExchangeFixture {
    function setUp() public override {
        super.setUp();
        _deposit(alice, 50_000 ether);
        _deposit(bob, 50_000 ether);
        exchange.setManualPriceMode(true);
    }

    function testFundingFlowsFromLongToShort() public {
        // 用例：mark 高于 index，long 支付、short 获得资金费
        vm.prank(alice);
        exchange.placeOrder(true, 100 ether, 200 ether, 0);
        vm.prank(bob);
        exchange.placeOrder(false, 100 ether, 200 ether, 0);

        exchange.updatePrices(150 ether, 100 ether);
        vm.warp(block.timestamp + exchange.fundingInterval());
        exchange.settleFunding();
        // Premium = (150-100)/100 = 0.5
        // Rate = 0.5 - 0.0005 = 0.4995
        int256 rate = 4995 * 1e14; 

        MonadPerpExchange.Position memory pAlice = exchange.getPosition(alice);
        console.log("Alice Size:", uint256(int256(pAlice.size)));
        console.log("Alice Margin:", exchange.margin(alice)); 

        uint256 aliceMarginBefore = exchange.margin(alice);
        uint256 bobMarginBefore = exchange.margin(bob);
        exchange.settleUserFunding(alice);
        exchange.settleUserFunding(bob);

        // Payment = Size * Mark * Rate
        // Size = 200e18. Mark = 150e18. Rate = 0.4995e18.
        // Payment = (200e18 * 150e18 * 0.4995e18) / 1e36 = 30000e18 * 0.4995 = 14985e18
        uint256 payment = 14985 ether;
        assertEq(exchange.margin(alice), aliceMarginBefore - payment, "long pays funding");
        assertEq(exchange.margin(bob), bobMarginBefore + payment, "short receives funding");
    }

    function testSettleFundingNoIndexPriceSkips() public {
        // 用例：指数价为 0 时不应累积资金费
        uint256 tsBefore = exchange.lastFundingTime();
        exchange.updatePrices(120 ether, 0);
        vm.warp(block.timestamp + exchange.fundingInterval());
        exchange.settleFunding();
        assertEq(exchange.cumulativeFundingRate(), 0, "no funding without index price");
        assertEq(exchange.lastFundingTime(), tsBefore, "timestamp unchanged");
    }

    function testFundingAccumulatesAcrossIntervals() public {
        // 用例：跨多个 interval 应累加资金费并推进时间戳
        exchange.updatePrices(200 ether, 100 ether); // mark premium 100%
        uint256 start = exchange.lastFundingTime();
        
        // Loop 3 times
        for(uint256 i=0; i<3; i++) {
            vm.warp(block.timestamp + exchange.fundingInterval());
            exchange.settleFunding();
        }

        // Premium = (200-100)/100 = 1.0
        // Rate = 1.0 - 0.0005 = 0.9995
        int256 expected = int256(3) * int256(9995 * 1e14);
        assertEq(exchange.cumulativeFundingRate(), expected, "funding adds per interval");
        assertEq(exchange.lastFundingTime(), start + 3 * exchange.fundingInterval(), "advance timestamp by intervals");
    }

    function testFundingSequentialEntrantsAccruesCorrectly() public {
        // 用例：多用户分批进入/退出，资金费率按各自上次指数结算
        // Reduce sizes to avoid bankruptcy
        uint256 sizeA = 10 ether;
        uint256 sizeC = 5 ether;
        uint256 price = 100 ether;

        _deposit(carol, 100_000 ether);

        // A 与 B 建仓：A 多、B 空
        vm.prank(alice);
        exchange.placeOrder(true, price, sizeA, 0);
        vm.prank(bob);
        exchange.placeOrder(false, price, sizeA, 0);

        // 第一次资金费率：mark=150,index=100
        // Premium = 0.5. Rate = 0.4995.
        exchange.updatePrices(150 ether, 100 ether);
        vm.warp(block.timestamp + exchange.fundingInterval());
        exchange.settleFunding();
        int256 r1 = 4995 * 1e14; // 49.95%

        uint256 aBefore = exchange.margin(alice);
        uint256 bBefore = exchange.margin(bob);
        exchange.settleUserFunding(alice);
        exchange.settleUserFunding(bob);
        // Payment = 10 * 150 * 0.4995 = 749.25
        uint256 pay1 = 74925 * 1e16; // 749.25 ether
        assertEq(exchange.margin(alice), aBefore - pay1, "A pays r1");
        assertEq(exchange.margin(bob), bBefore + pay1, "B receives r1");

        // 第二次资金费率：mark=200,index=100
        // Premium = 1.0. Rate = 0.9995.
        exchange.updatePrices(200 ether, 100 ether);
        vm.warp(block.timestamp + exchange.fundingInterval());
        exchange.settleFunding();
        int256 r2 = 9995 * 1e14;

        aBefore = exchange.margin(alice);
        bBefore = exchange.margin(bob);
        exchange.settleUserFunding(alice);
        exchange.settleUserFunding(bob);
        // Payment = 10 * 200 * 0.9995 = 1999
        uint256 pay2 = 1999 ether;
        assertEq(exchange.margin(alice), aBefore - pay2, "A pays r2");
        assertEq(exchange.margin(bob), bBefore + pay2, "B receives r2");

        // C 此时加入，与 B 再撮合 500
        vm.prank(carol);
        exchange.placeOrder(true, price, sizeC, 0);
        vm.prank(bob);
        exchange.placeOrder(false, price, sizeC, 0);

        // 第三次资金费率：mark=300,index=100
        // Premium = 2.0. Rate = 1.9995.
        exchange.updatePrices(300 ether, 100 ether);
        vm.warp(block.timestamp + exchange.fundingInterval());
        exchange.settleFunding();
        int256 r3 = 19995 * 1e14;

        aBefore = exchange.margin(alice);
        bBefore = exchange.margin(bob);
        uint256 cBefore = exchange.margin(carol);

        exchange.settleUserFunding(alice);
        exchange.settleUserFunding(bob);
        exchange.settleUserFunding(carol);

        // Payment A = 10 * 300 * 1.9995 = 5998.5
        // Payment C = 5 * 300 * 1.9995 = 2999.25
        uint256 pay3A = 59985 * 1e17; // 5998.5
        uint256 pay3C = 299925 * 1e16; // 2999.25
        uint256 pay3B = pay3A + pay3C;

        assertEq(exchange.margin(alice), aBefore - pay3A, "A pays r3");
        assertEq(exchange.margin(carol), cBefore - pay3C, "C pays r3");
        assertEq(exchange.margin(bob), bBefore + pay3B, "B receives r3 from A+C");
    }

    function testFundingCapAndIntervalChange() public {
        // 设置 30 分钟 interval 和每 interval 上限 0.05 (5%/interval) -> 5e16
        exchange.setFundingParams(30 minutes, 5e16);

        vm.prank(alice);
        exchange.placeOrder(true, 100 ether, 100 ether, 0);
        vm.prank(bob);
        exchange.placeOrder(false, 100 ether, 100 ether, 0);

        exchange.updatePrices(500 ether, 100 ether); // diff/index = 4, rateRaw=4/24=0.166... => 会被 cap
        vm.warp(block.timestamp + 30 minutes);
        exchange.settleFunding();
        int256 capped = 5e16;
        assertEq(exchange.cumulativeFundingRate(), capped, "capped per interval");

        // 再走一轮，累计应 2 * capped
        vm.warp(block.timestamp + 30 minutes);
        exchange.settleFunding();
        assertEq(exchange.cumulativeFundingRate(), capped * 2, "capped again with new interval");
    }

    function testFundingShortPaysWhenMarkBelowIndex() public {
        // 用例：mark < index，空头支付资金费给多头
        vm.prank(alice);
        exchange.placeOrder(true, 100 ether, 100 ether, 0);
        vm.prank(bob);
        exchange.placeOrder(false, 100 ether, 100 ether, 0);

        exchange.updatePrices(80 ether, 100 ether); // mark discount
        vm.warp(block.timestamp + exchange.fundingInterval());
        exchange.settleFunding();
        int256 rate = exchange.cumulativeFundingRate();
        // Premium = (80-100)/100 = -0.2
        // Rate = -0.2 + 0.0005 = -0.1995
        int256 expectedRate = -1995 * 1e14;
        assertEq(rate, expectedRate, "rate calculation");

        uint256 marginALong = exchange.margin(alice);
        uint256 marginBShort = exchange.margin(bob);
        exchange.settleUserFunding(alice);
        exchange.settleUserFunding(bob);

        // Payment = Size * Mark * Rate
        // 100 * 80 * (-0.1995) = -1596
        uint256 payment = 1596 ether;
        assertEq(exchange.margin(alice), marginALong + payment, "long receives funding");
        assertEq(exchange.margin(bob), marginBShort - payment, "short pays funding");
    }

    // ============ _ensureWithdrawKeepsMaintenance 测试 ============
    // maintenanceMarginBps = 50 (0.5%)
    // maintenance = positionValue * 50 / 10_000 = positionValue * 0.005

    function testWithdrawNoPositionAllowsFullWithdrawal() public {
        // 用例：无持仓时可以全部提取
        // setUp 中 alice 已存入 50_000 ether，没有开仓
        uint256 balance = exchange.margin(alice);
        assertEq(balance, 50_000 ether, "initial margin");

        vm.prank(alice);
        exchange.withdraw(balance);

        assertEq(exchange.margin(alice), 0, "can withdraw all without position");
    }

    function testWithdrawWithProfitablePositionSuccess() public {
        // 用例：有盈利持仓时，考虑未实现盈亏后仍满足维持保证金，提取成功
        // alice 开多头 100 size @ 100 价格，bob 作为对手方
        vm.prank(alice);
        exchange.placeOrder(true, 100 ether, 100 ether, 0);
        vm.prank(bob);
        exchange.placeOrder(false, 100 ether, 100 ether, 0);

        // 价格涨到 150，alice 有未实现盈利
        exchange.updatePrices(150 ether, 150 ether);
        // unrealizedPnl = (150 - 100) * 100 = 5,000 ether
        // positionValue = 150 * 100 = 15,000 ether
        // maintenance = 15,000 * 0.5% = 75 ether
        // marginBalance after withdraw 5000 = (50000 - 5000) + 5000 = 50,000 >> 75 ✓

        uint256 withdrawAmount = 5_000 ether;
        vm.prank(alice);
        exchange.withdraw(withdrawAmount);

        assertEq(exchange.margin(alice), 50_000 ether - withdrawAmount, "withdraw succeeds with profitable position");
    }

    function testWithdrawRevertsWhenWouldTriggerLiquidation() public {
        // 用例：提取后 marginBalance < maintenance，应该 revert
        vm.prank(alice);
        exchange.placeOrder(true, 100 ether, 100 ether, 0);
        vm.prank(bob);
        exchange.placeOrder(false, 100 ether, 100 ether, 0);

        // 价格跌到 80，alice 有未实现亏损
        exchange.updatePrices(80 ether, 80 ether);
        // unrealizedPnl = (80 - 100) * 100 = -2,000 ether
        // positionValue = 80 * 100 = 8,000 ether
        // maintenance = 8,000 * 0.5% = 40 ether
        // marginBalance = 50,000 - withdraw - 2,000 = 48,000 - withdraw
        // 需要 withdraw > 47,960 使得 marginBalance < 40

        uint256 withdrawAmount = 48_000 ether;
        // marginBalance = 50,000 - 48,000 + (-2,000) = 0 < 40 → revert
        vm.prank(alice);
        vm.expectRevert("withdraw would trigger liquidation");
        exchange.withdraw(withdrawAmount);
    }

    function testWithdrawAtExactMaintenanceBoundary() public {
        // 用例：刚好在维持保证金边界时，提取成功
        vm.prank(alice);
        exchange.placeOrder(true, 100 ether, 100 ether, 0);
        vm.prank(bob);
        exchange.placeOrder(false, 100 ether, 100 ether, 0);

        exchange.updatePrices(80 ether, 80 ether);
        // unrealizedPnl = -2,000 ether
        // maintenance = 40 ether
        // marginBalance = 50,000 - withdraw - 2,000 = 40
        // withdraw = 47,960 ether

        uint256 withdrawAmount = 47_960 ether;
        vm.prank(alice);
        exchange.withdraw(withdrawAmount);

        assertEq(exchange.margin(alice), 50_000 ether - withdrawAmount, "withdraw at exact boundary succeeds");
    }

    function testWithdrawOneWeiBelowMaintenanceReverts() public {
        // 用例：比维持保证金少 1 wei 时，应该 revert
        vm.prank(alice);
        exchange.placeOrder(true, 100 ether, 100 ether, 0);
        vm.prank(bob);
        exchange.placeOrder(false, 100 ether, 100 ether, 0);

        exchange.updatePrices(80 ether, 80 ether);
        // 边界是 47,960 ether，多提 1 wei 应该 revert
        // marginBalance = 40 - 1 wei < 40 → revert

        uint256 withdrawAmount = 47_960 ether + 1;
        vm.prank(alice);
        vm.expectRevert("withdraw would trigger liquidation");
        exchange.withdraw(withdrawAmount);
    }
}
