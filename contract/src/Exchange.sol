// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./modules/OrderBookModule.sol";
import "./modules/ViewModule.sol";

/// @title MonadPerpExchange
/// @notice A minimal non-production template for a perpetual DEX on Monad-style chains.
/// @dev 功能按模块拆分，保持简单高效但未经过生产验证。
contract MonadPerpExchange is OrderBookModule, ViewModule {
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        // Initial price setup can be done via updateIndexPrice by operator
        lastFundingTime = block.timestamp;
    }

    function setOperator(address newOperator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(OPERATOR_ROLE, newOperator);
        emit OperatorUpdated(newOperator);
    }

    // _pullLatestPrice is handled by PricingModule base implementation
}
