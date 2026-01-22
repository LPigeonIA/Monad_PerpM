# Day 2 - 订单簿与下单（OrderBook & PlaceOrder）

本节目标：在 Day 1（保证金充值/提现 + 视图函数）已经完成的基础上，实现一个最小可运行的**限价单订单簿**：用户可以下单 `placeOrder`，订单会按价格优先排序进入链表；用户也可以撤单 `cancelOrder` 把订单从链表中移除。

---

## 1) 学习目标

完成本节后，你将能够：

- 理解“价格优先 + 同价 FIFO”在链上如何落到链表结构上。
- 掌握有序单链表的插入与删除（空表/插头/插尾/中间删除）。
- 理解 `hintId`：为什么需要、合约如何校验它、防止“同价插队”。
- 学会继续用测试驱动实现：先读 `Day2OrderbookTest`，再补齐合约 TODO。

---

## 2) 前置准备

Day2 是建立在 Day1 之上的，请先确认：

- `deposit()` / `withdraw(uint256)` 已实现并能通过 `Day1MarginTest`
- `margin(address)` 视图函数已实现（Day2 测试会读取余额）

你可以先跑：

```bash
cd contract
forge test --match-contract Day1MarginTest -vvv
```

---

## 3) 当天完成标准

- `forge test --match-contract Day2OrderbookTest -vvv` 全部通过
- 买单链表始终保持：**价格从高到低**（同价 FIFO）
- 卖单链表始终保持：**价格从低到高**（同价 FIFO）
- `hintId` 校验行为与测试一致：`invalid hint` / `hint too deep` / `hint not last`
- `cancelOrder` 能正确移除订单并 `delete orders[id]`

---

## 4) 开发步骤（边理解边写代码）

### Step 1: 读测试，先把规则写清楚

打开：

- `contract/test/Day2Orderbook.t.sol`

你会看到三类要求：

1. **排序正确**：更高买价变头、更低卖价变头
2. **同价 FIFO**：同价单不能插队（第二单应在第一单后面）
3. **hint 校验**：错误的 hint 必须 revert 且消息匹配

> 注意：测试里 `price/amount` 直接用小整数写起来更直观；你实现排序逻辑时不需要关心精度，只要“同一套比较规则”在合约里一致即可。

---

### Step 2: 先看存储结构（你要改哪些指针）

打开：

- `contract/src/core/ExchangeStorage.sol`

你会用到这些状态：

- `mapping(uint256 => Order) public orders;`
- `uint256 public bestBuyId;`
- `uint256 public bestSellId;`
- `uint256 internal orderIdCounter;`
- `mapping(address => uint256) public pendingOrderCount;`

---

### Step 3: 实现 `getOrder`（订单查询视图函数）

修改：

- `contract/src/modules/ViewModule.sol`

Day 2 需要通过 `getOrder` 来查询订单详情，测试和前端都会用到这个函数。

参考实现：

```solidity
function getOrder(uint256 id) external view virtual returns (Order memory) {
    return orders[id];
}
```

预期行为：

- `exchange.getOrder(1)` 返回 ID 为 1 的订单详情
- 如果订单不存在，返回空结构体（`id = 0`）

---

### Step 4: 实现 `_startFromHint`（Day2 的关键）

修改：

- `contract/src/modules/OrderBookModule.sol`

`hintId` 的含义是：“我认为新订单应该插在 `hintId` 之后”。合约必须校验：

- hint 存在（否则 `"invalid hint"`）
- 价格关系不矛盾（否则 `"hint too deep"`）
- 同价时必须插在该价位尾部（否则 `"hint not last"`，防止插队）

参考实现（可直接照写）：

