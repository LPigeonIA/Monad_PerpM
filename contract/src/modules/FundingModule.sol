// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "../core/ExchangeStorage.sol";

/// @notice Funding settlement and shared math helpers.
/// @dev Day 5: 资金费率计算与结算
abstract contract FundingModule is ExchangeStorage {

    /// @notice 结算全局资金费率
    /// @dev 每隔 fundingInterval 调用一次，更新 cumulativeFundingRate
    function settleFunding() public virtual {
    // Step 1: 检查是否已过 fundingInterval
    if (block.timestamp < lastFundingTime + fundingInterval) return;
    if (indexPrice == 0) return;

    // Step 2: 计算 Premium Index
    int256 mark = int256(markPrice);
    int256 index = int256(indexPrice);
    int256 premiumIndex = ((mark - index) * 1e18) / index;

    // Step 3: 应用利率和钳位
    int256 interestRate = 1e14; // 0.01%
    int256 clampRange = 5e14;   // 0.05%
    
    int256 diff = interestRate - premiumIndex;
    int256 clamped = diff;
    if (diff > clampRange) clamped = clampRange;
    if (diff < -clampRange) clamped = -clampRange;
    
    int256 rate = premiumIndex + clamped;

    // Step 4: 应用全局上限
    if (maxFundingRatePerInterval > 0) {
        if (rate > maxFundingRatePerInterval) rate = maxFundingRatePerInterval;
        if (rate < -maxFundingRatePerInterval) rate = -maxFundingRatePerInterval;
    }

    // Step 5: 累加到全局费率
    cumulativeFundingRate += rate;
    lastFundingTime = block.timestamp;

    // Step 6: 触发事件
    emit FundingUpdated(cumulativeFundingRate, block.timestamp);
}
    /// @notice 结算特定用户的资金费
    /// @param trader 用户地址
    function settleUserFunding(address trader) external virtual {
        _applyFunding(trader);
    }

    /// @notice 设置资金费率参数 (仅管理员)
    function setFundingParams(uint256 interval, int256 maxRatePerInterval) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        require(interval > 0, "interval=0");
        require(maxRatePerInterval >= 0, "cap<0");
        fundingInterval = interval;
        maxFundingRatePerInterval = maxRatePerInterval;
        emit FundingParamsUpdated(interval, maxRatePerInterval);
    }

    /// @notice 应用资金费到用户账户
    /// @dev 内部函数，计算用户应付/应收的资金费
    function _applyFunding(address trader) internal virtual {
    Account storage a = accounts[trader];
    Position storage p = a.position;
    
    // Step 1: 无持仓则更新 index 并返回
    if (p.size == 0) {
        lastFundingIndex[trader] = cumulativeFundingRate;
        return;
    }

    // Step 2: 确保全局费率最新
    settleFunding();
    
    // Step 3: 计算费率差值
    int256 diff = cumulativeFundingRate - lastFundingIndex[trader];
    if (diff == 0) return;

    // Step 4: 计算应付金额
    // Payment = Size * MarkPrice * Diff / 1e36
    int256 payment = (int256(p.size) * int256(markPrice) * diff) / 1e36;
    
    // Step 5: 更新用户保证金
    uint256 free = a.margin;
    if (payment > 0) {
        // 需要支付
        uint256 pay = uint256(payment);
        if (pay > free) {
            // debt 情况：margin 不足，全部扣除
            a.margin = 0;
        } else {
            a.margin = free - pay;
        }
    } else if (payment < 0) {
        // 获得收入
        uint256 credit = uint256(-payment);
        a.margin = free + credit;
    }
    
    // Step 6: 更新用户费率 index
    lastFundingIndex[trader] = cumulativeFundingRate;
    
    // Step 7: 触发事件
    emit FundingPaid(trader, payment);
}

    /// @notice 计算未实现盈亏
    /// @param p 持仓结构体
    /// @return 未实现盈亏 (可为负)
    function _unrealizedPnl(Position memory p) internal view returns (int256) {
        return _unrealizedPnlAtPrice(p, markPrice);
    }

    /// @notice 在指定价格下计算未实现盈亏
    function _unrealizedPnlAtPrice(Position memory p, uint256 price) internal pure returns (int256) {
        if (p.size == 0) return 0;
        int256 priceDiff = int256(price) - int256(p.entryPrice);
        if (p.size < 0) priceDiff = -priceDiff;
        return (priceDiff * int256(SignedMath.abs(p.size))) / 1e18;
    }

    /// @notice 钩子：子模块可覆盖以在操作前拉取最新价格
    function _pullLatestPrice() internal virtual {}
}
