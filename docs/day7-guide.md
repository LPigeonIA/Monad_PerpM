# Day 7 - 清算系统与风控闭环（Liquidation）

本节目标：实现完整的清算系统，包括健康度判定 `canLiquidate()`、清算执行 `liquidate()`、以及 Keeper 机器人扫描风险账户。

---

## 1) 学习目标

完成本节后，你将能够：

- 理解永续合约清算机制的作用：保护系统免受坏账影响。
- 实现 `canLiquidate()`：判断账户健康度。
- 实现 `liquidate()`：强制平仓并分配清算费。
- 实现 `_matchLiquidationSell/Buy()`：清算市价撮合。
- 理解部分清算与完全清算的区别。

---

## 2) 前置准备

Day 7 建立在 Day 6 之上，请先确认：

- Day 1-6 功能已实现
- `settleFunding()` 和 `_applyFunding()` 可用
- `_unrealizedPnl()` 可用

```bash
cd contract
forge test --match-contract "Day1|Day2|Day3|Day4|Day6" -v
```

---

## 3) 当天完成标准

- `forge test --match-contract Day7 -vvv` 全部通过（5 个测试）
- 健康账户无法被清算
- 不健康账户可被清算，持仓归零
- 清算者获得清算费奖励
- 被清算者的挂单被自动取消
- 部分清算如仍不健康则 revert

---

## 4) 开发步骤（边理解边写代码）

### Step 1: 理解清算机制

清算发生在账户**保证金不足以维持持仓**时：

```
MarginBalance = FreeMargin + RealizedPnL + UnrealizedPnL
MaintenanceRequired = PositionValue × (MaintenanceBps + LiquidationFeeBps) / 10000

如果 MarginBalance < MaintenanceRequired → 可清算
```

---

### Step 2: 实现 `canLiquidate()`

修改：

- `contract/src/modules/LiquidationModule.sol`

```solidity
function canLiquidate(address trader) public view virtual returns (bool) {
    Position memory p = accounts[trader].position;
    if (p.size == 0) return false;

    uint256 markPrice = _calculateMarkPrice(indexPrice);
    
    int256 unrealized = _unrealizedPnl(p);
    
    int256 marginBalance = int256(accounts[trader].margin) + unrealized;
    
    uint256 priceBase = markPrice == 0 ? p.entryPrice : markPrice;
    uint256 positionValue = SignedMath.abs(int256(priceBase) * p.size) / 1e18;
    
    // Binance Style: Maintenance + Liquidation Fee 作为触发线
    uint256 maintenance = (positionValue * (maintenanceMarginBps + liquidationFeeBps)) / 10_000;
    
    return marginBalance < int256(maintenance);
}
```

---

### Step 3: 实现 `_clearTraderOrders()` 和 `_removeOrders()`

```solidity
function _clearTraderOrders(address trader) internal {
    bestBuyId = _removeOrders(bestBuyId, trader);
    bestSellId = _removeOrders(bestSellId, trader);
}

function _removeOrders(uint256 headId, address trader) internal returns (uint256 newHead) {
    newHead = headId;
    uint256 current = headId;
    uint256 prev = 0;

    while (current != 0) {
        Order storage o = orders[current];
        uint256 next = o.next;
        if (o.trader == trader) {
            if (prev == 0) {
                newHead = next;
            } else {
                orders[prev].next = next;
            }
            pendingOrderCount[trader]--;  // 更新挂单计数
            emit OrderRemoved(o.id);
            delete orders[current];
            current = next;
            continue;
        }
        prev = current;
        current = next;
    }
}
```

---

### Step 4: 实现 `liquidate()`

修改：

- `contract/src/modules/LiquidationModule.sol`