```solidity
function _startFromHint(bool isBuy, uint256 price, uint256 hintId)
    internal
    view
    virtual
    returns (uint256 prev, uint256 curr)
{
    if (hintId == 0) {
        return (0, isBuy ? bestBuyId : bestSellId);
    }

    Order storage hint = orders[hintId];
    require(hint.id != 0, "invalid hint");

    if (isBuy) {
        require(price <= hint.price, "hint too deep");
        if (price == hint.price && hint.next != 0) {
            require(orders[hint.next].price != price, "hint not last");
        }
    } else {
        require(price >= hint.price, "hint too deep");
        if (price == hint.price && hint.next != 0) {
            require(orders[hint.next].price != price, "hint not last");
        }
    }

    return (hintId, hint.next);
}
```

---

### Step 5: 实现 `_insertBuy` / `_insertSell`（把订单“入簿”）

修改：

- `contract/src/modules/OrderBookModule.sol`

你要实现的两个排序规则：

- 买单：价格降序；同价 FIFO（新单插在同价尾部）
- 卖单：价格升序；同价 FIFO

参考实现（买单）：

```solidity
function _insertBuy(Order memory incoming, uint256 hintId) internal virtual {
    (uint256 prevId, uint256 currentId) = _startFromHint(true, incoming.price, hintId);

    while (currentId != 0 && orders[currentId].price > incoming.price) {
        prevId = currentId;
        currentId = orders[currentId].next;
    }
    while (currentId != 0 && orders[currentId].price == incoming.price) {
        prevId = currentId;
        currentId = orders[currentId].next;
    }

    incoming.next = currentId;
    orders[incoming.id] = incoming;

    if (prevId == 0) bestBuyId = incoming.id;
    else orders[prevId].next = incoming.id;

    pendingOrderCount[incoming.trader]++;
}
```

参考实现（卖单）：

```solidity
function _insertSell(Order memory incoming, uint256 hintId) internal virtual {
    (uint256 prevId, uint256 currentId) = _startFromHint(false, incoming.price, hintId);

    while (currentId != 0 && orders[currentId].price < incoming.price) {
        prevId = currentId;
        currentId = orders[currentId].next;
    }
    while (currentId != 0 && orders[currentId].price == incoming.price) {
        prevId = currentId;
        currentId = orders[currentId].next;
    }

    incoming.next = currentId;
    orders[incoming.id] = incoming;

    if (prevId == 0) bestSellId = incoming.id;
    else orders[prevId].next = incoming.id;

    pendingOrderCount[incoming.trader]++;
}
```

---

### Step 6: 实现 `_matchBuy` / `_matchSell`（Day2 用“无成交时入簿”就够）

修改：

- `contract/src/modules/OrderBookModule.sol`

Day2 的测试里不会发生真实成交（例如只下买单，卖盘为空），所以你只要保证：

- 如果对手盘为空/不满足价格，剩余量会入簿

参考实现（保留 Day3 可扩展结构，成交部分留到 Day3 再补）：

```solidity
function _matchBuy(Order memory incoming, uint256 hintId) internal virtual {
    while (incoming.amount > 0 && bestSellId != 0) {
        Order storage head = orders[bestSellId];
        if (incoming.price < head.price) break;

        uint256 matched = Math.min(incoming.amount, head.amount);
        _executeTrade(incoming.trader, head.trader, incoming.id, head.id, matched, head.price); // Day3 实现

        incoming.amount -= matched;
        head.amount -= matched;

        if (head.amount == 0) {
            uint256 nextHead = head.next;
            uint256 removedId = head.id;
            pendingOrderCount[head.trader]--;
            delete orders[bestSellId];
            bestSellId = nextHead;
            emit OrderRemoved(removedId);
        }
    }

    if (incoming.amount > 0) {
        _insertBuy(incoming, hintId);
        _checkWorstCaseMargin(incoming.trader); // Day2 可先实现成“结构化的骨架”
    }
}
```

`_matchSell` 同理（方向相反）：

