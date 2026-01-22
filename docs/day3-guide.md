# Day 3 - 撮合与持仓更新（Matching & Positions）

本节目标：在 Day 2 的订单簿基础上，完成成交后的核心状态更新：撮合触发 `_executeTrade`，并正确维护 `Position.size` / `entryPrice`，将已实现盈亏直接计入 `margin`。

---

## 1) 学习目标

完成本节后，你将能够：

- 理解 maker 价成交的撮合规则（成交价来自挂在簿上的订单）。
- 实现 `_executeTrade` / `_updatePosition` 两个核心函数。
- 正确处理三种持仓更新：加仓、减仓、反向开仓。

---

## 2) 前置准备

Day3 建立在 Day2 之上，请先确认：

- Day1 / Day2 测试已通过
- 订单簿已能正确插入与撮合入口可用（`placeOrder` → `_matchBuy/_matchSell`）

你可以先跑：

```bash
cd contract
forge test --match-contract Day2OrderbookTest -vvv
```

---

## 3) 当天完成标准

- `forge test --match-contract Day3MatchingTest -vvv` 全部通过
- 部分成交后订单 `amount` 正确减少
- 双方持仓 `size` 更新正确（多头为正、空头为负）
- 反向平仓后盈亏正确结算到 `margin`

---

## 4) 开发步骤

### Step 1

打开：

- `contract/test/Day3Matching.t.sol`

你会看到四类要求：

1. **部分成交更新持仓**：成交后订单剩余数量正确
2. **价格不交叉不成交**：买价 < 最优卖价时不成交
3. **反向平仓结算 PnL**：盈亏直接更新到 `margin`
4. **taker 跨多档吃单**：多档成交后订单簿清空

---

### Step 2

当前 `_matchBuy/_matchSell` 会把成交价设为 **链表头订单的价格**：

- 买单成交：`price = bestSell.price`
- 卖单成交：`price = bestBuy.price`

因此 Day3 的 `_executeTrade` 只需使用传入的 `price`，不需要重新计算。

---

### Step 3: 实现 `getPosition`

修改：

- `contract/src/modules/ViewModule.sol`

Day 3 需要通过 `getPosition` 来查询用户持仓状态，前端和后续的清算逻辑都会用到。

参考实现：

```solidity
function getPosition(address trader) external view virtual returns (Position memory) {
    return accounts[trader].position;
}
```

预期行为：

- `exchange.getPosition(alice)` 返回 Alice 的持仓详情
- 返回结构体包含 `size`（正=多头，负=空头）、`entryPrice`

**验证命令**（使用 `cast` 查询）：

```bash
# 查询 Alice 的持仓（返回 size, entryPrice）
cast call $EXCHANGE "getPosition(address)(int256,uint256)" \
  0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --rpc-url http://127.0.0.1:8545

# 示例输出（Alice 持有 1 ETH 多头 @ 1500）：
# 1000000000000000000    ← size = 1e18 (1 ETH 多头)
# 1500000000000000000000 ← entryPrice = 1500e18
```

> [!TIP]
> **Order ≠ Position**：挂单（Order）只是等待成交的意愿；仓位（Position）是已成交的实际持仓。只有当订单被撮合后，才会更新 Position。

---

### Step 4: 实现 `_executeTrade`

修改：

- `contract/src/modules/LiquidationModule.sol`

`_executeTrade` 只做四件事：

1. 对买卖双方应用资金费（Day5 才有真实逻辑，先调用钩子）
2. 更新买方持仓
3. 更新卖方持仓
4. 触发成交事件 `TradeExecuted`

参考实现：

```solidity
function _executeTrade(
    address buyer,
    address seller,
    uint256 buyOrderId,
    uint256 sellOrderId,
    uint256 amount,
    uint256 price
) internal virtual {
    _applyFunding(buyer);
    _applyFunding(seller);

    _updatePosition(buyer, true, amount, price);
    _updatePosition(seller, false, amount, price);

    emit TradeExecuted(buyOrderId, sellOrderId, price, amount, buyer, seller);
}
```

---

### Step 5: 实现 `_updatePosition`（加仓 / 减仓 / 反向）

仍在：

- `contract/src/modules/LiquidationModule.sol`

核心规则：

- **同方向加仓**：按加权平均价更新 `entryPrice`
- **反方向减仓/平仓**：计算已实现盈亏并更新 `margin`
- **反向开仓**：完全对冲后还有剩余，则按成交价开新仓

