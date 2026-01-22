// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/Exchange.sol";

contract MonadPerpExchangeHarness is MonadPerpExchange {
    constructor() MonadPerpExchange() {}

    bool public manualPriceMode;

    function setManualPriceMode(bool _mode) external {
        manualPriceMode = _mode;
    }

    function updatePrices(uint256 mark, uint256 index) external {
        markPrice = mark;
        indexPrice = index;
    }

    function _pullLatestPrice() internal virtual override {
        if (!manualPriceMode) {
            super._pullLatestPrice();
        }
        // If manual mode, do nothing (preserve manually set prices)
    }

    function _calculateMarkPrice(uint256 indexPrice_) internal view override returns (uint256) {
        if (manualPriceMode) {
            return markPrice;
        }
        return super._calculateMarkPrice(indexPrice_);
    }
}
