# AGENTS.md - Agent 指南

本文档为在此仓库中工作的 AI 代理提供指南。

## 项目概述

**教学项目**（非生产环境），用于学习永续合约交易所开发。渐进式学习结构（Day 1-7）涵盖保证金、订单簿、撮合引擎、预言机、资金费率、清算和集成测试。

项目模块：
- `contract/` - Solidity 智能合约（Foundry）
- `frontend/` - React 交易界面（Vite + MobX）
- `indexer/` - Envio 事件索引器
- `keeper/` - 价格更新和清算服务（TypeScript）

## 构建与测试命令

### Smart Contracts (Foundry)
```bash
cd contract

# 运行所有测试
forge test

# 运行单个测试（按 Day）
forge test --match-contract Day1MarginTest -vvv
forge test --match-contract Day2OrderbookTest -vvv
forge test --match-contract Day3MatchingTest -vvv
forge test --match-contract Day4PriceUpdateTest -vvv
forge test --match-contract Day5FundingTest -vvv
forge test --match-contract Day6LiquidationTest -vvv
forge test --match-contract Day7IntegrationTest -vvv

# 运行单个测试函数
forge test --match-test testDepositTracksMargin -vvv

# 格式化
forge fmt
```

### Frontend (React)
```bash
cd frontend

npm install        # 安装依赖
npm run dev        # 开发服务器
npm run build      # 构建
npm run preview    # 预览构建
```

### Keeper / Indexer
```bash
cd keeper          # 手动运行 ts-node src/index.ts

cd indexer
envio codegen
envio dev         # 开发模式
envio start       # 生产模式
```

## 代码风格指南

### Solidity 合约
- **导入顺序**：OpenZeppelin → 本地模块
- **命名约定**：合约 `PascalCase`，函数 `camelCase`，内部函数 `_camelCase`，常量 `SCREAMING_SNAKE_CASE`，事件 `PascalCase`
- **文档**：NatSpec 格式（`/// @notice`, `/// @dev`, `/// @param`, `/// @return`），中文注释
- **格式化**：`forge fmt`，行宽 120 字符

### TypeScript / JavaScript
- **导入顺序**：第三方库 → 相对路径（按字母排序）
- **命名约定**：类/接口 `PascalCase`，变量/函数 `camelCase`，常量 `SCREAMING_SNAKE_CASE`，类型 `PascalCase`
- **类型系统**：严格类型检查，`import type` 显式类型导入，避免 `any`
- **ESLint**：`consistent-type-imports`，`no-unused-vars`，`n/prefer-node-protocol`，`simple-import-sort`
- **Prettier**：打印宽度 140 字符，4 空格缩进，单引号，无尾随逗号，分号必需

### React / Frontend
- **组件**：函数组件 `const Component: React.FC<Props> = () => {}`，Props 接口 `PascalCase`
- **状态管理**：MobX（`mobx`, `mobx-react-lite`），状态存储在 `store/` 目录
- **样式**：Tailwind CSS，深色模式（`bg-[#05050A]`）
- **错误处理**：React Error Boundary 包裹应用，`console.error` 记录错误

### Python
- **命名约定**：类 `PascalCase`，函数/变量 `snake_case`，常量 `SCREAMING_SNAKE_CASE`
- **Linting**：Ruff（行宽 120 字符，Python 3.10+）
- **类型检查**：Pyright 严格模式（`typeCheckingMode = "strict"`）

## 依赖管理

### 前端依赖
```bash
cd frontend

# 使用 pnpm 安装依赖
pnpm install

# 更新单个依赖到最新版本
pnpm update <package-name>@latest

# 更新所有依赖
pnpm update

# 查看过期依赖
pnpm outdated
```

### 关键依赖版本
| 依赖 | 版本 | 说明 |
|------|------|------|
| **viem** | 2.43.5 | 以太坊交互库，提供完整的 TypeScript 类型支持 |
| **react** | 19.2.0 | React 19 最新稳定版 |
| **mobx** | 6.15.0 | 状态管理库（自动更新） |
| **vite** | 6.4.1 | 构建工具（自动更新） |
| **typescript** | 5.8.3 | TypeScript 编译器（自动更新） |

### 依赖更新日志

#### 2026-01-05 - viem 升级
- **变更**：viem 从 2.21.27 升级到 2.43.5
- **原因**：改进 TypeScript 类型推断，特别是 `writeContract` 的 `chain` 参数处理
- **影响**：
  - 现在可以使用 `functionName: 'deposit' as const` 进行精确类型推断
  - WalletClient 配置的 `chain` 和 `account` 不需要在调用时重复传递
  - 减少了 `as any` 的使用，提高类型安全性
- **验证**：构建成功，所有 `writeContract` 调用通过类型检查

## 错误处理模式
- **Solidity**：`require` 前置检查，`revert` 回滚，`emit` 事件用于链下索引
- **TypeScript**：`try/catch` 块，`console.error` 记录服务错误（前缀服务名），React Error Boundary
- **Python**：`try/except` 块，异常记录日志

## 测试模式
- **Foundry**：测试文件按 Day 组织，测试合约名 `DayXModuleTest`，使用 `vm.prank`、`vm.expectRevert`，Fixture 在 `test/utils/ExchangeFixture.sol`
- **Vitest**：`describe`/`it` 结构，`expect()` 断言，`vi.doMock()`，测试文件以 `.test.ts` 或 `.test.tsx` 结尾
- **pytest**：测试文件以 `test_*.py` 命名

## 重要提示
1. **教学性质**：此仓库仅用于教学，不适用于生产环境
2. **中文注释**：Solidity 文件包含中文注释，用于教学说明
3. **TODO 标记**：许多函数标记为 `TODO`，这是课程的练习部分
4. **测试数据**：使用 Anvil 的公开测试私钥（不要在生产中使用）
5. **简化**：为了教学简化了许多机制（如资金费率公式、TWAP 等）