关键公式：

- 加权平均价：`(oldSize * oldEntry + newSize * tradePrice) / (oldSize + newSize)`
- 已实现盈亏（多头）：`(tradePrice - entryPrice) * closing / 1e18`
- 已实现盈亏（空头）：`(entryPrice - tradePrice) * closing / 1e18`

参考实现：

```solidity
function _updatePosition(
    address trader,
    bool isBuy,
    uint256 amount,
    uint256 tradePrice
) internal virtual {
    Position storage p = accounts[trader].position;
    int256 signed = isBuy ? int256(amount) : -int256(amount);
    uint256 existingAbs = SignedMath.abs(p.size);

    // 1) 同方向加仓
    if (p.size == 0 || (p.size > 0) == (signed > 0)) {
        uint256 newAbs = existingAbs + amount;
        uint256 weighted = existingAbs == 0
            ? tradePrice
            : (existingAbs * p.entryPrice + amount * tradePrice) / newAbs;
        p.entryPrice = weighted;
        p.size += signed;
        emit PositionUpdated(trader, p.size, p.entryPrice);
        return;
    }

    // 2) 反向减仓/平仓
    uint256 closing = amount < existingAbs ? amount : existingAbs;
    int256 pnlPerUnit = p.size > 0
        ? int256(tradePrice) - int256(p.entryPrice)
        : int256(p.entryPrice) - int256(tradePrice);
    int256 pnl = (pnlPerUnit * int256(closing)) / int256(SCALE);

    // 盈亏直接结算到 margin（无需单独记录 realizedPnl）
    int256 newMargin = int256(accounts[trader].margin) + pnl;
    if (newMargin < 0) accounts[trader].margin = 0;
    else accounts[trader].margin = uint256(newMargin);

    // 3) 是否反向开仓
    uint256 remaining = amount - closing;
    if (closing == existingAbs) {
        if (remaining == 0) {
            p.size = 0;
            p.entryPrice = tradePrice;
        } else {
            p.size = signed > 0 ? int256(remaining) : -int256(remaining);
            p.entryPrice = tradePrice;
        }
    } else {
        if (p.size > 0) p.size -= int256(closing);
        else p.size += int256(closing);
    }
    
    // Day 5 优化：发出 PositionUpdated 事件，简化 Indexer 逻辑
    emit PositionUpdated(trader, p.size, p.entryPrice);
}
```

---

## 5) 解析：为什么这样写

### 5.1 为什么用 maker 价成交？

在订单簿交易所中，成交价通常取**被动方（maker）的挂单价格**，而非主动方（taker）的报价。原因：

- **价格发现更公平**：maker 先挂单承担了流动性风险，应该以他愿意成交的价格成交
- **防止价格操纵**：如果用 taker 价，恶意用户可以用极端价格扫单
- **符合行业惯例**：CEX（如币安、OKX）均采用 maker 价成交

在代码中体现为：

```solidity
// _matchBuy 中
_executeTrade(..., head.price);  // head 是卖单链表头，即 bestSell
```

### 5.2 加权平均价公式详解

当用户**同方向加仓**时，新的 `entryPrice` 需要按加权平均计算：

```
newEntry = (oldSize × oldEntry + addSize × tradePrice) / (oldSize + addSize)
```

示例：
- 原持仓：10 ETH @ $1000
- 加仓：5 ETH @ $1200
- 新均价：`(10×1000 + 5×1200) / 15 = 16000/15 ≈ $1066.67`

代码实现：

```solidity
uint256 weighted = (existingAbs * p.entryPrice + amount * tradePrice) / newAbs;
```

### 5.3 平仓盈亏的符号处理

盈亏方向取决于**持仓方向**与**价格变动方向**：

| 持仓方向 | 价格变动 | 盈亏 |
|---------|---------|------|
| 多头 (size > 0) | 价格上涨 | 盈利 (+) |
| 多头 (size > 0) | 价格下跌 | 亏损 (-) |
| 空头 (size < 0) | 价格下跌 | 盈利 (+) |
| 空头 (size < 0) | 价格上涨 | 亏损 (-) |

代码中用条件表达式处理：