```solidity
function _matchSell(Order memory incoming, uint256 hintId) internal virtual {
    while (incoming.amount > 0 && bestBuyId != 0) {
        Order storage head = orders[bestBuyId];
        if (incoming.price > head.price) break;

        uint256 matched = Math.min(incoming.amount, head.amount);
        _executeTrade(head.trader, incoming.trader, head.id, incoming.id, matched, head.price);

        incoming.amount -= matched;
        head.amount -= matched;

        if (head.amount == 0) {
            uint256 nextHead = head.next;
            uint256 removedId = head.id;
            pendingOrderCount[head.trader]--;
            delete orders[bestBuyId];
            bestBuyId = nextHead;
            emit OrderRemoved(removedId);
        }
    }

    if (incoming.amount > 0) {
        _insertSell(incoming, hintId);
        _checkWorstCaseMargin(incoming.trader);
    }
}
```

---

### Step 7: 实现 `placeOrder`（把 Day2 路径串起来）

修改：

- `contract/src/modules/OrderBookModule.sol`

你要把“参数检查 → 构造订单 → 进入 match → 入簿/删除”串起来。参考实现：

```solidity
function placeOrder(bool isBuy, uint256 price, uint256 amount, uint256 hintId)
    external
    virtual
    nonReentrant
    returns (uint256)
{
    require(price > 0 && amount > 0, "invalid params");

    _applyFunding(msg.sender);

    require(_countPendingOrders(msg.sender) < MAX_PENDING_ORDERS, "too many pending orders");
    _checkWorstCaseMargin(msg.sender);

    orderIdCounter += 1;
    uint256 orderId = orderIdCounter;
    emit OrderPlaced(orderId, msg.sender, isBuy, price, amount);

    Order memory incoming = Order(orderId, msg.sender, isBuy, price, amount, amount, block.timestamp, 0);

    if (isBuy) _matchBuy(incoming, hintId);
    else _matchSell(incoming, hintId);

    return orderId;
}
```

---

### Step 8: 实现撤单 `cancelOrder` + 链表删除 `_removeOrderFromList`

修改：

- `contract/src/modules/OrderBookModule.sol`

撤单的核心是“从链表中摘掉节点 + 清理存储”。参考实现：

```solidity
function cancelOrder(uint256 orderId) external virtual nonReentrant {
    Order storage o = orders[orderId];
    require(o.id != 0, "order not found");
    require(o.trader == msg.sender, "not your order");

    if (o.isBuy) bestBuyId = _removeOrderFromList(bestBuyId, orderId);
    else bestSellId = _removeOrderFromList(bestSellId, orderId);

    pendingOrderCount[msg.sender]--;
    emit OrderRemoved(orderId);
    delete orders[orderId];
}

function _removeOrderFromList(uint256 head, uint256 targetId) internal returns (uint256 newHead) {
    if (head == targetId) return orders[head].next;

    uint256 prev = head;
    uint256 curr = orders[head].next;
    while (curr != 0) {
        if (curr == targetId) {
            orders[prev].next = orders[curr].next;
            break;
        }
        prev = curr;
        curr = orders[curr].next;
    }
    return head;
}
```

---

### Step 9: Day2 的保证金检查怎么写（先写“骨架”，不阻塞主线）

你会在：

- `contract/src/modules/MarginModule.sol`

看到 `_calculatePositionMargin` / `_calculateWorstCaseMargin` / `_checkWorstCaseMargin` 的 TODO。

Day2 的要求不是做完整风控，但为了后续 Day3+ 不返工，建议你把这三个函数按“真实结构”写出来：即便现在 `markPrice` 还没设置，计算出来的 `required` 很可能是 0，也不会影响 Day2 的订单簿测试。

你可以按下面思路实现：

- `_calculatePositionMargin`：`abs(size) * markPrice / 1e18 * initialMarginBps / 10000`
- `_calculateWorstCaseMargin`：遍历买/卖链表，累加该用户挂单量，算“全买成交/全卖成交”两种持仓，取更大保证金
- `_checkWorstCaseMargin`：`margin + unrealizedPnl >= required`（注意：`realizedPnl` 已在 `_updatePosition` 结算到 `margin`，无需重复加）

参考实现（可直接照写；注意这里不强制要求 `markPrice > 0`，Day4 再收紧）：

