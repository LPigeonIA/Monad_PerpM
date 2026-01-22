# Day 5 - 数据索引与 K 线（Indexer & Candles）

本节目标：配置 Indexer（Envio）解析链上事件，生成 Trade、Order、Candle（OHLC）等数据结构，并在前端集成图表库展示专业的 K 线行情看板。

---

## 1) 学习目标

完成本节后，你将能够：

- 理解区块链 Indexer 的作用：将链上事件转换为可查询的结构化数据。
- 配置 Envio Indexer：定义 schema、编写 event handler。
- 实现 K 线（Candle）数据生成：从 TradeExecuted 事件构建 OHLC。
- 在前端集成图表库展示 K 线。

---

## 2) 前置准备

Day 5 建立在 Day 4 之上，请先确认：

- Day 1-4 功能已实现（保证金、订单簿、撮合、价格服务）
- 本地 Anvil 和合约部署正常

你可以先跑：

```bash
./quickstart.sh
# 确认前端能正常下单和成交
```

---

## 3) 当天完成标准

- Indexer 能正确解析 `MarginDeposited`、`OrderPlaced`、`TradeExecuted` 等事件
- GraphQL API 可查询 `trades`、`orders`、`candles`
- 前端 Recent Trades 列表从 Indexer 获取数据
- 前端 K 线图表显示历史价格走势
- 前端 OrderBook 深度从 Indexer 获取

---

## 4) 开发步骤（边理解边写代码）

### Step 1: 理解 Indexer 架构

Indexer 的作用是：

```
链上事件 (Event Logs) → Indexer 解析 → 数据库存储 → GraphQL API → 前端查询
```

本课程使用 **Envio** 作为 Indexer 框架，配置文件：

- `indexer/config.yaml`：定义监听的合约和事件
- `indexer/schema.graphql`：定义数据模型
- `indexer/src/EventHandlers.ts`：事件处理逻辑

---

### Step 2: 添加 K 线 Schema 定义

修改：
- `indexer/schema.graphql`

Day 1-3 已经定义了 `MarginEvent`、`Order`、`Trade`、`Position` 实体。Day 5 需要**新增**以下两个实体来支持 K 线功能：

```graphql
# Day 5: Candle - K 线数据
type Candle @entity {
  id: ID!  # "1m-timestamp"
  resolution: String!
  timestamp: Int!
  openPrice: BigInt!
  highPrice: BigInt!
  lowPrice: BigInt!
  closePrice: BigInt!
  volume: BigInt!
}

# Day 5: LatestCandle - 最新价格状态（用于新 K 线的 open 价格）
type LatestCandle @entity {
  id: ID!  # "1"
  closePrice: BigInt!
  timestamp: Int!
}
```

将上述代码添加到 `schema.graphql` 文件末尾。

---

### Step 2.5: 生成类型定义 (Codegen)
在编写代码之前，必须先根据 `config.yaml` 和 `schema.graphql` 生成 TypeScript 类型定义。

```bash
cd indexer
pnpm codegen
```

> [!IMPORTANT]
> 每当你修改了 `config.yaml` 或 `schema.graphql`，都必须重新运行 `pnpm codegen`，否则 `src/EventHandlers.ts` 会报错找不到类型。

---

### Step 3: 在 TradeExecuted Handler 中添加 K 线逻辑

Day 3 已实现 TradeExecuted handler 的基础部分（Trade 记录 + Order 更新）。现在在该 handler 末尾（`context.Trade.set(trade);` 之后）添加 K 线聚合逻辑：

修改：

- `indexer/src/EventHandlers.ts`

找到 `Exchange.TradeExecuted.handler`，在 `context.Trade.set(trade);` 后添加：