```solidity
int256 pnlPerUnit = p.size > 0
    ? int256(tradePrice) - int256(p.entryPrice)   // 多头：卖出价 - 入场价
    : int256(p.entryPrice) - int256(tradePrice);  // 空头：入场价 - 买回价
```

### 5.4 反向开仓的边界情况

当 taker 的成交量**大于**原持仓时，会触发"反向开仓"：

1. 先平掉全部原仓位（`closing = existingAbs`）
2. 剩余量按成交价开新仓（`remaining = amount - closing`）

例如：
- 原持仓：多头 5 ETH @ $1000
- 卖出 8 ETH @ $1100
- 结果：先平 5 ETH（盈利 $500），再开空头 3 ETH @ $1100

代码分支：

```solidity
if (closing == existingAbs) {
    if (remaining == 0) { p.size = 0; }           // 刚好平仓
    else { p.size = signed > 0 ? int256(remaining) : -int256(remaining); }  // 反向开仓
}
```

### Step 6: 前端持仓实时更新

为了在 UI 上看到 Alice 和 Bob 的持仓变化，我们需要更新 `frontend/store/exchangeStore.tsx` 中的 `refresh` 函数，使其能够调用我们在 Day 1 实现的 `getPosition` 视图函数。

修改 `refresh` 方法，添加持仓读取逻辑：

```typescript
// 在 refresh() 方法中，替换现有的 position 读取代码
refresh = async () => {
    try {
        runInAction(() => {
            this.syncing = true;
            this.error = undefined;
        });
        const address = this.ensureContract();
        const [mark, index, bestBid, bestAsk, imBps] = await Promise.all([
            publicClient.readContract({ abi: EXCHANGE_ABI, address, functionName: 'markPrice' } as any) as Promise<bigint>,
            publicClient.readContract({ abi: EXCHANGE_ABI, address, functionName: 'indexPrice' } as any) as Promise<bigint>,
            publicClient.readContract({ abi: EXCHANGE_ABI, address, functionName: 'bestBuyId' } as any) as Promise<bigint>,
            publicClient.readContract({ abi: EXCHANGE_ABI, address, functionName: 'bestSellId' } as any) as Promise<bigint>,
            publicClient.readContract({ abi: EXCHANGE_ABI, address, functionName: 'initialMarginBps' } as any) as Promise<bigint>,
        ]);
        runInAction(() => {
            this.markPrice = mark;
            this.indexPrice = index;
            this.initialMarginBps = imBps;
        });

        if (this.account) {
            const [m, pos] = await Promise.all([
                publicClient.readContract({
                    abi: EXCHANGE_ABI,
                    address,
                    functionName: 'margin',
                    args: [this.account],
                } as any) as Promise<bigint>,
                publicClient.readContract({
                    abi: EXCHANGE_ABI,
                    address,
                    functionName: 'getPosition',
                    args: [this.account],
                } as any) as Promise<PositionSnapshot>,
            ]);

            runInAction(() => {
                this.margin = m;
                this.position = pos;
            });
        }

        // 订单簿等其他数据保持不变...
    } catch (e) {
        runInAction(() => (this.error = (e as Error)?.message || 'Failed to sync exchange data'));
    } finally {
        runInAction(() => (this.syncing = false));
    }
};
```

> [!NOTE]
> 使用 `Promise.all` 可以并发请求多个数据，显著提升页面加载速度。
> 所有状态更新都在 `runInAction()` 中包装，确保 MobX 能够正确追踪依赖。

---

## 6) 测试与验证

### 6.1 运行合约测试

```bash
cd contract
forge test --match-contract Day3MatchingTest -vvv
```

通过标准：4 个测试全部 `PASS`

你也可以单独跑某个测试：

```bash
forge test --match-test testClosingPositionRealizesPnl -vvv
```

### 6.2 前端验证（必须）

启动本地环境：

```bash
# 终端1（启动 anvil 并部署）
./scripts/run-anvil-deploy.sh

# 终端2（启动前端）
cd frontend && pnpm dev
```

打开 `http://localhost:3000`，按以下路径验证：

**验收路径 1：基本成交**

1. 切换到 Alice 账号，充值 10 MON
2. 下一个买单：价格 100，数量 1
3. 切换到 Bob 账号，充值 10 MON
4. 下一个卖单：价格 100，数量 1
5. 观察 **Recent Trades** 列表出现成交记录
6. 观察 **Positions** 面板：Alice 显示多头 +1，Bob 显示空头 -1

