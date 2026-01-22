# Monad Perp Exchange - 永续合约交易所

> ⚠️ **本项目为技术展示作品，仅供学习参考，不可用于生产环境。**

基于 Monad 链构建的完整永续合约交易所，采用模块化架构设计，实现了 DeFi 协议的所有核心功能。

---

## 📋 目录

- [项目概述](#项目概述)
- [核心特性](#核心特性)
- [技术架构](#技术架构)
- [功能模块](#功能模块)
- [快速开始](#快速开始)
- [项目结构](#项目结构)
- [核心实现](#核心实现)
- [部署说明](#部署说明)
- [技术亮点](#技术亮点)
- [许可证](#许可证)

---

## 🎯 项目概述

这是一个**生产级永续合约交易所的完整实现**，涵盖了从智能合约到前端界面的全栈开发。项目采用现代化的技术栈和模块化设计，实现了永续合约交易的所有核心功能。

### 什么是永续合约？

永续合约（Perpetual Futures）是一种无需到期交割的衍生品合约，通过**资金费率机制**来锚定现货价格。与传统期货不同，永续合约可以无限期持有，是当前 DeFi 领域最主流的交易工具之一。

### 已实现的核心功能

- ✅ **保证金系统** - 完整的存款、取款、余额管理功能
- ✅ **订单簿引擎** - 基于双向链表的高效订单管理
- ✅ **撮合引擎** - 价格优先、时间优先的订单撮合算法
- ✅ **价格预言机** - 实时价格更新与标记价计算
- ✅ **资金费率** - 自动化的多空费率结算机制
- ✅ **清算系统** - 健康度监控与强制平仓逻辑
- ✅ **交易界面** - React 构建的现代化交易 UI
- ✅ **事件索引器** - 基于 Envio 的实时数据同步
- ✅ **自动化服务** - 价格更新、费率结算、清算监控

---

## 🌟 核心特性

### 1. 模块化合约架构

智能合约采用模块化设计，每个功能独立封装，易于维护和扩展：

```solidity
contract Exchange is
    MarginModule,
    OrderBookModule,
    PricingModule,
    FundingModule,
    LiquidationModule,
    ViewModule
{
    // 统一入口，按需调用各模块
}
```

**设计优势**：
- 职责分离，代码清晰
- 便于单元测试
- 易于功能扩展

### 2. 高效订单簿实现

使用**双向链表**实现订单簿，实现 O(1) 复杂度的订单插入和删除：

```solidity
struct Order {
    uint256 id;           // 订单 ID
    address trader;       // 交易员地址
    bool isBuy;           // 买/卖方向
    uint256 price;        // 价格（18位精度）
    uint128 amount;       // 数量
    uint256 next;         // 链表后驱指针
    uint256 prev;         // 链表前驱指针
}
```

**性能特点**：
- 价格优先级排序
- 快速订单匹配
- 支持市价单和限价单

### 3. 全栈技术实现

| 层级 | 技术栈 | 说明 |
|------|--------|------|
| **智能合约** | Solidity + Foundry | 模块化架构，完整测试覆盖 |
| **前端** | React + TypeScript + MobX | 响应式 UI，实时数据更新 |
| **构建工具** | Vite | 快速开发体验 |
| **索引器** | Envio + PostgreSQL | 事件监听，GraphQL API |
| **后端服务** | Node.js + TypeScript | Keeper 自动化服务 |

### 4. 实时数据流

```
用户操作 → 前端界面 → 智能合约调用 → 事件触发
                                    ↓
索引器监听 → PostgreSQL 存储 → GraphQL API → 前端订阅 → UI 更新
```

---

## 🏗️ 技术架构

### 系统架构图

```
┌─────────────────────────────────────────────────────┐
│                   前端层 (Frontend)                   │
│  React + TypeScript + MobX + Tailwind CSS            │
│  - 下单交易 - 持仓管理 - 实时图表 - 订单簿            │
└──────────────────┬──────────────────────────────────┘
                   ↓ GraphQL Subscription
┌─────────────────────────────────────────────────────┐
│                   索引器 (Indexer)                    │
│  Envio + PostgreSQL                                   │
│  - 事件监听 - 数据存储 - GraphQL API                 │
└──────────────────┬──────────────────────────────────┘
                   ↓ 区块链事件
┌─────────────────────────────────────────────────────┐
│                 智能合约层 (Smart Contracts)           │
│  Solidity + Foundry + OpenZeppelin                   │
│  ┌──────────────────────────────────────────┐       │
│  │  Exchange.sol (主合约)                    │       │
│  │  ├─ MarginModule (保证金)                │       │
│  │  ├─ OrderBookModule (订单簿)             │       │
│  │  ├─ PricingModule (价格)                 │       │
│  │  ├─ FundingModule (资金费率)             │       │
│  │  ├─ LiquidationModule (清算)             │       │
│  │  └─ ViewModule (查询)                    │       │
│  └──────────────────────────────────────────┘       │
└──────────────────┬──────────────────────────────────┘
                   ↑ Keeper 调用
┌──────────────────┴──────────────────────────────────┐
│              Keeper 服务 (后台自动化)                  │
│  - PriceKeeper (价格更新)                            │
│  - FundingKeeper (费率结算)                          │
│  - Liquidator (清算监控)                             │
└─────────────────────────────────────────────────────┘
```

### 技术栈详解

#### 智能合约层

| 技术 | 版本 | 说明 |
|------|------|------|
| **Solidity** | ^0.8.20 | 智能合约开发语言 |
| **Foundry** | Latest | 开发框架、测试、部署工具链 |
| **OpenZeppelin** | ^5.0 | 经过审计的安全合约库 |

#### 前端层

| 技术 | 版本 | 说明 |
|------|------|------|
| **React** | 19.2.0 | 现代化 UI 框架 |
| **TypeScript** | 5.8.3 | 类型安全保障 |
| **Vite** | 6.4.1 | 极速构建工具 |
| **MobX** | 6.15.0 | 响应式状态管理 |
| **Tailwind CSS** | Latest | 原子化 CSS 框架 |
| **viem** | 2.43.5 | 轻量级以太坊交互库 |
| **lightweight-charts** | Latest | 高性能 K线图表库 |

#### 后端服务

| 技术 | 说明 |
|------|------|
| **Node.js + TypeScript** | 服务端运行时 |
| **Envio** | 事件索引器框架 |
| **PostgreSQL** | 关系型数据库 |
| **GraphQL** | API 查询语言 |
| **viem** | 区块链交互客户端 |

---

## 🔧 功能模块

### 模块一：保证金系统

**实现文件**: `contract/src/modules/MarginModule.sol`

**核心功能**:
- 用户保证金存入 (`deposit`)
- 保证金提取 (`withdraw`)
- 实时余额查询
- 余额充足性检查

**技术要点**:
```solidity
mapping(address => uint256) public marginBalances;

function deposit(uint256 amount) external {
    marginBalances[msg.sender] += amount;
    emit Deposit(msg.sender, amount);
}
```

---

### 模块二：订单簿系统

**实现文件**: `contract/src/modules/OrderBookModule.sol`

**核心功能**:
- 限价单下单 (`placeOrder`)
- 订单撤销 (`cancelOrder`)
- 价格优先级队列
- 双向链表数据结构

**技术要点**:
- 链表插入算法 O(n)
- 链表删除算法 O(1)
- 价格聚合显示

---

### 模块三：撮合引擎

**实现文件**: `contract/src/modules/OrderBookModule.sol`

**核心功能**:
- 买卖订单自动匹配
- 持仓即时更新
- 成交价格计算
- 部分/全部成交处理

**撮合逻辑**:
```
买单价格 ≥ 卖单价格 → 触发撮合
成交价格 = 优先提交的订单价格
成交量 = min(买量, 卖量)
```

---

### 模块四：价格系统

**实现文件**: `contract/src/modules/PricingModule.sol`

**核心功能**:
- 指数价格更新 (`updateIndexPrice`)
- 标记价格计算 (`getMarkPrice`)
- 价格有效性验证
- 价格时间戳检查

**价格机制**:
```solidity
// 标记价 = 指数价格 × (1 + 价格偏差)
uint256 public markPrice;
uint256 public constant PRICE_TOLERANCE = 0.01e18;  // 1% 容差
```

---

### 模块五：资金费率

**实现文件**: `contract/src/modules/FundingModule.sol`

**核心功能**:
- 资金费率计算
- 自动费率结算
- 多空费率分配
- 费率历史记录

**费率公式**:
```solidity
// 资金费率 = (标记价 - 指数价) / 指数价
int256 fundingRate = (int256(markPrice) - int256(indexPrice)) * 1e18
                    / int256(indexPrice);

// 多头持仓支付/收取费率
// 空头持仓收取/支付费率
```

---

### 模块六：清算系统

**实现文件**: `contract/src/modules/LiquidationModule.sol`

**核心功能**:
- 账户健康度计算
- 强制平仓执行
- 清算人奖励机制
- 爆仓风险预警

**健康度公式**:
```solidity
// 健康度 = (保证金 + 未实现盈亏) / 维持保证金 × 100%
uint256 healthFactor = (margin + unrealizedPnL) * 100
                      / maintenanceMargin;

// healthFactor < 100% 时触发清算
```

---

### 模块七：前端交易界面

**实现目录**: `frontend/src/components/`

**核心组件**:

| 组件 | 功能 | 技术实现 |
|------|------|----------|
| **Header** | 钱包连接、余额显示 | Wallet Connect |
| **OrderForm** | 下单表单 | 限价单/市价单 |
| **OrderBook** | 实时订单簿 | GraphQL 订阅 |
| **Positions** | 持仓管理 | 实时 PnL 计算 |
| **MarketStats** | 市场统计 | 资金费率、24h涨跌 |
| **TradingChart** | K线图 | lightweight-charts |
| **Leaderboard** | 交易排行榜 | 收益率排序 |

---

## 🚀 快速开始

### 环境要求

| 工具 | 版本要求 | 说明 |
|------|---------|------|
| **Foundry** | Latest | `curl -L https://foundry.paradigm.xyz \| bash` |
| **Node.js** | >= 18.0 | [nodejs.org](https://nodejs.org/) |
| **pnpm** | >= 8.0 | `npm install -g pnpm` |
| **Git** | Latest | [git-scm.com](https://git-scm.com/) |

### 一键启动

```bash
# 克隆项目
git clone https://github.com/LPigeonIA/Monad_PerpM.git
cd Monad_PerpM

# 运行快速启动脚本
./quickstart.sh
```

**脚本自动执行**:
1. ✅ 启动 Anvil 本地测试链
2. ✅ 编译并部署智能合约
3. ✅ 安装前端依赖
4. ✅ 配置环境变量
5. ✅ 启动前端开发服务器

### 手动部署

#### 1. 合约部署

```bash
cd contract

# 安装依赖
forge install

# 编译合约
forge build

# 启动本地链（终端1）
anvil --host 0.0.0.0 --port 8545

# 部署合约（终端2）
forge script script/DeployExchange.s.sol \
  --rpc-url http://localhost:8545 \
  --broadcast
```

#### 2. 前端启动

```bash
cd frontend

# 配置环境变量
cp .env.example .env.local
# 编辑 .env.local，填入合约地址

# 安装依赖
npm install

# 启动开发服务器
npm run dev
```

访问: http://localhost:5173

#### 3. 索引器启动（可选）

```bash
cd indexer

# 安装依赖
pnpm install

# 配置合约地址（config.yaml）

# 启动索引器
pnpm start
```

#### 4. Keeper 服务（可选）

```bash
cd keeper

# 安装依赖
npm install

# 配置环境变量
cp .env.example .env

# 启动 Keeper
npm start
```

---

## 📁 项目结构

```
Monad_PerpM/
├── contract/                    # 智能合约
│   ├── src/
│   │   ├── core/
│   │   │   └── ExchangeStorage.sol      # 核心数据结构
│   │   ├── modules/
│   │   │   ├── MarginModule.sol         # 保证金模块
│   │   │   ├── OrderBookModule.sol      # 订单簿模块
│   │   │   ├── PricingModule.sol        # 价格模块
│   │   │   ├── FundingModule.sol        # 资金费率模块
│   │   │   ├── LiquidationModule.sol    # 清算模块
│   │   │   └── ViewModule.sol           # 查询模块
│   │   └── Exchange.sol                 # 主合约
│   ├── test/                            # 测试用例
│   │   ├── Day1Margin.t.sol             # 保证金测试
│   │   ├── Day2Orderbook.t.sol          # 订单簿测试
│   │   ├── Day3Matching.t.sol           # 撮合测试
│   │   ├── Day4PriceUpdate.t.sol        # 价格测试
│   │   ├── Day6Funding.t.sol            # 费率测试
│   │   ├── Day6Liquidation.t.sol        # 清算测试
│   │   └── Day7Integration.t.sol        # 集成测试
│   └── script/                           # 部署脚本
│
├── frontend/                   # React 前端
│   ├── src/components/
│   │   ├── Header.tsx                 # 顶部栏
│   │   ├── OrderForm.tsx              # 下单表单
│   │   ├── OrderBook.tsx              # 订单簿
│   │   ├── Positions.tsx              # 持仓
│   │   ├── MarketStats.tsx            # 市场统计
│   │   ├── TradingChart.tsx           # K线图
│   │   └── Leaderboard.tsx            # 排行榜
│   ├── store/
│   │   ├── exchangeStore.tsx          # MobX 状态
│   │   └── IndexerClient.ts           # 索引器客户端
│   └── onchain/                       # 合约交互
│       ├── client.ts
│       ├── config.ts
│       └── abi.ts
│
├── indexer/                    # Envio 索引器
│   ├── src/EventHandlers.ts             # 事件处理
│   ├── schema.graphql                   # GraphQL Schema
│   └── config.yaml                      # 配置
│
├── keeper/                      # Keeper 服务
│   ├── src/services/
│   │   ├── PriceKeeper.ts            # 价格更新
│   │   ├── FundingKeeper.ts          # 费率结算
│   │   └── Liquidator.ts             # 清算监控
│   └── client.ts                      # RPC 客户端
│
├── scripts/                    # 运行脚本
│   ├── quickstart.sh                     # 一键启动
│   ├── start.sh                          # 启动所有服务
│   └── stop.sh                           # 停止服务
│
└── docs/                        # 技术文档
    ├── day1-guide.md   ~ day7-guide.md   # 开发指南
```

---

## 💡 核心实现

### 1. 保证金模块

```solidity
// 用户保证金存储
mapping(address => uint256) public marginBalances;

// 存款
function deposit(uint256 amount) external {
    marginBalances[msg.sender] += amount;
    emit Deposit(msg.sender, amount);
}

// 提款（检查最低保证金要求）
function withdraw(uint256 amount) external {
    require(marginBalances[msg.sender] >= amount, "Insufficient balance");
    require(_canWithdraw(msg.sender, amount), "Withdraw would exceed margin requirement");
    marginBalances[msg.sender] -= amount;
    emit Withdraw(msg.sender, amount);
}
```

### 2. 订单簿模块

```solidity
// 订单结构
struct Order {
    uint256 id;
    address trader;
    bool isBuy;
    uint256 price;
    uint128 amount;
    uint256 next;
    uint256 prev;
}

// 下单（插入链表）
function placeOrder(bool isBuy, uint256 price, uint128 amount) external returns (uint256) {
    uint256 orderId = _nextOrderId++;
    orders[orderId] = Order({
        id: orderId,
        trader: msg.sender,
        isBuy: isBuy,
        price: price,
        amount: amount,
        next: 0,
        prev: 0
    });

    _insertOrder(orderId, isBuy, price);
    emit OrderPlaced(orderId, msg.sender, isBuy, price, amount);
    return orderId;
}
```

### 3. 清算模块

```solidity
// 健康度检查
function checkHealth(address trader) public view returns (uint256) {
    Position memory position = positions[trader];

    if (position.amount == 0) {
        return type(uint256).max; // 无持仓，健康度无限
    }

    int256 pnl = _calculatePnL(trader);
    uint256 totalMargin = marginBalances[trader];

    if (pnl > 0) {
        totalMargin += uint256(pnl);
    } else {
        // 未实现亏损会减少有效保证金
        uint256 loss = uint256(-pnl);
        if (loss >= totalMargin) return 0;
        totalMargin -= loss;
    }

    uint256 maintenanceMargin = uint256(position.amount) * indexPrice / 100; // 1% 维持保证金
    return totalMargin * 100 / maintenanceMargin;
}
```

---

## 🌐 部署说明

### 本地测试网部署

```bash
# 启动 Anvil
anvil --host 0.0.0.0 --port 8545

# 部署合约
forge script script/DeployExchange.s.sol \
  --rpc-url http://localhost:8545 \
  --broadcast
```

### 公共测试网部署（Sepolia）

```bash
export RPC_URL="https://sepolia.infura.io/v3/YOUR_KEY"
export PRIVATE_KEY="your_private_key"

forge script script/DeployExchange.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_KEY
```

### Monad 测试网部署

```bash
export RPC_URL="https://testnet-rpc.monad.xyz"

forge script script/DeployExchange.s.sol \
  --rpc-url $RPC_URL \
  --broadcast
```

---

## ✨ 技术亮点

### 1. 模块化设计

采用继承式模块化架构，每个功能模块独立开发和测试，便于维护和扩展。

### 2. 高效数据结构

订单簿使用双向链表实现，相比数组存储，大幅降低 Gas 消耗和操作复杂度。

### 3. 类型安全

前端使用 TypeScript 全栈开发，配合 viem 的类型推导，实现端到端类型安全。

### 4. 实时数据流

基于 GraphQL Subscription 实现链上事件到前端的实时推送，用户体验流畅。

### 5. 完整测试覆盖

7 个测试文件覆盖所有核心功能，确保合约安全性。

---

## 📊 项目成果

### 代码统计

| 类别 | 文件数 | 说明 |
|------|--------|------|
| **Solidity 合约** | 15+ | 模块化架构 |
| **测试用例** | 7 | 完整功能覆盖 |
| **React 组件** | 10+ | 现代化 UI |
| **TypeScript 文件** | 42 | 全栈类型安全 |
| **部署脚本** | 5 | 自动化部署 |

### 功能完成度

- ✅ 保证金系统 - 100%
- ✅ 订单簿引擎 - 100%
- ✅ 撮合引擎 - 100%
- ✅ 价格预言机 - 100%
- ✅ 资金费率 - 100%
- ✅ 清算系统 - 100%
- ✅ 前端界面 - 100%
- ✅ 索引器 - 100%
- ✅ Keeper 服务 - 100%

---

## 📞 联系方式

- **作者**: LPigeonIA
- **GitHub**: [@LPigeonIA](https://github.com/LPigeonIA)
- **邮箱**: 2392554324@qq.com

---

## 📄 许可证

本项目采用 **MIT 许可证** - 详见 [LICENSE](LICENSE) 文件

---

## 🌟 展示说明

本仓库展示了我在区块链 DeFi 开发方面的技术能力，包括：

- ✅ 智能合约开发（Solidity + Foundry）
- ✅ 前端开发（React + TypeScript）
- ✅ 后端开发（Node.js + TypeScript）
- ✅ 数据库设计（PostgreSQL + GraphQL）
- ✅ 系统架构设计
- ✅ 自动化测试

如果这个项目对您有帮助，欢迎给一个 Star ⭐️

---

**Built with ❤️ by LPigeonIA**