```typescript
    // Day 5: 更新 K 线 (1m)
const resolution = "1m";
// 向下取整到最近的分钟
const timestamp = event.block.timestamp - (event.block.timestamp % 60);
const candleId = `${resolution}-${timestamp}`;

const existingCandle = await context.Candle.get(candleId);

if (!existingCandle) {
    // 新 K 线：使用上一根 K 线的 close 作为 open
    const latestCandleState = await context.LatestCandle.get("1");
    const openPrice = latestCandleState ? latestCandleState.closePrice : event.params.price;
    
    const candle: Candle = {
        id: candleId,
        resolution,
        timestamp,
        openPrice: openPrice,
        highPrice: event.params.price > openPrice ? event.params.price : openPrice,
        lowPrice: event.params.price < openPrice ? event.params.price : openPrice,
        closePrice: event.params.price,
        volume: event.params.amount,
    };
    context.Candle.set(candle);
} else {
    // 更新现有 K 线
    const newHigh = event.params.price > existingCandle.highPrice ? event.params.price : existingCandle.highPrice;
    const newLow = event.params.price < existingCandle.lowPrice ? event.params.price : existingCandle.lowPrice;

    context.Candle.set({
        ...existingCandle,
        highPrice: newHigh,
        lowPrice: newLow,
        closePrice: event.params.price,
        volume: existingCandle.volume + event.params.amount,
    });
}

// 更新全局最新价格状态
context.LatestCandle.set({
    id: "1",
    closePrice: event.params.price,
    timestamp: event.block.timestamp
});
```

---

### Step 5: 启动 Indexer

```bash
# 安装依赖
cd indexer
pnpm install

# 启动（需要先启动 Anvil）
pnpm dev
```

验证 GraphQL playground：

```
http://localhost:8080/graphql
```

查询示例：

```graphql
query {
  trades(limit: 10, orderBy: timestamp, orderDirection: desc) {
    id
    buyer
    seller
    price
    amount
    timestamp
  }
}

query {
  candles(where: { resolution: "1m" }, orderBy: timestamp, orderDirection: desc) {
    timestamp
    openPrice
    highPrice
    lowPrice
    closePrice
    volume
  }
}

query {
  positions {
    trader
    size
    entryPrice
  }
}
```

---

### Step 6: 前端数据抓取 (Store 逻辑)

在 `frontend/store/exchangeStore.tsx` 中实现从 Indexer 获取数据的逻辑。

#### 6.0 确认 IndexerClient 已启用

如果你在 Day 2 已经完成了这一步，可以跳过。

确认文件顶部已有以下 import 语句（在 Day 2 Step 2.1 中启用）：

```typescript
import { client, GET_CANDLES, GET_RECENT_TRADES, GET_POSITIONS, GET_OPEN_ORDERS } from './IndexerClient';
```

#### 6.1 实现 loadTrades

找到 `loadTrades` 方法（标记为 `// Open for implementation in Day 5`），实现如下：

```typescript
loadTrades = async (): Promise<Trade[]> => {
    const result = await client.query(GET_RECENT_TRADES, {}).toPromise();
    if (!result.data?.Trade) return [];
    const trades = result.data.Trade.map((t: any) => ({
        id: t.id,
        price: Number(formatEther(t.price)),
        amount: Number(formatEther(t.amount)),
        time: new Date(t.timestamp * 1000).toLocaleTimeString(),
        side: BigInt(t.buyOrderId) > BigInt(t.sellOrderId) ? 'buy' : 'sell',
    }));
    runInAction(() => { this.trades = trades; });
    return trades;
};
```

#### 6.2 实现 loadCandles

找到 `loadCandles` 方法，实现如下：

```typescript
loadCandles = async () => {
    const result = await client.query(GET_CANDLES, {}).toPromise();
    if (result.data?.Candle) {
        const candles = result.data.Candle.map((c: any) => ({
            time: new Date(c.timestamp * 1000).toISOString(),
            open: Number(formatEther(c.openPrice)),
            high: Number(formatEther(c.highPrice)),
            low: Number(formatEther(c.lowPrice)),
            close: Number(formatEther(c.closePrice)),
        }));
        runInAction(() => { this.candles = candles; });
    }
};
```

#### 6.3 启用数据加载

在 `refresh()` 方法中，找到以下被注释的代码并取消注释：

```typescript
await this.loadTrades();
this.loadCandles();
```

#### 6.4 实现用户成交历史 (loadMyTrades)