```solidity
function _calculatePositionMargin(int256 size) internal view returns (uint256) {
    if (size == 0 || markPrice == 0) return 0;
    uint256 absSize = SignedMath.abs(size);
    uint256 notional = (absSize * markPrice) / 1e18;
    return (notional * initialMarginBps) / 10_000;
}

    function _calculateWorstCaseMargin(address trader) internal view returns (uint256) {
        Position memory pos = accounts[trader].position;

        // 1. Calculate margin needed for Open Orders (based on Order Price)
        // 使用委托价 (User Price) 而非标记价来计算挂单占用的保证金
        uint256 buyOrderMargin = 0;
        uint256 id = bestBuyId;
        while (id != 0) {
            if (orders[id].trader == trader) {
                 uint256 orderVal = (orders[id].price * orders[id].amount) / 1e18;
                 buyOrderMargin += (orderVal * initialMarginBps) / 10_000;
            }
            id = orders[id].next;
        }

        uint256 sellOrderMargin = 0;
        id = bestSellId;
        while (id != 0) {
            if (orders[id].trader == trader) {
                 uint256 orderVal = (orders[id].price * orders[id].amount) / 1e18;
                 sellOrderMargin += (orderVal * initialMarginBps) / 10_000;
            }
            id = orders[id].next;
        }

        // 2. Calculate margin needed for Current Position (based on Mark Price)
        uint256 positionMargin = _calculatePositionMargin(pos.size);

        // 3. Total Required = Position Margin + Max(BuyOrdersMargin, SellOrdersMargin)
        return positionMargin + (buyOrderMargin > sellOrderMargin ? buyOrderMargin : sellOrderMargin);
    }

    function _checkWorstCaseMargin(address trader) internal view {
        uint256 required = _calculateWorstCaseMargin(trader);
        Position memory p = accounts[trader].position;

        int256 marginBalance =
            int256(accounts[trader].margin) + _unrealizedPnl(p);

        require(marginBalance >= int256(required), "insufficient margin");
    }
```

---

## 5) 测试与验证

### 5.1 运行 Day2 合约测试

```bash
cd contract
forge test --match-contract Day2OrderbookTest -vvv
```

预期：8 个测试全部通过。

### 5.2 前端验证

**启动环境**：

```bash
# 终端 1：启动本地链并部署
./scripts/run-anvil-deploy.sh

# 终端 2：启动前端
cd frontend && pnpm dev
```

**验证步骤**：

1. 打开 http://localhost:3000
2. 在 Deposit 区域充值 100 ETH（系统内视为 100 USD）
3. 下单测试：
   - 下一个买单：价格 1500，数量 0.1（需保证金 = 1500 × 0.1 / 20 = 7.5 USD）
   - 再下一个买单：价格 1600，数量 0.1（需保证金 = 1600 × 0.1 / 20 = 8 USD）
   - 观察订单簿：1600 的买单应该排在 1500 上面（价格高的在上）
4. 撤单测试：
   - 点击订单旁的取消按钮
   - 订单应该从列表中消失

> **保证金计算**：初始保证金 = 价格 × 数量 / 杠杆倍数（默认 20 倍）

**预期结果**：
- 订单簿显示正确的价格排序（买单价格高在上，卖单价格低在上）
- 撤单后订单从列表移除

---

## 6) 常见问题（排错思路）

1. **`hint not last` 一直触发**：你没有正确校验/维护"同价尾部"，或插入逻辑没有把新单放到同价末尾。
2. **链表断了/循环了**：检查 `incoming.next`、`bestBuyId/bestSellId`、`orders[prev].next` 的赋值顺序。
3. **撤单后链表顺序错**：`_removeOrderFromList` 没处理"删除头节点"的情况，或没正确连接 `prev.next`。

---

## 7) Indexer：索引订单事件

Day 2 的合约会触发 `OrderPlaced` 和 `OrderRemoved` 事件，需要在 Indexer 中处理。

### Step 1: 配置事件（config.yaml）