```solidity
function liquidate(address trader, uint256 amount) external virtual nonReentrant {
    require(msg.sender != trader, "cannot self-liquidate");
    require(markPrice > 0, "mark price unset");
    
    _applyFunding(trader);
    require(canLiquidate(trader), "position healthy");
    
    _clearTraderOrders(trader);

    Position storage p = accounts[trader].position;
    uint256 sizeAbs = SignedMath.abs(p.size);
    
    // amount=0 表示全部清算
    uint256 liqAmount = amount == 0 ? sizeAbs : Math.min(amount, sizeAbs);

    // 1. 执行市价平仓
    if (p.size > 0) {
        Order memory closeOrder = Order(0, trader, false, 0, liqAmount, liqAmount, block.timestamp, 0);
        _matchLiquidationSell(closeOrder);
    } else {
        Order memory closeOrder = Order(0, trader, true, 0, liqAmount, liqAmount, block.timestamp, 0);
        _matchLiquidationBuy(closeOrder);
    }
    
    // 2. 计算并转移清算费
    uint256 notional = (liqAmount * markPrice) / 1e18;
    uint256 fee = (notional * liquidationFeeBps) / 10_000;
    if (fee < minLiquidationFee) fee = minLiquidationFee;
    
    // 从被清算者扣除，给清算者
    if (accounts[trader].margin >= fee) {
        accounts[trader].margin -= fee;
        accounts[msg.sender].margin += fee;
    } else {
        // 坏账情况：被清算者保证金不足，清算者只能获得剩余部分
        uint256 available = accounts[trader].margin;
        accounts[trader].margin = 0;
        accounts[msg.sender].margin += available;
    }
    
    emit Liquidated(trader, msg.sender, liqAmount, fee);
    
    // 3. H-1 安全检查：部分清算后验证
    // 防止攻击者反复小额清算提取费用
    Position storage pAfterLiq = accounts[trader].position;
    if (pAfterLiq.size != 0) {
        require(!canLiquidate(trader), "must fully liquidate unhealthy position");
    }
}
```

---

### Step 5: 实现清算撮合函数

继续在 `LiquidationModule.sol` 中添加：

```solidity
function _matchLiquidationSell(Order memory incoming) internal {
    while (incoming.amount > 0 && bestBuyId != 0) {
        Order storage head = orders[bestBuyId];
        
        uint256 matched = Math.min(incoming.amount, head.amount);
        _executeTrade(head.trader, incoming.trader, head.id, 0, matched, head.price);

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
}

function _matchLiquidationBuy(Order memory incoming) internal {
    while (incoming.amount > 0 && bestSellId != 0) {
        Order storage head = orders[bestSellId];
        
        uint256 matched = Math.min(incoming.amount, head.amount);
        _executeTrade(incoming.trader, head.trader, 0, head.id, matched, head.price);

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
}
```

---

## 5) 解析：为什么这样写

### 5.1 清算触发条件

| 参数 | 说明 |
|------|------|
| MaintenanceMarginBps | 维持保证金率，如 50 bps = 0.5% |
| LiquidationFeeBps | 清算费率，如 125 bps = 1.25% |
| 触发线 | 两者之和，如 1.75% |

### 5.2 H-1: 部分清算保护

```solidity
if (amount < sizeAbs && canLiquidate(trader)) {
    revert("must fully liquidate unhealthy position");
}
```

防止攻击者反复小额清算提取费用而不真正解决风险。

### 5.3 坏账处理

```solidity
p.realizedPnl -= int256(debt);
```

如果账户余额不足支付清算费，差额记为负 realizedPnl（坏账）。这比让清算者空手而归更合理。

### 5.4 清算撮合 vs 普通撮合

| 普通撮合 | 清算撮合 |
|---------|---------|
| 检查价格匹配 | 不检查价格（市价） |
| 可能部分成交并挂单 | 只吃现有流动性 |
| 正常订单 ID | 订单 ID = 0 |

---

## 6) 测试与验证

### 6.1 运行合约测试

```bash
cd contract
forge test --match-contract Day7LiquidationTest -vvv
```

通过标准：5 个测试全部 `PASS`

测试用例覆盖：

1. `testLiquidationMarketClose` - 正常清算流程
2. `testLiquidationPartialFillRevertsIfStillUnhealthy` - H-1 保护
3. `testCannotLiquidateHealthyPosition` - 健康账户不可清算
4. `testLiquidationClearsOrders` - 清算时取消挂单
5. `testFuzzLiquidationPnL` - 模糊测试各种价格场景

### 6.2 端到端验证

```bash
cd contract
forge test --match-contract Day7IntegrationTest -vvv
```

验证完整流程：挂单 → 撮合 → 资金费 → 清算

---

## 7) 常见问题（排错思路）

1. **测试报错 "position healthy"**
   - 确认价格设置正确触发清算条件
   - 检查 `canLiquidate()` 计算逻辑

2. **清算费计算错误**
   - 确认 `liquidationFeeBps` 设置正确
   - 检查 notional 计算精度

3. **部分清算未 revert**
   - 确认 H-1 检查在清算后执行
   - 检查 `amount < sizeAbs` 条件

