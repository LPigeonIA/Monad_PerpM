// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ExchangeStorage
/// @notice 永续合约交易所的共享状态、结构体、事件和角色定义
/// @dev 所有模块继承此合约以共享存储布局
abstract contract ExchangeStorage is AccessControl, ReentrancyGuard {
    
    // ============================================
    // 角色定义
    // ============================================
    
    /// @notice 操作员角色，可以更新价格
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ============================================
    // 常量配置
    // ============================================
    
    /// @notice 抵押品符号 (Monad 原生代币)
    string public constant COLLATERAL_SYMBOL = "MON";
    
    /// @notice 抵押品精度
    uint8 public constant COLLATERAL_DECIMALS = 18;

    // ============================================
    // 数据结构
    // ============================================

    /// @notice 订单结构体
    /// @dev 使用链表存储，next 指向下一个订单 ID
    struct Order {
        uint256 id;           // 订单 ID
        address trader;       // 交易者地址
        bool isBuy;           // 是否为买单
        uint256 price;        // 价格 (1e18 精度)
        uint256 amount;       // 剩余数量 (1e18 精度)
        uint256 initialAmount;// 初始数量
        uint256 timestamp;    // 创建时间戳
        uint256 next;         // 链表中下一个订单 ID
    }

    /// @notice 持仓结构体
    struct Position {
        int256 size;          // 持仓数量 (正=多头, 负=空头)
        uint256 entryPrice;   // 入场价格 (加权平均)
    }

    /// @notice 账户结构体
    struct Account {
        uint256 margin;       // 账户保证金 (MON)
        Position position;    // 用户持仓
    }

    // ============================================
    // 订单簿状态
    // ============================================

    /// @notice 订单存储 (订单ID => 订单)
    mapping(uint256 => Order) public orders;
    
    /// @notice 最优买单 ID (链表头)
    uint256 public bestBuyId;
    
    /// @notice 最优卖单 ID (链表头)
    uint256 public bestSellId;
    
    /// @notice 订单 ID 计数器
    uint256 internal orderIdCounter;

    // ============================================
    // 账户状态
    // ============================================

    /// @notice 用户账户 (地址 => 账户)
    mapping(address => Account) internal accounts;
    
    /// @notice 用户挂单数量 (用于限制最大挂单数)
    mapping(address => uint256) public pendingOrderCount;

    // ============================================
    // 资金费率状态
    // ============================================

    /// @notice 累计资金费率 (1e18 精度)
    int256 public cumulativeFundingRate;
    
    /// @notice 用户上次结算时的资金费率指数
    mapping(address => int256) public lastFundingIndex;
    
    /// @notice 上次资金费率结算时间
    uint256 public lastFundingTime;
    
    /// @notice 标记价格 (1e18 精度)
    uint256 public markPrice;
    
    /// @notice 指数价格 (1e18 精度)
    uint256 public indexPrice;
    
    /// @notice 资金费率结算间隔 (默认 1 小时)
    uint256 public fundingInterval = 1 hours;
    
    /// @notice 每个周期最大资金费率 (0 表示无上限, 1e18 精度)
    int256 public maxFundingRatePerInterval;

    // ============================================
    // 风控参数
    // ============================================

    /// @notice 初始保证金率 (基点, 100 = 1%, 支持最高 100 倍杠杆)
    uint256 public initialMarginBps = 100;
    
    /// @notice 维持保证金率 (基点, 50 = 0.5%)
    uint256 public maintenanceMarginBps = 50;
    
    /// @notice 清算费率 (基点, 125 = 1.25%)
    uint256 public liquidationFeeBps = 125;
    
    /// @notice 最小清算奖励 (激励清算者)
    uint256 public minLiquidationFee = 0.01 ether;
    
    /// @notice 每用户最大挂单数 (简化最坏情况保证金计算)
    uint256 public constant MAX_PENDING_ORDERS = 100;

    // ============================================
    // 事件定义
    // ============================================

    /// @notice 保证金充值事件
    event MarginDeposited(address indexed trader, uint256 amount);
    
    /// @notice 保证金提现事件
    event MarginWithdrawn(address indexed trader, uint256 amount);
    event Liquidated(address indexed trader, address indexed liquidator, uint256 amount, uint256 reward);
    
    /// @notice 订单创建事件
    event OrderPlaced(uint256 indexed id, address indexed trader, bool isBuy, uint256 price, uint256 amount);
    
    /// @notice 订单移除事件 (成交或取消)
    event OrderRemoved(uint256 indexed id);
    
    /// @notice 成交事件
    event TradeExecuted(
        uint256 indexed buyOrderId,
        uint256 indexed sellOrderId,
        uint256 price,
        uint256 amount,
        address buyer,
        address seller
    );
    
    /// @notice 标记价格更新事件
    event MarkPriceUpdated(uint256 markPrice, uint256 indexPrice);
    
    /// @notice 资金费率更新事件
    event FundingUpdated(int256 cumulativeFundingRate, uint256 timestamp);
    
    /// @notice 资金费率参数更新事件
    event FundingParamsUpdated(uint256 interval, int256 maxRatePerInterval);
    
    /// @notice 资金费支付事件
    event FundingPaid(address indexed trader, int256 amount);

    /// @notice 操作员更新事件
    event OperatorUpdated(address operator);
    
    /// @notice 已实现盈亏事件 (Day 7 Addon)
    event RealizedPnl(address indexed trader, int256 pnl, uint256 closePrice, uint256 amount);

    /// @notice 持仓更新事件
    event PositionUpdated(address indexed trader, int256 size, uint256 entryPrice);
}
