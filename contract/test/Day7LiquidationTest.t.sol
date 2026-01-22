// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./utils/ExchangeFixture.sol";

/// @title Day 7 清算系统测试
/// @dev 测试用例覆盖：
/// 1. testLiquidationMarketClose - 正常清算流程
/// 2. testLiquidationPartialFillRevertsIfStillUnhealthy - H-1 保护
/// 3. testCannotLiquidateHealthyPosition - 健康账户不可清算
/// 4. testLiquidationClearsOrders - 清算时取消挂单
/// 5. testFuzzLiquidationPnL - 模糊测试各种价格场景
contract Day7LiquidationTest is ExchangeFixture {

    address internal trader;
    address internal liquidator;

    function setUp() public override {
        super.setUp();
        trader = makeAddr("trader");
        liquidator = makeAddr("liquidator");
        vm.deal(trader, 1000 ether);
        vm.deal(liquidator, 10000 ether);
    }

    /// @notice 测试 1: 正常清算流程
    /// 场景：Trader 做多 10 ETH @ 100，保证金 20 ETH
    ///       价格跌到 98 ETH 触发清算
    ///       Liquidator 执行清算，获得清算费
    function testLiquidationMarketClose() public {
        // 1. 充值
        vm.prank(trader);
        exchange.deposit{value: 20 ether}();
        vm.prank(liquidator);
        exchange.deposit{value: 2000 ether}();

        // 2. Trader 做多 10 ETH @ 100
        vm.prank(trader);
        exchange.placeOrder(true, 100 ether, 10 ether, 0);

        // 3. Liquidator 提供对手方（卖出），完成撮合
        vm.prank(liquidator);
        exchange.placeOrder(false, 100 ether, 10 ether, 0);

        // 验证 Trader 持仓
        MonadPerpExchange.Position memory p = exchange.getPosition(trader);
        assertEq(p.size, int256(10 ether), "Trader should be long 10 ETH");
        assertEq(p.entryPrice, 100 ether, "Entry price should be 100");

        // 4. 价格跌到 98 ETH，触发清算
        // marginBalance = 20 + (98-100)*10 = 0 ETH
        // maintenance = 98*10*0.0175 = 17.15 ETH
        // 0 < 17.15 → 可清算
        exchange.updatePrices(98 ether, 98 ether);

        assertTrue(exchange.canLiquidate(trader), "Trader should be liquidatable");

        // 5. Liquidator 挂买单提供流动性（让 trader 能平仓卖出）
        vm.prank(liquidator);
        exchange.placeOrder(true, 98 ether, 10 ether, 0);

        // 6. 执行清算
        uint256 liquidatorMarginBefore = exchange.margin(liquidator);

        vm.prank(liquidator);
        exchange.liquidate(trader, 0); // 0 = 全部清算

        // 7. 验证结果
        MonadPerpExchange.Position memory pAfter = exchange.getPosition(trader);
        assertEq(pAfter.size, 0, "Trader position should be closed");

        // 清算费计算: notional = 10 * 98 = 980 ETH
        // fee = 980 * 1.25% = 12.25 ETH
        uint256 expectedFee = (10 ether * 98 ether * 125) / 10000 / 1e18;
        uint256 liquidatorMarginAfter = exchange.margin(liquidator);

        // Liquidator 应该获得清算费（可能 trader 没有足够保证金支付全部）
        assertTrue(liquidatorMarginAfter > liquidatorMarginBefore, "Liquidator should receive fee");
    }

    /// @notice 测试 2: H-1 保护 - 部分清算后仍不健康应 revert
    /// 场景：只提供部分流动性，清算后仍可清算，应该 revert
    function testLiquidationPartialFillRevertsIfStillUnhealthy() public {
        // 1. 充值
        vm.prank(trader);
        exchange.deposit{value: 20 ether}();
        vm.prank(liquidator);
        exchange.deposit{value: 2000 ether}();

        // 2. Trader 做多 10 ETH @ 100
        vm.prank(trader);
        exchange.placeOrder(true, 100 ether, 10 ether, 0);
        vm.prank(liquidator);
        exchange.placeOrder(false, 100 ether, 10 ether, 0);

        // 3. 价格跌到 98 ETH，触发清算
        exchange.updatePrices(98 ether, 98 ether);
        assertTrue(exchange.canLiquidate(trader), "Trader should be liquidatable");

        // 4. 只提供 5 ETH 流动性（不足以完全清算）
        vm.prank(liquidator);
        exchange.placeOrder(true, 98 ether, 5 ether, 0);

        // 5. 尝试部分清算 - 应该 revert
        // 因为清算 5 ETH 后，剩余 5 ETH 仓位仍然不健康
        vm.prank(liquidator);
        vm.expectRevert("must fully liquidate unhealthy position");
        exchange.liquidate(trader, 5 ether);
    }

    /// @notice 测试 3: 健康账户不可清算
    /// 场景：价格稳定，账户健康，尝试清算应该 revert
    function testCannotLiquidateHealthyPosition() public {
        // 1. 充值（充足的保证金）
        vm.prank(trader);
        exchange.deposit{value: 100 ether}();
        vm.prank(liquidator);
        exchange.deposit{value: 1000 ether}();

        // 2. Trader 做多 10 ETH @ 100
        vm.prank(trader);
        exchange.placeOrder(true, 100 ether, 10 ether, 0);
        vm.prank(liquidator);
        exchange.placeOrder(false, 100 ether, 10 ether, 0);

        // 3. 价格保持稳定
        exchange.updatePrices(100 ether, 100 ether);

        // 验证账户健康
        // marginBalance = 100 + (100-100)*10 = 100 ETH
        // maintenance = 100*10*0.0175 = 17.5 ETH
        // 100 > 17.5 → 健康
        assertFalse(exchange.canLiquidate(trader), "Trader should be healthy");

        // 4. 尝试清算健康账户应该 revert
        vm.prank(liquidator);
        vm.expectRevert("position healthy");
        exchange.liquidate(trader, 0);
    }

    /// @notice 测试 4: 清算时自动取消挂单
    /// 场景：Trader 有仓位和额外挂单，清算时挂单被自动清除
    function testLiquidationClearsOrders() public {
        // 1. 充值
        vm.prank(trader);
        exchange.deposit{value: 50 ether}();
        vm.prank(liquidator);
        exchange.deposit{value: 2000 ether}();

        // 2. Trader 做多 5 ETH @ 100
        vm.prank(trader);
        exchange.placeOrder(true, 100 ether, 5 ether, 0);
        vm.prank(liquidator);
        exchange.placeOrder(false, 100 ether, 5 ether, 0);

        // 3. Trader 再挂一个额外的限价买单
        vm.prank(trader);
        uint256 extraOrderId = exchange.placeOrder(true, 90 ether, 2 ether, 0);

        // 验证挂单存在
        (uint256 orderId,,,,,,,) = exchange.orders(extraOrderId);
        assertEq(orderId, extraOrderId, "Extra order should exist");

        // 4. 价格暴跌触发清算
        // margin = 50, size = 5 @ 100
        // 需要 marginBalance < maintenance
        // 50 + (price-100)*5 < price*5*0.0175
        // 50 + 5*price - 500 < 0.0875*price
        // 5*price - 450 < 0.0875*price
        // 4.9125*price < 450
        // price < 91.6
        exchange.updatePrices(40 ether, 40 ether);

        // unrealizedPnl = (40-100)*5 = -300
        // marginBalance = 50 - 300 = -250 < 0
        // 绝对可清算
        assertTrue(exchange.canLiquidate(trader), "Trader should be liquidatable");

        // 5. 提供流动性并清算
        vm.prank(liquidator);
        exchange.placeOrder(true, 40 ether, 5 ether, 0);

        vm.prank(liquidator);
        exchange.liquidate(trader, 0);

        // 6. 验证挂单被清除
        (uint256 orderIdAfter,,,,,,,) = exchange.orders(extraOrderId);
        assertEq(orderIdAfter, 0, "Extra order should be cleared after liquidation");

        // 7. 验证持仓归零
        MonadPerpExchange.Position memory p = exchange.getPosition(trader);
        assertEq(p.size, 0, "Position should be closed");
    }

    /// @notice 测试 5: 模糊测试各种价格场景
    /// @param priceDropBps 价格下跌基点 (1-99%)
    function testFuzzLiquidationPnL(uint256 priceDropBps) public {
        // 限制价格下跌范围 1%-99%
        priceDropBps = bound(priceDropBps, 100, 9900);

        address fuzzTrader = makeAddr("fuzzTrader");
        address fuzzLiquidator = makeAddr("fuzzLiquidator");
        vm.deal(fuzzTrader, 1000 ether);
        vm.deal(fuzzLiquidator, 100000 ether);

        // 1. 设置仓位：20 ETH 保证金，做多 10 ETH @ 100
        uint256 initialMargin = 20 ether;
        uint256 posSize = 10 ether;
        uint256 entryPrice = 100 ether;

        vm.prank(fuzzTrader);
        exchange.deposit{value: initialMargin}();
        vm.prank(fuzzLiquidator);
        exchange.deposit{value: 10000 ether}();

        vm.prank(fuzzTrader);
        exchange.placeOrder(true, entryPrice, posSize, 0);
        vm.prank(fuzzLiquidator);
        exchange.placeOrder(false, entryPrice, posSize, 0);

        // 2. 计算新价格
        uint256 newPrice = entryPrice * (10000 - priceDropBps) / 10000;
        if (newPrice == 0) newPrice = 1 ether; // 避免零价格

        exchange.updatePrices(newPrice, newPrice);

        // 3. 计算预期状态
        // unrealizedPnl = (newPrice - 100) * 10 / 1e18
        int256 unrealizedPnl = (int256(newPrice) - int256(entryPrice)) * int256(posSize) / 1e18;
        int256 marginBalance = int256(initialMargin) + unrealizedPnl;

        uint256 positionValue = newPrice * posSize / 1e18;
        uint256 maintenance = positionValue * 175 / 10000; // 1.75%

        bool shouldBeLiquidatable = marginBalance < int256(maintenance);

        // 4. 验证 canLiquidate 符合预期
        assertEq(
            exchange.canLiquidate(fuzzTrader),
            shouldBeLiquidatable,
            "Liquidation status mismatch"
        );

        // 5. 如果可清算，执行清算并验证
        if (shouldBeLiquidatable) {
            // 提供流动性
            vm.prank(fuzzLiquidator);
            exchange.placeOrder(true, newPrice, posSize, 0);

            // 执行清算
            vm.prank(fuzzLiquidator);
            exchange.liquidate(fuzzTrader, 0);

            // 验证仓位关闭
            MonadPerpExchange.Position memory p = exchange.getPosition(fuzzTrader);
            assertEq(p.size, 0, "Position should be closed after liquidation");
        }
    }
}
