// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./FundingModule.sol";

/// @notice Price management (Operator updates only).
/// @dev Day 4: 价格预言机模块
abstract contract PricingModule is FundingModule {

    /// @notice 历史价格记录 (Ring Buffer 简化版)
    uint256[] public priceHistory;
    uint256 public constant HISTORY_LENGTH = 12;

    /// @notice 更新指数价格 (仅 OPERATOR_ROLE)
    /// @param newIndexPrice 新的指数价格
    function updateIndexPrice(uint256 newIndexPrice) external virtual onlyRole(OPERATOR_ROLE) {
        indexPrice = newIndexPrice;
        
        // TWAP History Logic
        if (priceHistory.length < HISTORY_LENGTH) {
            priceHistory.push(newIndexPrice);
        } else {
            // Shift left
            for (uint i = 0; i < HISTORY_LENGTH - 1; i++) {
                priceHistory[i] = priceHistory[i+1];
            }
            priceHistory[HISTORY_LENGTH - 1] = newIndexPrice;
        }

        markPrice = _calculateMarkPrice(newIndexPrice);
        emit MarkPriceUpdated(markPrice, indexPrice);
    }

    /// @notice 获取 TWAP 价格
    function getTwapPrice() public view returns (uint256) {
        if (priceHistory.length == 0) return indexPrice;
        uint256 sum = 0;
        for (uint i = 0; i < priceHistory.length; i++) {
            sum += priceHistory[i];
        }
        return sum / priceHistory.length;
    }

    /// @notice 计算标记价格
    /// @dev 使用订单簿最优价和指数价的中位数
    /// @param indexPrice_ 指数价格
    /// @return 标记价格
    function _calculateMarkPrice(uint256 indexPrice_) internal view virtual returns (uint256) {
        uint256 bestBid = bestBuyId == 0 ? 0 : orders[bestBuyId].price;
        uint256 bestAsk = bestSellId == 0 ? 0 : orders[bestSellId].price;

        // If both empty, return index
        if (bestBid == 0 && bestAsk == 0) {
            return indexPrice_;
        }

        // If one side empty, use index for that side
        if (bestBid == 0) bestBid = indexPrice_;
        if (bestAsk == 0) bestAsk = indexPrice_;

        // Median of (Bid, Ask, Index) using bubble sort
        uint256 a = bestBid;
        uint256 b = bestAsk;
        uint256 c = indexPrice_;
        
        if (a > b) (a, b) = (b, a);
        if (b > c) (b, c) = (c, b);
        if (a > b) (a, b) = (b, a);
        
        uint256 median = b;

        // ±5% Deviation Clamp
        uint256 maxDeviation = (indexPrice_ * 500) / 10_000;
        if (median > indexPrice_ + maxDeviation) return indexPrice_ + maxDeviation;
        if (indexPrice_ > maxDeviation && median < indexPrice_ - maxDeviation) return indexPrice_ - maxDeviation;

        return median;
    }

    function _pullLatestPrice() internal virtual override(FundingModule) {
        // No-op: Price is pushed by operator
    }
}