在 `indexer/config.yaml` 的 `events` 列表中添加订单事件：

```yaml
contracts:
  - name: Exchange
    handler: src/EventHandlers.ts
    events:
      - event: MarginDeposited(address indexed trader, uint256 amount)
      - event: MarginWithdrawn(address indexed trader, uint256 amount)
      # Day 2: 添加订单事件
      - event: OrderPlaced(uint256 indexed id, address indexed trader, bool isBuy, uint256 price, uint256 amount)
      - event: OrderRemoved(uint256 indexed id)
```

### Step 2: 定义 Order Schema

在 `indexer/schema.graphql` 中添加（Day 1 已有 MarginEvent）：

```graphql
type Order @entity {
  id: ID!
  trader: String!
  isBuy: Boolean!
  price: BigInt!
  initialAmount: BigInt!
  amount: BigInt!
  status: String!  # "OPEN", "FILLED", "CANCELLED"
  timestamp: Int!
}
```

### Step 3: 实现 Order Event Handlers

在 `indexer/src/EventHandlers.ts` 中添加：

```typescript
Exchange.OrderPlaced.handler(async ({ event, context }) => {
    const order: Order = {
        id: event.params.id.toString(),
        trader: event.params.trader,
        isBuy: event.params.isBuy,
        price: event.params.price,
        initialAmount: event.params.amount,
        amount: event.params.amount,
        status: "OPEN",
        timestamp: event.block.timestamp,
    };
    context.Order.set(order);
});

Exchange.OrderRemoved.handler(async ({ event, context }) => {
    const order = await context.Order.get(event.params.id.toString());
    if (order) {
        context.Order.set({
            ...order,
            status: order.amount === 0n ? "FILLED" : "CANCELLED",
            amount: 0n, // 清零以便 GET_OPEN_ORDERS 过滤
        });
    }
});
```

### Step 4: 验证 Indexer

**启动步骤**：

```bash
# 1. 重置旧数据（如有）
cd indexer/generated && docker compose down -v && cd ..

# 2. 生成类型
pnpm codegen

# 3. 启动 Indexer
pnpm dev
```

**触发事件**：

1. 确保本地链和前端已启动（见 5.2 节）
2. 在前端下单：买单 价格 1600，数量 0.1
3. 在前端下单：卖单 价格 1400，数量 0.1

**验证方式 1：Hasura Console（UI）**

打开 http://localhost:8080/console，在 GraphiQL 中执行：

```graphql
query {
  Order(order_by: {timestamp: desc}) {
    id
    trader
    isBuy
    price
    amount
    status
  }
}
```

**验证方式 2：curl（命令行）**

```bash
curl -X POST http://localhost:8080/v1/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ Order(order_by: {timestamp: desc}) { id trader isBuy price amount status } }"}'
```

**预期结果**：

```json
{
  "data": {
    "Order": [
      {
        "id": "2",
        "trader": "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
        "isBuy": false,
        "price": "1400000000000000000000",
        "amount": "100000000000000000",
        "status": "OPEN"
      },
      {
        "id": "1",
        "trader": "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
        "isBuy": true,
        "price": "1600000000000000000000",
        "amount": "100000000000000000",
        "status": "OPEN"
      }
    ]
  }
}
```

> 注意：`price` 和 `amount` 是 18 位精度的 BigInt。

**撤单后验证**：

在前端撤销订单 1，再次查询，预期 `status` 变为 `"CANCELLED"`。

---

## 8) 前端：实现下单功能

### Step 1: 实现 placeOrder 函数

修改 `frontend/store/exchangeStore.tsx`，实现 `placeOrder` 函数：

