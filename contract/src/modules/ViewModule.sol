// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../core/ExchangeStorage.sol";

/// @notice Read-only helpers for offchain consumers.
/// @dev Day 1: 这些是视图函数，用于读取合约状态
abstract contract ViewModule is ExchangeStorage {
    
    /// @notice 获取订单详情
    /// @param id 订单 ID
    /// @return 订单结构体
    function getOrder(uint256 id) external view virtual returns (Order memory) {
        return orders[id];
}
    /// @notice 获取用户账户保证金
    /// @param trader 用户地址
    /// @return 账户保证金数量
    function margin(address trader) external view virtual returns (uint256) {
        return accounts[trader].margin;
    }

    /// @notice 获取用户持仓
    /// @param trader 用户地址
    /// @return 持仓结构体
    function getPosition(address trader) external view virtual returns (Position memory) {
        return accounts[trader].position;
}

    
}
