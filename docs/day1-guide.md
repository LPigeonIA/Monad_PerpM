# Day 1 - 保证金系统（Deposit / Withdraw）

本节目标：在 `scaffold` 基线代码上实现最小可运行的保证金流，让用户可以向合约存入抵押品（MON，链原生代币）并提取，同时通过合约的 `margin()` 视图函数读到最新余额，并让 `Day1MarginTest` 通过。

---

## 1) 学习目标

完成本节后，你将能够：

- 理解合约里"保证金余额"的最小状态表示（`accounts[trader].margin`）。
- 实现 `deposit()` / `withdraw(uint256)` 的基础资金流与安全写法。
- 学会用 Foundry 测试驱动实现（TDD）：读测试 → 写最小实现 → 跑通测试。
- 在前端通过真实交易（本地 Anvil）验证余额变化。

---

## 2) 前置知识

需要你具备：

- Solidity 基础语法：`mapping`、`struct`、`msg.sender`、`msg.value`、`require`、事件（`event`/`emit`）。
- Foundry 基础：`forge test`、`vm.prank`、`vm.expectRevert`。
- 原生币金额单位：1 MON = `1e18` wei（Solidity 里常写作 `1 ether`，只是 `1e18` 的单位名；前端用 `parseEther/formatEther` 做 18 位精度转换）。

本课程约定：

- Day1 基于 `scaffold` 的起始脚手架代码；后续每一天都在前一天基础上递进。

---

## 3) 当天完成标准

- 合约：`deposit/withdraw` 可用；`margin()` 可读。
- 测试：`contract/test/Day1Margin.t.sol` 全部通过。
- 前端：无需修改，直接使用现有功能，在 UI 上完成一次充值 + 一次提现，并看到余额变化。

---

## 4) 开发步骤

### Step 1: 读测试，明确你要实现什么

打开测试文件：

- `contract/test/Day1Margin.t.sol`

你会看到核心断言（简化描述）：

- 充值后：`exchange.margin(alice)` 应增加。
- 提现后：`exchange.margin(alice)` 应减少。
- 超额提现：revert，错误信息为 `not enough margin`。
- 提现 0：revert，错误信息为 `amount=0`。

这些断言基本就定义了 Day1 的合约接口与行为。

---

### Step 2: 实现 ViewModule 的 `margin()`

目标：让前端/测试能读取保证金余额，且不再 `revert("Not implemented")`。

修改文件：

- `contract/src/modules/ViewModule.sol`

需要实现的函数：

- `margin(address trader)`：返回 `accounts[trader].margin`

> [!NOTE]
> `getOrder` 和 `getPosition` 会在后续 Day 中实现：
> - Day 2 实现 `getOrder`（订单簿需要）
> - Day 3 实现 `getPosition`（持仓更新需要）

参考实现（可直接照写）：

```solidity
function margin(address trader) external view virtual returns (uint256) {
    return accounts[trader].margin;
}
```

预期行为：

- `exchange.margin(alice)` 不再 revert，且能返回余额（wei）。

---

### Step 3: 实现 `deposit()`（增加 margin 并发事件）

修改文件：

- `contract/src/modules/MarginModule.sol`

实现要点：

- 充值就是把 `msg.value` 计入 `accounts[msg.sender].margin`
- 发出事件：`MarginDeposited(msg.sender, msg.value)`

参考实现：

```solidity
function deposit() external payable virtual nonReentrant {
    accounts[msg.sender].margin += msg.value;
    emit MarginDeposited(msg.sender, msg.value);
}
```

预期行为：

- 调用 `deposit{value: 1 ether}()` 后（`1 ether == 1e18`，课程里视为 `1 MON`），`margin(msg.sender)` 增加对应数量。

---

### Step 4: 实现 `withdraw(uint256 amount)`（最小安全提现）

同样修改：

- `contract/src/modules/MarginModule.sol`

实现要点（按顺序）：

1. `require(amount > 0, "amount=0");`
2. 先做资金费结算钩子：`_applyFunding(msg.sender);`
   - Day1 不实现资金费公式（Day5 才做），但提前放钩子，保证架构可扩展
3. 余额检查：`require(margin >= amount, "not enough margin");`
4. 维护保证金检查钩子：`_ensureWithdrawKeepsMaintenance(msg.sender, amount);`
   - Day1 不实现完整维持保证金逻辑（Day6 会补齐，见 Step 5）