4. **挂单未清除**
   - 确认 `_clearTraderOrders()` 在清算前调用
   - 检查链表遍历逻辑

5. **坏账处理失败**
   - 确认 `realizedPnl` 类型为 `int256`
   - 检查负数处理逻辑

---

## 8) Indexer：索引清算事件

Day 7 会触发 `Liquidated` 事件。

### Step 1: 定义 Liquidation Schema

在 `indexer/schema.graphql` 中添加：

```graphql
type Liquidation @entity {
  id: ID!
  trader: String!
  liquidator: String!
  amount: BigInt!
  fee: BigInt!
  timestamp: Int!
  txHash: String!
}
```

### Step 2: 实现 Liquidated Handler

在 `indexer/src/EventHandlers.ts` 中添加：

```typescript
Exchange.Liquidated.handler(async ({ event, context }) => {
    const entity: Liquidation = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        trader: event.params.trader,
        liquidator: event.params.liquidator,
        amount: event.params.amount,
        fee: event.params.fee,
        timestamp: event.block.timestamp,
        txHash: event.transaction.hash,
    };
    context.Liquidation.set(entity);
    
    // 清算后持仓应该归零或减少
    const position = await context.Position.get(event.params.trader);
    if (position) {
        const newSize = position.size > 0n 
            ? position.size - event.params.amount 
            : position.size + event.params.amount;
        context.Position.set({
            ...position,
            size: newSize,
        });
    }
});
```

---

## 9) 前端：健康度显示

在持仓表格中添加 Health 列，直观显示账户健康状态。

修改：

- `frontend/components/Positions.tsx`

### 9.1 在 displayPosition 中添加健康度计算

找到 `displayPosition` 的 `useMemo`，在返回对象中添加 `marginRatio`：

```typescript
// 在 displayPosition 计算中添加保证金率
const marginRatio = (() => {
    const marginBalance = freeMargin + pnl;  // margin + unrealizedPnl
    const positionValue = mark * absSize;
    if (positionValue === 0) return 100;
    return (marginBalance / positionValue) * 100;
})();

return {
    symbol: 'ETH',
    // ... 其他字段
    marginRatio,  // 添加这行
};
```

### 9.2 在表头添加 Health 列

```tsx
<tr className="text-[10px] text-gray-500 uppercase tracking-wider">
    <th className="pb-3 pl-2">Symbol</th>
    <th className="pb-3 text-right">Size</th>
    <th className="pb-3 text-right">Entry Price</th>
    <th className="pb-3 text-right">Mark Price</th>
    <th className="pb-3 text-right">Liq. Price</th>
    <th className="pb-3 text-right">Health</th>  {/* 添加 */}
    <th className="pb-3 text-right">PnL (ROE%)</th>
</tr>
```

### 9.3 在数据行显示健康度

在 Liq. Price 和 PnL 之间添加 Health 列：

```tsx
{/* Health 列 - 添加在 Liq. Price 之后 */}
<td className="py-3 text-right font-mono">
    <span className={
        displayPosition.marginRatio < 2 ? 'text-red-500' :
        displayPosition.marginRatio < 5 ? 'text-yellow-500' :
        'text-green-500'
    }>
        {displayPosition.marginRatio.toFixed(1)}%
    </span>
</td>
```

颜色含义：
- 🟢 绿色 (>5%): 安全
- 🟡 黄色 (2-5%): 警告
- 🔴 红色 (<2%): 危险（清算线 1.75%）

---

## 10) 小结 & 课程完成

今天我们完成了"清算系统"，这是 DEX 风控的最后一环：

- `canLiquidate()`：健康度判定
- `liquidate()`：清算执行
- `_matchLiquidationSell/Buy()`：市价平仓撮合
- Indexer：索引 `Liquidated` 事件
- 前端：危险预警 Toast 和健康度显示

至此，7 天课程全部完成！系统具备：

1. ✅ 资金管理（Day 1）- 合约 + Indexer + 前端
2. ✅ 订单簿（Day 2）- 合约 + Indexer + 前端
3. ✅ 撮合引擎（Day 3）- 合约 + Indexer + 前端
4. ✅ 价格服务（Day 4）- 合约 + Keeper + 前端
5. ✅ K 线图表（Day 5）- Indexer + 前端
6. ✅ 资金费率（Day 6）- 合约 + Indexer + 前端
7. ✅ 清算系统（Day 7）- 合约 + Indexer + 前端

**恭喜你完成了一个完整的永续合约 DEX！**
