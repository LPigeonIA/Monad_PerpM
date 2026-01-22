# Monad Perp Exchange - 永续合约交易所

> ⚠️ **本仓库仅供教学与练习，不可用于生产环境。**

基于 Monad 链的永续合约交易所完整实现，采用模块化架构设计，涵盖 DeFi 协议开发的所有核心环节。

---

## 📋 目录

- [项目简介](#项目简介)
- [核心特性](#核心特性)
- [技术架构](#技术架构)
- [7天学习路径](#7天学习路径)
- [快速开始](#快速开始)
- [项目结构详解](#项目结构详解)
- [核心模块说明](#核心模块说明)
- [部署指南](#部署指南)
- [开发指南](#开发指南)
- [常见问题](#常见问题)
- [许可证](#许可证)

---

## 🎯 项目简介

这是一个**完整的永续合约交易所教学项目**，通过 7 天渐进式学习路径，带你从零构建一个生产级的 DeFi 协议。

### 什么是永续合约？

永续合约（Perpetual Futures）是一种无需到期交割的衍生品合约，通过**资金费率机制**来锚定现货价格。与传统期货不同，永续合约可以无限期持有。

### 本项目涵盖的核心功能

- ✅ **保证金系统** - 支持多币种保证金存取
- ✅ **订单簿** - 基于链表的高效订单管理
- ✅ **撮合引擎** - 价格优先、时间优先的订单撮合
- ✅ **价格预言机** - 实时价格更新与标记价计算
- ✅ **资金费率** - 自动化的多空费率结算
- ✅ **清算系统** - 健康度监控与强制平仓
- ✅ **前端界面** - 完整的交易 UI
- ✅ **索引器** - 实时事件监听与数据同步
- ✅ **Keeper 服务** - 自动化后台任务

---

## 🌟 核心特性

### 1. 模块化架构

智能合约采用模块化设计，每个功能独立封装：

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

### 2. 高效的订单簿

使用**双向链表**实现订单簿，O(1) 复杂度的插入和删除：

```solidity
struct Order {
    uint256 id;           // 订单 ID
    address trader;       // 交易员地址
    bool isBuy;           // 买/卖方向
    uint256 price;        // 价格（18位精度）
    uint128 amount;       // 数量
    uint256 next;         // 链表指针
    uint256 prev;         // 链表指针
}
```

### 3. 完整的前后端系统

- **前端**: React + TypeScript + MobX + Vite
- **后端**: Node.js + TypeScript
- **索引器**: Envio 事件索引框架
- **Keeper**: 自动化价格更新和清算服务

### 4. 实时数据同步

通过事件监听实现链上数据与前端实时同步：

```
合约事件 → 索引器 → 数据库 → 前端订阅 → UI 更新
```

---

## 🏗️ 技术架构

### 整体架构图

```
┌─────────────────────────────────────────────────────┐
│                   前端层 (Frontend)                   │
│  React + TypeScript + MobX + Tailwind CSS            │
│  - 下单交易 - 持仓管理 - 实时图表 - 订单簿            │
└──────────────────┬──────────────────────────────────┘
                   ↓ WebSocket/REST
┌─────────────────────────────────────────────────────┐
│                   索引器 (Indexer)                    │
│  Envio + PostgreSQL                                   │
│  - 事件监听 - 数据存储 - GraphQL API                 │
└──────────────────┬──────────────────────────────────┘
                   ↓
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
                   ↑
┌──────────────────┴──────────────────────────────────┐
│              Keeper 服务 (后台自动化)                  │
│  - PriceKeeper (价格更新)                            │
│  - FundingKeeper (费率结算)                          │
│  - Liquidator (清算监控)                             │
└─────────────────────────────────────────────────────┘
```

### 技术栈详情

#### 智能合约层

| 技术 | 版本 | 用途 |
|------|------|------|
| **Solidity** | ^0.8.20 | 智能合约语言 |
| **Foundry** | Latest | 开发框架、测试、部署 |
| **OpenZeppelin** | ^5.0 | 安全合约库 |

#### 前端层

| 技术 | 版本 | 用途 |
|------|------|------|
| **React** | 19.2.0 | UI 框架 |
| **TypeScript** | 5.8.3 | 类型安全 |
| **Vite** | 6.4.1 | 构建工具 |
| **MobX** | 6.15.0 | 状态管理 |
| **Tailwind CSS** | Latest | 样式框架 |
| **viem** | 2.43.5 | 以太坊交互库 |
| **lightweight-charts** | Latest | K线图表 |

#### 后端服务

| 技术 | 用途 |
|------|------|
| **Node.js + TypeScript** | 运行时环境 |
| **Envio** | 事件索引器 |
| **PostgreSQL** | 数据存储 |
| **viem** | 区块链交互 |

---

## 📚 7天学习路径

| Day | 主题 | 核心功能 | 测试文件 |
|-----|------|----------|----------|
| **Day 1** | 保证金系统 | `deposit()`, `withdraw()`, 余额管理 | `Day1Margin.t.sol` |
| **Day 2** | 订单簿结构 | 链表实现, `placeOrder()`, 价格优先级 | `Day2Orderbook.t.sol` |
| **Day 3** | 撮合引擎 | 买卖匹配, 持仓更新, PnL 计算 | `Day3Matching.t.sol` |
| **Day 4** | 价格预言机 | `updateIndexPrice()`, 标记价计算 | `Day4PriceUpdate.t.sol` |
| **Day 5** | 资金费率 | Funding Rate 公式, 多空结算 | `Day6Funding.t.sol` |
| **Day 6** | 清算系统 | 健康度检查, 强制平仓, 奖励机制 | `Day6Liquidation.t.sol` |
| **Day 7** | 集成测试 | 端到端流程验证 | `Day7Integration.t.sol` |

### 每日学习目标

#### Day 1: 保证金系统
- 理解保证金账户的存储结构
- 实现存款和取款功能
- 编写余额检查和验证逻辑

#### Day 2: 订单簿
- 掌握链表数据结构在 Solidity 中的实现
- 实现订单插入和删除算法
- 理解价格优先级排序

#### Day 3: 撮合引擎
- 实现买卖订单匹配逻辑
- 计算并更新用户持仓
- 实现盈亏（PnL）计算

#### Day 4: 价格预言机
- 设计价格更新机制
- 计算标记价格（Mark Price）
- 实现价格有效期检查

#### Day 5: 资金费率
- 理解资金费率的经济模型
- 实现费率计算公式
- 自动化多空费率结算

#### Day 6: 清算系统
- 计算账户健康度
- 实现强制平仓逻辑
- 设计清算人激励机制

#### Day 7: 集成测试
- 端到端流程验证
- 压力测试和边界情况
- 安全性检查

---

## 🚀 快速开始

### 前置要求

确保您的系统已安装以下工具：

| 工具 | 最低版本 | 安装链接 |
|------|---------|---------|
| **Foundry** | Latest | [getfoundry.sh](https://getfoundry.sh) |
| **Node.js** | >= 18.0 | [nodejs.org](https://nodejs.org/) |
| **pnpm** | >= 8.0 | `npm install -g pnpm` |
| **Git** | Latest | [git-scm.com](https://git-scm.com/) |

### 一键启动（推荐）

```bash
# 克隆仓库
git clone https://github.com/LPigeonIA/Monad_PerpM.git
cd Monad_PerpM

# 运行快速启动脚本
./quickstart.sh
```

这个脚本会自动：
1. 启动本地 Anvil 测试链
2. 部署智能合约
3. 启动前端界面
4. 配置环境变量

### 手动安装

#### 1. 安装合约依赖

```bash
cd contract

# 安装 Foundry 依赖
forge install

# 编译合约
forge build
```

#### 2. 运行测试

```bash
# 运行所有测试
forge test

# 运行特定 Day 的测试（带详细输出）
forge test --match-contract Day1MarginTest -vvv
forge test --match-contract Day2OrderbookTest -vvv
forge test --match-contract Day3MatchingTest -vvv
```

#### 3. 部署合约到本地网络

```bash
# 终端 1: 启动 Anvil 本地链
anvil

# 终端 2: 部署合约
cd contract
forge script script/DeployExchange.s.sol --rpc-url http://localhost:8545 --broadcast
```

#### 4. 启动前端

```bash
cd frontend

# 复制环境变量文件
cp .env.example .env.local

# 编辑 .env.local，填入合约地址
# VITE_EXCHANGE_ADDRESS=<部署后的合约地址>

# 安装依赖
npm install

# 启动开发服务器
npm run dev
```

访问 http://localhost:5173 查看界面

#### 5. 启动索引器（可选）

```bash
cd indexer

# 安装依赖
pnpm install

# 配置合约地址（在 config.yaml 中）

# 启动索引器
pnpm start
```

#### 6. 启动 Keeper 服务（可选）

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

## 📁 项目结构详解

```
Monad_PerpM/
├── contract/                    # 智能合约目录
│   ├── src/
│   │   ├── core/
│   │   │   └── ExchangeStorage.sol      # 核心数据结构定义
│   │   ├── modules/
│   │   │   ├── MarginModule.sol         # 保证金模块
│   │   │   ├── OrderBookModule.sol      # 订单簿模块
│   │   │   ├── PricingModule.sol        # 价格模块
│   │   │   ├── FundingModule.sol        # 资金费率模块
│   │   │   ├── LiquidationModule.sol    # 清算模块
│   │   │   └── ViewModule.sol           # 查询模块
│   │   └── Exchange.sol                 # 主合约入口
│   ├── test/                            # 测试用例
│   │   ├── Day1Margin.t.sol
│   │   ├── Day2Orderbook.t.sol
│   │   ├── Day3Matching.t.sol
│   │   ├── Day4PriceUpdate.t.sol
│   │   ├── Day6Funding.t.sol
│   │   ├── Day6Liquidation.t.sol
│   │   ├── Day7Integration.t.sol
│   │   └── utils/                        # 测试工具
│   ├── script/                           # 部署脚本
│   │   ├── DeployExchange.s.sol
│   │   ├── SeedData.s.sol
│   │   └── Trade.s.sol
│   ├── foundry.toml                      # Foundry 配置
│   └── lib/                              # 依赖库
│
├── frontend/                   # React 前端
│   ├── src/
│   │   ├── components/                    # React 组件
│   │   │   ├── Header.tsx                 # 顶部栏（钱包连接）
│   │   │   ├── OrderForm.tsx              # 下单表单
│   │   │   ├── OrderBook.tsx              # 订单簿
│   │   │   ├── Positions.tsx              # 持仓列表
│   │   │   ├── MarketStats.tsx            # 市场统计
│   │   │   ├── TradingChart.tsx           # K线图
│   │   │   ├── RecentTrades.tsx           # 最新成交
│   │   │   └── Leaderboard.tsx            # 排行榜
│   │   ├── store/
│   │   │   ├── exchangeStore.tsx          # MobX 全局状态
│   │   │   └── IndexerClient.ts           # 索引器客户端
│   │   ├── onchain/
│   │   │   ├── client.ts                  # viem 客户端
│   │   │   ├── config.ts                  # 链配置
│   │   │   └── abi.ts                     # 合约 ABI
│   │   ├── App.tsx                        # 主应用组件
│   │   └── main.tsx                       # 入口文件
│   ├── .env.example                       # 环境变量模板
│   ├── vite.config.ts                     # Vite 配置
│   └── package.json
│
├── indexer/                    # Envio 索引器
│   ├── src/
│   │   └── EventHandlers.ts               # 事件处理器
│   ├── schema.graphql                     # GraphQL Schema
│   ├── config.yaml                        # 索引器配置
│   └── package.json
│
├── keeper/                      # Keeper 后台服务
│   ├── src/
│   │   ├── services/
│   │   │   ├── PriceKeeper.ts            # 价格更新服务
│   │   │   ├── FundingKeeper.ts          # 资金费率服务
│   │   │   └── Liquidator.ts             # 清算服务
│   │   ├── client.ts                      # RPC 客户端
│   │   └── config.ts                      # 配置
│   ├── .env                               # 环境变量
│   └── package.json
│
├── scripts/                    # 运行脚本
│   ├── quickstart.sh                     # 一键启动脚本
│   ├── start.sh                          # 启动所有服务
│   ├── stop.sh                           # 停止所有服务
│   ├── run-anvil-deploy.sh               # 启动链并部署
│   ├── seed.sh                           # 初始化测试数据
│   └── seed_leaderboard.sh               # 填充排行榜数据
│
├── docs/                        # 课程文档
│   ├── day1-guide.md
│   ├── day2-guide.md
│   ├── day3-guide.md
│   ├── day4-guide.md
│   ├── day5-guide.md
│   ├── day6-guide.md
│   └── day7-guide.md
│
├── .gitignore                   # Git 忽略文件
├── README.md                    # 本文档
└── CLAUDE.md                    # Claude Code 配置
```

---

## 🔧 核心模块说明

### 1. ExchangeStorage.sol - 核心数据结构

定义交易所的所有状态变量和核心数据结构：

```solidity
// 用户保证金账户
mapping(address => uint256) public marginBalances;

// 订单映射
mapping(uint256 => Order) public orders;

// 用户持仓
mapping(address => Position) public positions;

// 市场配置
uint256 public indexPrice;          // 指数价格
uint256 public fundingRate;         // 资金费率
uint256 public lastFundingTime;     // 上次费率结算时间
```

### 2. MarginModule.sol - 保证金模块

**功能**:
- `deposit(address token, uint256 amount)` - 存入保证金
- `withdraw(uint256 amount)` - 提取保证金
- `_checkMargin(address trader, uint256 amount)` - 内部：保证金检查

**事件**:
```solidity
event Deposit(address indexed trader, uint256 amount);
event Withdraw(address indexed trader, uint256 amount);
```

### 3. OrderBookModule.sol - 订单簿模块

**功能**:
- `placeOrder(bool isBuy, uint256 price, uint128 amount)` - 下单
- `cancelOrder(uint256 orderId)` - 撤单
- `_matchOrders(Order memory buy, Order memory sell)` - 内部：撮合订单

**数据结构**:
```solidity
struct Order {
    uint256 id;
    address trader;
    bool isBuy;
    uint256 price;
    uint128 amount;
    uint256 next;
    uint256 prev;
}

mapping(uint256 => uint256) public bestBid;  // 最高买价
mapping(uint256 => uint256) public bestAsk;  // 最低卖价
```

### 4. PricingModule.sol - 价格模块

**功能**:
- `updateIndexPrice(uint256 newPrice)` - 更新指数价格
- `getMarkPrice() public view returns (uint256)` - 获取标记价格
- `_validatePrice(uint256 price)` - 内部：价格验证

**价格机制**:
```solidity
// 标记价 = 指数价格 × (1 + 价格偏差)
uint256 public markPrice;
uint256 public constant PRICE_TOLERANCE = 0.01e18;  // 1% 容差
```

### 5. FundingModule.sol - 资金费率模块

**功能**:
- `updateFundingRate()` - 更新资金费率
- `_settleFunding(address trader)` - 内部：结算费率

**费率公式**:
```solidity
// 资金费率 = (标记价 - 指数价) / 指数价
int256 fundingRate = (int256(markPrice) - int256(indexPrice)) * 1e18 / int256(indexPrice);
```

### 6. LiquidationModule.sol - 清算模块

**功能**:
- `checkHealth(address trader)` - 检查账户健康度
- `liquidate(address trader)` - 清算不健康账户
- `_calculatePnL(address trader) internal view returns (int256)` - 计算盈亏

**健康度计算**:
```solidity
// 健康度 = (保证金 + 未实现盈亏) / 维持保证金
uint256 healthFactor = (margin + unrealizedPnL) * 100 / maintenanceMargin;
// healthFactor < 100 时可清算
```

### 7. ViewModule.sol - 查询模块

提供只读查询接口：
- `getAccount(address trader)` - 获取账户信息
- `getOrderBook(bool isBuy)` - 获取订单簿
- `getAllPositions()` - 获取所有持仓

---

## 🌐 部署指南

### 部署到本地测试网

```bash
# 1. 启动 Anvil
anvil --host 0.0.0.0 --port 8545

# 2. 部署合约
cd contract
forge script script/DeployExchange.s.sol \
  --rpc-url http://localhost:8545 \
  --broadcast \
  --verify

# 3. 记录部署的合约地址
```

### 部署到公共测试网（如 Sepolia）

```bash
# 1. 配置环境变量
export RPC_URL="https://sepolia.infura.io/v3/YOUR_INFURA_KEY"
export PRIVATE_KEY="your_private_key"

# 2. 部署合约
forge script script/DeployExchange.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_KEY
```

### 部署到 Monad 主网/测试网

```bash
# 1. 配置 Monad RPC
export RPC_URL="https://testnet-rpc.monad.xyz"

# 2. 部署
forge script script/DeployExchange.s.sol \
  --rpc-url $RPC_URL \
  --broadcast
```

---

## 💻 开发指南

### 智能合约开发

#### 编译合约

```bash
cd contract
forge build
```

#### 运行测试

```bash
# 所有测试
forge test

# 带气体报告
forge test --gas-report

# 带详细输出
forge test -vvv

# 特定测试合约
forge test --match-contract Day1MarginTest -vvv

# 特定测试函数
forge test --match-test testDeposit -vvv
```

#### 代码格式化

```bash
forge fmt
```

#### 代码覆盖率

```bash
forge coverage
```

### 前端开发

#### 启动开发服务器

```bash
cd frontend
npm run dev
```

#### 构建生产版本

```bash
npm run build
```

#### 类型检查

```bash
npm run type-check
```

### 索引器开发

#### 本地运行索引器

```bash
cd indexer
pnpm install
pnpm run dev
```

#### 生成 GraphQL Schema

```bash
pnpm run codegen
```

### Keeper 服务

#### 运行 PriceKeeper

```bash
cd keeper
npm run price-keeper
```

#### 运行 Liquidator

```bash
npm run liquidator
```

---

## 🔍 常见问题

### 1. Foundry 安装失败？

```bash
# 使用官方安装脚本
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### 2. 前端无法连接合约？

检查 `.env.local` 配置：
```env
VITE_RPC_URL=http://127.0.0.1:8545
VITE_CHAIN_ID=31337
VITE_EXCHANGE_ADDRESS=0x...  # 确保地址正确
```

### 3. 测试失败？

```bash
# 清理缓存
forge clean

# 重新编译
forge build

# 运行测试
forge test -vvv
```

### 4. 索引器无法启动？

确保 PostgresSQL 正在运行：
```bash
# macOS
brew services start postgresql

# Linux
sudo systemctl start postgresql
```

### 5. Keeper 服务报错？

检查环境变量配置：
```bash
# keeper/.env
RPC_URL=http://localhost:8545
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
EXCHANGE_ADDRESS=0x...
```

---

## 📖 学习资源

### 推荐阅读

- [Foundry 中文文档](https://book.getfoundry.sh/)
- [Solidity 官方文档](https://docs.soliditylang.org/)
- [OpenZeppelin 合约库](https://docs.openzeppelin.com/contracts/)
- [永续合约原理](https://www.binance.com/zh-CN/support/faq/what-is-perpetual-futures-contracts-360900492571)

### 相关文档

- [保证金计算说明](docs/margin_calculation_explained.md)
- [资金费率问题分析](docs/funding_rate_issue.md)

---

## ⚠️ 免责声明

本项目仅用于**教学目的**，包含以下简化：

- 使用简化的资金费率公式
- 无时间加权平均价格（TWAP）
- 无保险基金机制
- 单一交易对
- 测试私钥为 Anvil 公开默认值

**请勿将本合约用于真实资金交易。**

---

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

### 提交 PR 流程

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m '添加某个功能'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

### 代码规范

- Solidity: 遵循 [Solidity Style Guide](https://docs.soliditylang.org/en/v0.8.20/style-guide/)
- TypeScript: 使用 ESLint + Prettier
- 提交信息: 使用中文清晰描述

---

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

---

## 📞 联系方式

- 作者: **LPigeonIA**
- GitHub: [@LPigeonIA](https://github.com/LPigeonIA)
- 邮箱: 2392554324@qq.com

---

## 🌟 Star History

如果这个项目对您有帮助，请给一个 Star ⭐️

[![Star History Chart](https://api.star-history.com/svg?repos=LPigeonIA/Monad_PerpM&type=Date)](https://star-history.com/#LPigeonIA/Monad_PerpM&Date)

---

**享受学习 DeFi 开发的旅程！** 🚀