**验收路径 2：部分成交**

1. Alice 下买单：价格 100，数量 5
2. Bob 下卖单：价格 100，数量 2
3. 观察 Alice 的挂单剩余 3（在 Orderbook 或 Open Orders 中）
4. 观察 Recent Trades 显示成交 2

**验收路径 3：平仓盈亏**

1. Alice 持有多头 1 @ 100（从路径 1 继续）
2. Alice 下卖单：价格 150，数量 1
3. Bob 下买单：价格 150，数量 1（吃掉 Alice 的卖单）
4. 观察 Alice 的 `Available Margin` 增加（包含 +50 的盈利）
5. 观察 Alice 的 Position 变为 0

---

## 7) 常见问题（排错思路）

1. **平仓盈亏计算不对**
   - 检查多头/空头的 PnL 公式符号是否相反
   - 确认 `pnlPerUnit` 的计算顺序（多头：成交价-入场价；空头：入场价-成交价）

2. **`entryPrice` 异常**
   - 加仓时必须按加权平均价更新
   - 注意 `existingAbs == 0` 时直接取 `tradePrice`

3. **平仓后仓位不为 0**
   - 检查 `closing` 与 `remaining` 的分支逻辑
   - 确认 `remaining = amount - closing` 计算正确

4. **margin 没变化**
   - 确认 `pnl` 结果已写入 `margin`
   - 检查 `int256 newMargin = int256(accounts[trader].margin) + pnl;` 这行

5. **前端成交列表不更新**
   - 确认 Indexer 正在运行且监听 `TradeExecuted` 事件
   - 点击 Refresh 按钮手动刷新
   - 检查浏览器 Console 是否有 GraphQL 错误

---

## 8) Indexer：索引成交与持仓

Day 3 的核心是 `TradeExecuted` 事件，我们需要在 Indexer 中处理成交记录和持仓更新。

### Step 1: 定义 Trade 和 Position Schema

在 `indexer/schema.graphql` 中添加：

```graphql
type Trade @entity {
  id: ID!
  buyer: String!
  seller: String!
  price: BigInt!
  amount: BigInt!
  timestamp: Int!
  txHash: String!
  buyOrderId: BigInt!
  sellOrderId: BigInt!
}

type Position @entity {
  id: ID!  # trader address
  trader: String!
  size: BigInt!
  entryPrice: BigInt!
}
```

### Step 2: 添加事件配置

在 `indexer/config.yaml` 的 events 列表中添加：

```yaml
      - event: TradeExecuted(uint256 indexed buyOrderId, uint256 indexed sellOrderId, uint256 price, uint256 amount, address buyer, address seller)
      - event: PositionUpdated(address indexed trader, int256 size, uint256 entryPrice)
```

### Step 3: 实现 TradeExecuted Handler

在 `indexer/src/EventHandlers.ts` 中添加：

```typescript
Exchange.TradeExecuted.handler(async ({ event, context }) => {
    // 1. 创建成交记录
    const trade: Trade = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        buyer: event.params.buyer,
        seller: event.params.seller,
        price: event.params.price,
        amount: event.params.amount,
        timestamp: event.block.timestamp,
        txHash: event.transaction.hash,
        buyOrderId: event.params.buyOrderId,
        sellOrderId: event.params.sellOrderId,
    };
    context.Trade.set(trade);

    // 2. 更新买卖双方订单的剩余量
    const buyOrder = await context.Order.get(event.params.buyOrderId.toString());
    if (buyOrder) {
        const newAmount = buyOrder.amount - event.params.amount;
        context.Order.set({
            ...buyOrder,
            amount: newAmount,
            status: newAmount === 0n ? "FILLED" : "OPEN",
        });
    }

    const sellOrder = await context.Order.get(event.params.sellOrderId.toString());
    if (sellOrder) {
        const newAmount = sellOrder.amount - event.params.amount;
        context.Order.set({
            ...sellOrder,
            amount: newAmount,
            status: newAmount === 0n ? "FILLED" : "OPEN",
        });
    }
});
```

### Step 4: 实现 PositionUpdated Handler

合约的 `_updatePosition` 函数会发出 `PositionUpdated` 事件，我们直接监听它来更新持仓，无需手动计算：

