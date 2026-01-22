# Monad Perp Exchange 课程

> ⚠️ 本仓库仅供教学与练习，不可用于生产环境。

基于 Monad 的永续合约交易所开发教程，覆盖完整的 DeFi 协议开发流程。

## 🎯 课程概览

7 天渐进式学习路径，从基础到完整系统：

| Day | 主题 | 核心内容 |
|-----|------|----------|
| **Day 1** | 保证金系统 | `deposit`, `withdraw`, 余额管理 |
| **Day 2** | 订单簿结构 | 链表实现, `placeOrder`, 价格优先级 |
| **Day 3** | 撮合引擎 | 买卖匹配, 持仓更新, PnL 计算 |
| **Day 4** | 价格预言机 | `updateIndexPrice`, 标记价计算 |
| **Day 5** | 资金费率 | Funding Rate 公式, 多空结算 |
| **Day 6** | 清算系统 | 健康度检查, 强制平仓, 奖励机制 |
| **Day 7** | 集成测试 | 端到端流程验证 |

## 📁 项目结构

```
├── contract/          # Solidity 智能合约 (Foundry)
│   ├── src/           # 主合约和模块
│   └── test/          # Day1-7 测试用例
├── frontend/          # React 交易界面
├── indexer/           # Envio 事件索引器
├── keeper/            # 价格更新 & 清算服务
├── scripts/           # 部署和运行脚本
└── docs/              # 课程文档
```

## 🚀 快速开始

### 前提条件

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, anvil)
- [Node.js](https://nodejs.org/) >= 18
- [pnpm](https://pnpm.io/) (可选，用于 indexer)

### 一键启动

```bash
# 启动本地链 + 部署合约 + 前端
./quickstart.sh
```

### 手动运行

```bash
# 1. 安装合约依赖
cd contract && forge install

# 2. 运行测试
forge test

# 3. 按 Day 运行特定测试
forge test --match-contract Day1MarginTest -vvv
forge test --match-contract Day2OrderbookTest -vvv
# ... Day3-7
```

## 🖥️ 前端界面

React + Vite 构建的交易界面，包含以下组件：

| 组件 | 功能 |
|------|------|
| **Header** | 钱包连接、余额显示 |
| **OrderForm** | 下单表单（买/卖、价格、数量） |
| **OrderBook** | 实时订单簿（买卖盘） |
| **Positions** | 持仓管理、PnL 显示 |
| **MarketStats** | 市场统计、资金费率 |
| **TradingChart** | K线图（占位） |

### 前端运行

```bash
cd frontend
cp .env.example .env.local  # 配置环境变量
npm install
npm run dev
```

### 环境变量

```env
VITE_RPC_URL=http://127.0.0.1:8545
VITE_CHAIN_ID=31337
VITE_EXCHANGE_ADDRESS=0x<部署后的合约地址>
```

## 📖 测试驱动学习

每个 Day 的测试文件对应一个功能模块：

```bash
# Day 1: 保证金存取
forge test --match-contract Day1MarginTest -vvv

# Day 2: 订单簿插入与优先级
forge test --match-contract Day2OrderbookTest -vvv

# Day 3: 撮合与持仓
forge test --match-contract Day3MatchingTest -vvv

# Day 4: 价格更新
forge test --match-contract Day4PriceUpdateTest -vvv

# Day 5: 资金费率
forge test --match-contract Day5FundingTest -vvv

# Day 6: 清算机制
forge test --match-contract Day6LiquidationTest -vvv

# Day 7: 端到端集成
forge test --match-contract Day7IntegrationTest -vvv
```

## 🏗️ 核心模块

| 模块 | 文件 | 职责 |
|------|------|------|
| **MarginModule** | `src/modules/MarginModule.sol` | 保证金存取、余额检查 |
| **OrderBookModule** | `src/modules/OrderBookModule.sol` | 订单簿链表、插入/删除 |
| **PricingModule** | `src/modules/PricingModule.sol` | 标记价、指数价更新 |
| **FundingModule** | `src/modules/FundingModule.sol` | 资金费率计算与结算 |
| **LiquidationModule** | `src/modules/LiquidationModule.sol` | 健康度检查、强制平仓 |

## 📚 学习资源

- [课程大纲](docs/outline.md)
- [保证金计算说明](docs/margin_calculation_explained.md)
- [资金费率问题分析](docs/funding_rate_issue.md)

## ⚠️ 声明

本项目仅用于教学目的，包含以下简化：

- 使用简化的资金费率公式
- 无时间加权平均价格 (TWAP)
- 无保险基金机制
- 单一交易对
- 测试私钥为 Anvil 公开默认值

**请勿用于真实资金交易。**

## License

MIT