5. **先扣账再转账**（防重入）：`margin -= amount;` → `call{value: amount}("")`
6. 发出事件 `MarginWithdrawn(msg.sender, amount)`

参考实现：

```solidity
function withdraw(uint256 amount) external virtual nonReentrant {
    require(amount > 0, "amount=0");
    _applyFunding(msg.sender);
    require(accounts[msg.sender].margin >= amount, "not enough margin");
    _ensureWithdrawKeepsMaintenance(msg.sender, amount);

    accounts[msg.sender].margin -= amount;
    (bool ok, ) = msg.sender.call{value: amount}("");
    require(ok, "withdraw failed");

    emit MarginWithdrawn(msg.sender, amount);
}
```

预期行为：

- 提现后 `margin()` 正确减少
- `withdraw(0)` 按指定错误信息 revert
- 超额提现按指定错误信息 revert


---

### Step 5: 前端实现 (exchangeStore.tsx)

现在轮到在前端实现代码了！`frontend/store/exchangeStore.tsx` 中有三个TODO函数需要你完成。

**修改文件**：

- `frontend/store/exchangeStore.tsx`

---

### 5.1 实现 `refresh()` 中的保证金读取

在 `refresh()` 方法中，找到这段代码（约第234行附近）：

```typescript
// ============================================
// Day 1 TODO: 读取用户保证金余额
// ============================================
const m = 0n; // TODO: 移除这行，实现上面的代码
```

替换为：

```typescript
const m = await publicClient.readContract({
  abi: EXCHANGE_ABI,
  address,
  functionName: 'margin',
  args: [this.account],
} as any) as bigint;
```

---

### 5.2 实现 `deposit()` 函数

找到 `deposit` 方法（约第328行），替换整个函数为：

```typescript
deposit = async (ethAmount: string) => {
  if (!this.walletClient || !this.account) throw new Error('Connect wallet before depositing');
  const hash = await this.walletClient.writeContract({
    account: this.account,
    chain: this.walletClient.chain,
    address: this.ensureContract(),
    abi: EXCHANGE_ABI,
    functionName: 'deposit',
    value: parseEther(ethAmount),
  } as any);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== 'success') throw new Error('Transaction failed');
  await this.refresh();
}
```

---

### 5.3 实现 `withdraw()` 函数

找到 `withdraw` 方法（约第328行），替换整个函数为：

```typescript
withdraw = async (amount: string) => {
  if (!this.walletClient || !this.account) throw new Error('Connect wallet before withdrawing');
  const parsed = parseEther(amount || '0');
  const hash = await this.walletClient.writeContract({
    account: this.account,
    chain: this.walletClient.chain,
    address: this.ensureContract(),
    abi: EXCHANGE_ABI,
    functionName: 'withdraw',
    args: [parsed],
  });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== 'success') throw new Error('Transaction failed');
  await this.refresh();
}
```

---

### 验证

修改完成后：
1. 启动前端：`cd frontend && pnpm dev`
2. 打开 http://localhost:3000
3. 点击 `Deposit` 输入 `0.1`，应该拉起钱包签名
4. 等待交易确认后，`Available` 余额应该增加
5. 点击 `Withdraw` 输入 `0.05`，余额应该减少

> [!TIP]
> `runInAction()` 在 `refresh()` 方法中已经自动处理状态更新，你不需要手动添加。

---

## 5) 解析：为什么这样写

### 5.1 margin 是什么？

`ExchangeStorage` 里有：

- `mapping(address => Account) internal accounts;`
- `Account.margin`：代表用户当前"账户保证金"（以 wei 计）

Day1 先不引入保证金检查逻辑，保持最小状态闭环。后续 Day 会通过即时计算 `_calculateWorstCaseMargin` 来验证保证金是否充足（系统不使用独立的 `lockedMargin` 字段）。

### 5.2 为什么用 `nonReentrant` + “先扣账再转账”？

`withdraw` 是典型的外部转账入口，若先转账再更新余额会留下可重入攻击面。

即使有 `nonReentrant`，也依然建议遵循：

- Checks → Effects → Interactions（检查 → 状态更新 → 外部交互）