`loadTrades` 获取的是全市场最近 50 条成交，但用户在前端的 "History" 标签页需要看到**自己的成交历史**。如果用户的成交不在最近 50 条中，就无法显示。

脚手架已在 `IndexerClient.ts` 中定义了 `GET_MY_TRADES` 查询，你需要在 `exchangeStore.tsx` 中实现 `loadMyTrades` 方法：

```typescript
loadMyTrades = async (trader: Address): Promise<Trade[]> => {
    const result = await client.query(GET_MY_TRADES, { trader: trader.toLowerCase() }).toPromise();
    if (!result.data?.Trade) return [];
    const trades = result.data.Trade.map((t: any) => ({
        id: t.id,
        price: Number(formatEther(t.price)),
        amount: Number(formatEther(t.amount)),
        time: new Date(t.timestamp * 1000).toLocaleTimeString(),
        side: t.buyer.toLowerCase() === trader.toLowerCase() ? 'buy' : 'sell',
    }));
    runInAction(() => { this.myTrades = trades; });
    return trades;
};
```

**关键点**：
- 使用 `GET_MY_TRADES` 查询，它会筛选 `buyer` 或 `seller` 等于当前用户的成交
- `side` 判断逻辑：如果用户是买方 (`buyer`)，则显示为 `'buy'`；否则为 `'sell'`
- 注意地址需要转为小写 `trader.toLowerCase()`，因为 Indexer 存储的地址是小写格式

然后在 `refresh()` 方法中调用（在获取 `myOrders` 的逻辑附近）：

```typescript
if (this.account) {
    // ... loadMyOrders 调用 ...
    await this.loadMyTrades(this.account);
}
```

---


## 5) 解析：为什么这样写

### 5.1 为什么需要 Indexer？

区块链是"只写"的，查询历史数据很慢：

| 方案 | 速度 | 成本 |
|------|------|------|
| 直接查链 | 慢（需遍历区块） | 高（RPC 调用费用） |
| **Indexer** | 快（数据库查询） | 低（一次索引多次查询） |

### 5.2 OHLC K 线原理

| 字段 | 含义 |
|------|------|
| Open | 该时间段第一笔成交价 |
| High | 该时间段最高成交价 |
| Low | 该时间段最低成交价 |
| Close | 该时间段最后一笔成交价 |
| Volume | 该时间段成交量 |

### 5.3 为什么用 LatestCandle？

当开始新的 K 线时，需要知道上一根 K 线的 close 价格作为新 K 线的 open：

```
K1: [O=100, H=105, L=98, C=102]
K2: [O=102, ...]  ← 继承 K1 的 close
```

---

## 6) 测试与验证

### 6.1 启动服务

```bash
# 终端 1：启动 Anvil 并部署合约
./scripts/run-anvil-deploy.sh

# 终端 2：启动 Indexer（需要先运行 codegen）
cd indexer && pnpm codegen && pnpm dev

# 终端 3：启动 Keeper（价格服务）
cd keeper && pnpm start

# 终端 4：启动前端
cd frontend && pnpm dev
```

### 6.2 初始化测试数据

等待所有服务就绪后，运行数据初始化脚本：

```bash
./scripts/seed.sh
```

该脚本会自动：
- 读取部署的合约地址
- 为 Alice 和 Bob 充值保证金
- 设置初始价格
- 执行多笔成交（生成多根 K 线）
- 创建部分成交订单

### 6.3 GraphQL 验证

**查询 Trade（成交记录）**：

```bash
curl -s -X POST http://localhost:8080/v1/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ Trade(order_by: { timestamp: desc }, limit: 5) { id buyer seller price amount timestamp } }"}'
```

**预期输出**：

```json
{
  "data": {
    "Trade": [
      {
        "id": "0x...-3",
        "buyer": "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
        "seller": "0x70997970c51812dc3a010c7d01b50e0d17dc79c8",
        "price": "1550000000000000000000",
        "amount": "30000000000000000",
        "timestamp": 1234567890
      }
    ]
  }
}
```

**查询 Candle（K 线）**：