```typescript
placeOrder = async (params: { side: OrderSide; orderType?: OrderType; price?: string; amount: string; hintId?: string }) => {
  const { side, orderType = OrderType.LIMIT, price, amount, hintId } = params;
  if (!this.walletClient || !this.account) throw new Error('Connect wallet before placing orders');

  // 处理市价单：使用 markPrice 加滑点
  const currentPrice = this.markPrice > 0n ? this.markPrice : parseEther('1500');
  const parsedPrice = price ? parseEther(price) : currentPrice;
  const effectivePrice =
    orderType === OrderType.MARKET
      ? side === OrderSide.BUY
        ? currentPrice + parseEther('100')  // 买单加滑点
        : currentPrice - parseEther('100') > 0n ? currentPrice - parseEther('100') : 1n
      : parsedPrice;

  const parsedAmount = parseEther(amount);
  const parsedHint = hintId ? BigInt(hintId) : 0n;

  const hash = await this.walletClient.writeContract({
    account: this.account,
    address: this.ensureContract(),
    abi: EXCHANGE_ABI,
    functionName: 'placeOrder',
    args: [side === OrderSide.BUY, effectivePrice, parsedAmount, parsedHint],
    chain: undefined,
  } as any);

  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== 'success') throw new Error('Transaction failed');
  await this.refresh();
}
```

### Step 2: 从 Indexer 获取我的订单

#### 2.1 启用 IndexerClient

在文件顶部找到被注释的 import 语句，取消注释：

```typescript
import { client, GET_CANDLES, GET_RECENT_TRADES, GET_POSITIONS, GET_OPEN_ORDERS } from './IndexerClient';
```

#### 2.2 实现 loadMyOrders

找到 `loadMyOrders` 方法，实现如下：

```typescript
// Day 2: 从 Indexer 获取用户的 OPEN 订单
loadMyOrders = async (trader: Address): Promise<OpenOrder[]> => {
  // 注意: indexer 存储的地址是小写格式，需要转换
  const result = await client.query(GET_OPEN_ORDERS, { trader: trader.toLowerCase() }).toPromise();
  const orders = result.data?.Order || [];
  return orders.map((o: any) => ({
    id: BigInt(o.id),
    isBuy: o.isBuy,
    price: BigInt(o.price),
    amount: BigInt(o.amount),
    initialAmount: BigInt(o.initialAmount),
    timestamp: BigInt(o.timestamp),
    trader: trader,
  }));
};
```

然后在 `refresh` 函数中调用：

```typescript
// Day 2: 从 Indexer 获取我的订单
if (this.account) {
  const orders = await this.loadMyOrders(this.account);
  runInAction(() => {
    this.myOrders = orders;
  });
}
```

### Step 3: 实现 cancelOrder 函数

修改 `frontend/store/exchangeStore.tsx`，实现 `cancelOrder` 函数：

```typescript
cancelOrder = async (orderId: bigint) => {
  if (!this.walletClient || !this.account) throw new Error('Connect wallet before cancelling orders');
  runInAction(() => { this.cancellingOrderId = orderId; });
  try {
    const hash = await this.walletClient.writeContract({
      account: this.account,
      address: this.ensureContract(),
      abi: EXCHANGE_ABI,
      functionName: 'cancelOrder',
      args: [orderId],
      chain: undefined,
    } as any);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    if (receipt.status !== 'success') throw new Error('Transaction failed');
    await this.refresh();
  } finally {
    runInAction(() => { this.cancellingOrderId = undefined; });
  }
}
```

> 注意：`cancellingOrderId` 用于在 UI 中显示取消中的状态，需要在 store 中添加这个属性：
> ```typescript
> cancellingOrderId?: bigint; // 正在取消的订单 ID
> ```

### Step 4: 从 Indexer 获取订单簿

通过 GraphQL 查询获取订单簿数据，比链上遍历效率高 10-100 倍。

项目中已封装好 `IndexerClient`（见 `frontend/store/IndexerClient.ts`），使用方式：

```typescript
import { client, GET_OPEN_ORDERS } from './IndexerClient';

// 查询订单
const result = await client.query(GET_OPEN_ORDERS, { trader: account }).toPromise();
if (result.data?.Order) {
    const orders = result.data.Order;
    // 处理订单数据...
}
```

> [!NOTE]
> Indexer 查询不消耗 Gas，适合高频读取场景。