### 5.3 为什么用 `call` 而不是 `transfer`？

`transfer` 固定 2300 gas，可能因为对方是合约地址而失败；`call` 更通用。

---

## 6) 测试与验证

### 6.1 运行合约测试

在项目根目录执行：

```bash
cd contract
forge test --match-contract Day1MarginTest -vvv
```

### 6.2 前端验证（必须）

终端 1（启动 anvil 并部署，会自动写入 `frontend/.env.local`）：

```bash
./scripts/run-anvil-deploy.sh
```

终端 2（启动前端）：

```bash
cd frontend
pnpm install
pnpm dev
```

打开：

- `http://localhost:3000`

UI 验收路径（建议按顺序）：

1. 点击右上角 `Connect Wallet`（或直接用 Header 的 Alice/Bob/Carol 按钮切换账号）
2. 在右侧面板 `Deposit` 输入 `0.1`，点击 `Deposit`
3. 等待交易确认后，`Available`（可用保证金）增加
4. 在 `Withdraw` 输入 `0.05`，点击 `Withdraw`
5. `Available` 减少，且链上交易成功
6. 输入一个明显超额的数（如 `1000`）再点 `Withdraw`，应在 UI 里看到失败（revert）

---

## 7) 常见错误与排查

1) `Day1MarginTest` 报错：`revert: Not implemented`

- 你忘了实现 `ViewModule.margin()`（或仍在 `revert("Not implemented")`）。

2) `testWithdrawZeroReverts` 失败

- `withdraw` 的 `require` 错误信息不一致：必须是 `amount=0`（大小写/空格都要一致）。

3) `testWithdrawMoreThanMarginReverts` 失败

- 余额不足的错误信息必须是 `not enough margin`。

4) 前端点击 Deposit/Withdraw 没反应或报 `Set VITE_EXCHANGE_ADDRESS`

- 你没有部署合约，或 `frontend/.env.local` 里没有正确的 `VITE_EXCHANGE_ADDRESS`。
- 优先用 `./scripts/run-anvil-deploy.sh` 自动生成。

5) 提现交易失败 `withdraw failed`

- 通常是你把扣账/转账顺序写错，或误把转账对象写错（不是 `msg.sender`）。

---

## 8) Indexer 入门：索引保证金事件

在完成合约功能后，我们需要将链上事件索引到数据库，以便前端快速查询。本课程使用 **Envio** 作为 Indexer 框架。

### Step 1: 理解 Indexer 架构

```
链上事件 (Event Logs) → Indexer 解析 → 数据库存储 → GraphQL API → 前端查询
```

配置文件位置：
- `indexer/config.yaml`：定义监听的合约和事件
- `indexer/schema.graphql`：定义数据模型
- `indexer/src/EventHandlers.ts`：事件处理逻辑

### Step 2: 配置 config.yaml

打开 `indexer/config.yaml`，配置 Indexer 监听的合约和事件：

```yaml
name: monad-exchange-indexer
description: Indexer for Monad Perpetual Exchange events

field_selection:
  transaction_fields:
    - hash

contracts:
  - name: Exchange
    handler: src/EventHandlers.ts
    events:
      - event: MarginDeposited(address indexed trader, uint256 amount)
      - event: MarginWithdrawn(address indexed trader, uint256 amount)

networks:
  - id: 31337  # Anvil local network
    start_block: 0
    rpc_config:
      url: http://127.0.0.1:8545
    contracts:
      - name: Exchange
        address:
          - 0x5FbDB2315678afecb367f032d93F642f64180aa3
```

> [!NOTE]
> - `field_selection.transaction_fields: [hash]`：配置获取交易哈希，用于 `event.transaction.hash`
> - `id: 31337` 是 Anvil 本地网络的 Chain ID
> - `rpc_config.url` 是 Anvil 的 RPC 地址（Anvil 不支持 HyperSync，需要配置 RPC）
> - `address` 需要与实际部署的合约地址一致，可在 `frontend/.env.local` 中查看
> - 后续 Day 会逐步添加更多事件（OrderPlaced、TradeExecuted 等）

### Step 3: 定义 MarginEvent Schema

打开 `indexer/schema.graphql`，添加：