```typescript
Exchange.PositionUpdated.handler(async ({ event, context }) => {
    const position: Position = {
        id: event.params.trader,
        trader: event.params.trader,
        size: event.params.size,
        entryPrice: event.params.entryPrice,
    };
    context.Position.set(position);
});
```

> [!TIP]
> 直接使用合约发出的事件比在 Indexer 中重新计算更简单、更可靠，且能保证与链上状态一致。

### Step 5: Indexer 验证

**启动 Indexer：**

```bash
cd indexer
pnpm codegen  # 每次修改 config.yaml 或 schema.graphql 后必须运行
pnpm dev
```

**触发事件（在前端操作）：**

1. 打开 http://localhost:3000
2. Alice 充值 10 MON，下买单：价格 100，数量 1
3. 切换到 Bob，充值 10 MON，下卖单：价格 100，数量 1
4. 订单撮合成交，触发 `TradeExecuted` 和 `PositionUpdated` 事件

**查询成交记录：**

```bash
curl -s -X POST http://localhost:8080/v1/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ Trade(limit: 5, order_by: {timestamp: desc}) { id buyer seller price amount timestamp } }"}'
```

预期结果：

```json
{
  "data": {
    "Trade": [
      {
        "id": "0x124e7c91...-1",
        "buyer": "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
        "seller": "0x70997970c51812dc3a010c7d01b50e0d17dc79c8",
        "price": "100000000000000000000",
        "amount": "1000000000000000000",
        "timestamp": 1234567890
      }
    ]
  }
}
```

**查询持仓：**

```bash
curl -s -X POST http://localhost:8080/v1/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ Position { id trader size entryPrice } }"}'
```

预期结果：

```json
{
  "data": {
    "Position": [
      {
        "id": "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
        "trader": "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
        "size": "1000000000000000000",
        "entryPrice": "100000000000000000000"
      },
      {
        "id": "0x70997970c51812dc3a010c7d01b50e0d17dc79c8",
        "trader": "0x70997970c51812dc3a010c7d01b50e0d17dc79c8",
        "size": "-1000000000000000000",
        "entryPrice": "100000000000000000000"
      }
    ]
  }
}
```

> [!NOTE]
> - `size` 为正表示多头，为负表示空头
> - `price` 和 `amount` 使用 1e18 精度（100 MON = 100000000000000000000）

---

## 9) 前端：成交列表与持仓组件

### 9.1 RecentTrades 组件（从 Indexer 获取）

项目中已封装好 `IndexerClient`（见 `frontend/store/IndexerClient.ts`），使用方式：

```typescript
import { client, GET_RECENT_TRADES } from './IndexerClient';

// 查询最近成交
const result = await client.query(GET_RECENT_TRADES, {}).toPromise();
if (result.data?.Trade) {
    const trades = result.data.Trade.map((t: any) => ({
        price: formatEther(t.price),
        amount: formatEther(t.amount),
        time: new Date(t.timestamp * 1000).toLocaleTimeString(),
        side: BigInt(t.buyOrderId) > BigInt(t.sellOrderId) ? 'buy' : 'sell',
    }));
}
```

### 9.2 Positions 组件（从 Indexer 或链上获取）

```typescript
// 方式 A：从 Indexer 获取
import { client, GET_POSITIONS } from './IndexerClient';
const result = await client.query(GET_POSITIONS, { trader: account }).toPromise();

// 方式 B：从链上获取（更实时，推荐）
const pos = await publicClient.readContract({
    address: EXCHANGE_ADDRESS,
    abi: EXCHANGE_ABI,
    functionName: 'getPosition',
    args: [account],
});
```

> [!TIP]
> 持仓数据建议从链上获取以确保最新，成交历史则从 Indexer 获取以提升性能。

---

## 10) 小结 & 为 Day 4 铺垫

今天我们完成了"撮合引擎"的核心逻辑：

- `_executeTrade`：撮合后的统一入口，触发事件、更新双方持仓
- `_updatePosition`：处理加仓、减仓、反向开仓三种场景
- 平仓盈亏：平仓时结算已实现盈亏，直接更新到 `margin`
- Indexer：索引成交记录和持仓变化

Day 4 会在此基础上引入"价格服务"：

- `updateIndexPrice()`：外部预言机/Keeper 推送价格
- `_calculateMarkPrice()`：三价取中计算标记价格
- 标记价格将用于计算"未实现盈亏"与"强平价格"