```bash
curl -s -X POST http://localhost:8080/v1/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ Candle(where: { resolution: { _eq: \"1m\" } }, order_by: { timestamp: desc }, limit: 5) { id resolution timestamp openPrice highPrice lowPrice closePrice volume } }"}'
```

**预期输出**（应有多根 K 线，价格分别为 1500、1520、1490、1550）：

```json
{
  "data": {
    "Candle": [
      {
        "id": "1m-...",
        "resolution": "1m",
        "timestamp": 1234567920,
        "openPrice": "1490000000000000000000",
        "highPrice": "1550000000000000000000",
        "lowPrice": "1490000000000000000000",
        "closePrice": "1550000000000000000000",
        "volume": "30000000000000000"
      }
    ]
  }
}
```

**查询 LatestCandle（最新价格状态）**：

```bash
curl -s -X POST http://localhost:8080/v1/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ LatestCandle { id closePrice timestamp } }"}'
```

**预期输出**：

```json
{
  "data": {
    "LatestCandle": [
      {
        "id": "1",
        "closePrice": "1550000000000000000000",
        "timestamp": 1234567890
      }
    ]
  }
}
```

### 6.4 前端验证

打开 `http://localhost:3000`，验证以下功能：

**Step 1: 检查 Recent Trades 列表**
- 在页面右侧找到 "Recent Trades" 区域
- 预期结果：显示多条成交记录，包含价格（如 1500、1520、1490、1550）和数量

**Step 2: 检查浏览器控制台**
- 打开浏览器开发者工具（F12）→ Console
- 预期结果：应看到 `[loadTrades]` 和 `[loadCandles]` 的日志，无错误信息

**Step 3: 触发新交易验证实时更新**
- 在前端下一笔新订单（如 Alice 买入 0.01 @ 1560）
- 等待 2-3 秒后观察 Recent Trades 列表
- 预期结果：新成交记录出现在列表顶部

**Step 4: 验证 K 线数据加载（可选）**
- 如果已集成图表组件，检查 K 线图表是否显示
- 预期结果：显示多根 K 线，价格范围在 1490-1550 之间

---

## 7) 常见问题（排错思路）

1. **Indexer 报错 "contract not found"**
   - 检查 `config.yaml` 中的合约地址是否与部署地址一致
   - 重新运行 `./scripts/run-anvil-deploy.sh` 并更新配置

2. **GraphQL 查询返回空数组**
   - 确认 Indexer 正在运行且已处理事件
   - 查看 Indexer 日志确认是否有错误

3. **K 线数据不连续**
   - 确认 `LatestCandle` 逻辑正确实现
   - 检查时间戳取整逻辑 `timestamp % 60`

4. **前端图表不显示**
   - 确认 GraphQL endpoint 地址正确
   - 检查浏览器 Console 是否有 CORS 错误

---

## 8) 小结 & 为 Day 6 铺垫

今天我们完成了"数据索引"层：

- 配置 Envio Indexer 解析链上事件
- 实现 Event Handlers 存储 Trade、Order、Candle
- 前端通过 GraphQL 获取历史数据

至此，系统具备了：
1. 资金管理 → 2. 订单簿 → 3. 撮合 → 4. 价格服务 → **5. 数据索引**

Day 6 会在此基础上实现"资金费率机制"：

- `settleFunding()`：全局资金费率结算
- `_applyFunding()`：用户级资金费计算
- Keeper 定时触发结算
- 前端显示"未结资金费"与"强平价格"

---

## 9) 进阶开发（可选）

1. **多分辨率 K 线**
   - 支持 5m、15m、1h 等多种时间粒度。
   - 修改 resolution 参数和时间戳取整逻辑。

2. **实时 WebSocket 推送**
   - 使用 Envio 的 subscription 功能。
   - 前端订阅新成交事件。

3. **深度图数据**
   - 聚合 Order 实体生成深度数据。
   - 按价格级别汇总买卖盘数量。

4. **历史数据分页**
   - 实现 GraphQL 分页查询。
   - 前端无限滚动加载更多数据。