```graphql
type MarginEvent @entity {
  id: ID!
  trader: String!
  amount: BigInt!
  eventType: String!  # "DEPOSIT" 或 "WITHDRAW"
  timestamp: Int!
  txHash: String!
}
```

### Step 4: 生成类型定义 (Codegen)

在编写 EventHandlers 之前，必须先根据 `config.yaml` 和 `schema.graphql` 生成 TypeScript 类型定义：

```bash
cd indexer
pnpm install
pnpm codegen
```

> [!IMPORTANT]
> 每当修改了 `config.yaml` 或 `schema.graphql`，都必须重新运行 `pnpm codegen`，否则 TypeScript 会报类型错误。

### Step 5: 实现 Event Handlers

修改 `indexer/src/EventHandlers.ts`：

```typescript
import { Exchange, MarginEvent } from "generated";

Exchange.MarginDeposited.handler(async ({ event, context }) => {
    const entity: MarginEvent = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        trader: event.params.trader,
        amount: event.params.amount,
        eventType: "DEPOSIT",
        timestamp: event.block.timestamp,
        txHash: event.transaction.hash,
    };
    context.MarginEvent.set(entity);
});

Exchange.MarginWithdrawn.handler(async ({ event, context }) => {
    const entity: MarginEvent = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        trader: event.params.trader,
        amount: event.params.amount,
        eventType: "WITHDRAW",
        timestamp: event.block.timestamp,
        txHash: event.transaction.hash,
    };
    context.MarginEvent.set(entity);
});
```

### Step 6: 启动 Indexer

```bash
cd indexer
pnpm dev
```

### Step 7: 测试 Indexer

1. **确保服务都在运行**：
   - Anvil: `./scripts/run-anvil-deploy.sh`
   - Frontend: `cd frontend && pnpm dev`
   - Indexer: `cd indexer && pnpm dev`

2. **在前端触发事件**：
   - 打开 http://localhost:3000
   - 连接钱包（Alice）
   - 执行一次 Deposit（如 0.1 ETH）
   - 执行一次 Withdraw（如 0.05 ETH）

3. **验证 GraphQL 查询**：

   **方法 A：使用 Hasura Console（推荐）**

   1. 打开 http://localhost:8080/console
   2. 输入 Admin Secret：`testing`
   3. 在 GraphiQL 标签页执行查询

   **方法 B：使用 curl 命令**

   ```bash
   curl -s -X POST http://localhost:8080/v1/graphql \
     -H "Content-Type: application/json" \
     -d '{"query":"{ MarginEvent { id trader amount eventType timestamp txHash } }"}' | jq .
   ```

   **查询语句**（在 Hasura Console 中使用）：
   ```graphql
   query {
     MarginEvent(limit: 10, order_by: {timestamp: desc}) {
       id
       trader
       amount
       eventType
       timestamp
       txHash
     }
   }
   ```

4. **预期结果**：
   - 应该看到 2 条记录：一条 `DEPOSIT`，一条 `WITHDRAW`
   - `trader` 应该是 Alice 的地址
   - `amount` 应该与你操作的金额一致（单位：wei）

> [!TIP]
> Day 1 只需确保 Indexer 能正确监听 `MarginDeposited` 和 `MarginWithdrawn` 事件。后续 Day 2-7 会逐步添加更多事件处理。

---

## 9) 小结 & 为 Day2 铺垫

今天我们完成了“资金进出 + 余额读取”这一最小闭环：

- `deposit`：增加 `margin`
- `withdraw`：做最小校验并安全转账
- `margin()`：让测试与前端能读取链上余额

Day2 会在此基础上引入"订单簿与下单"：

- `placeOrder` / `cancelOrder`
- 买卖盘链表插入、价格优先级
- 最坏情况保证金检查（挂单占用的保证金需求）

---

## 10) 可选挑战 / 扩展（不影响主线）

1. 给 `deposit/withdraw` 补事件断言
   - 在 `Day1Margin.t.sol` 新增 `vm.expectEmit(...)`，校验 `MarginDeposited` / `MarginWithdrawn` 参数。
2. 补一个“提现后 MON 余额变化”的测试
   - 用 `uint256 beforeBal = alice.balance;` → 提现 → `assertEq(alice.balance, beforeBal + amount);`
3. 代码风格
   - 跑 `forge fmt`，确保格式一致。
