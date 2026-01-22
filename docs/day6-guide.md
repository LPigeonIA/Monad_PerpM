# Day 6 - 资金费率机制（Funding Rate）

本节目标：实现币安风格的资金费率机制，包括全局 `settleFunding()` 计算费率，用户级 `_applyFunding()` 结算资金费，以及 Keeper 定时触发结算。

---

## 1) 学习目标

完成本节后，你将能够：

- 理解永续合约资金费率的作用：锚定现货价格。
- 实现 `settleFunding()`：币安公式计算资金费率。
- 实现 `_applyFunding()`：根据用户持仓计算应付/应收资金费。
- 实现 `_unrealizedPnl()`：计算未实现盈亏。
- 配置 Keeper 定时触发资金费率结算。

---

## 2) 前置准备

Day 6 建立在 Day 5 之上，请先确认：

- Day 1-5 功能已实现
- `updateIndexPrice()` 和 `_calculateMarkPrice()` 可用

你可以先跑：

```bash
cd contract
forge test --match-contract "Day1|Day2|Day3|Day4" -v
```

---

## 3) 当天完成标准

- `forge test --match-contract Day6FundingTest -vvv` 全部通过（11 个测试）
- 多头在 mark > index 时支付资金费
- 空头在 mark < index 时支付资金费
- 资金费按 interval 累计
- 资金费有上限保护（maxFundingRatePerInterval）
- 前端显示"未结资金费"与"强平价格"

---

## 4) 开发步骤（边理解边写代码）

### Step 1: 理解资金费率机制

永续合约没有到期日，需要"资金费率"让价格锚定现货：

| 情况 | 资金费方向 | 目的 |
|------|-----------|------|
| Mark > Index | 多头付空头 | 压低合约价格 |
| Mark < Index | 空头付多头 | 抬高合约价格 |

**币安公式：**

```
FundingRate = PremiumIndex + clamp(InterestRate - PremiumIndex, -0.05%, +0.05%)
PremiumIndex = (MarkPrice - IndexPrice) / IndexPrice
InterestRate = 0.01% (固定)
```

---

### Step 2: 实现 `settleFunding()`

修改：

- `contract/src/modules/FundingModule.sol`

```solidity
function settleFunding() public virtual {
    // Step 1: 检查是否已过 fundingInterval
    if (block.timestamp < lastFundingTime + fundingInterval) return;
    if (indexPrice == 0) return;

    // Step 2: 计算 Premium Index
    int256 mark = int256(markPrice);
    int256 index = int256(indexPrice);
    int256 premiumIndex = ((mark - index) * 1e18) / index;

    // Step 3: 应用利率和钳位
    int256 interestRate = 1e14; // 0.01%
    int256 clampRange = 5e14;   // 0.05%
    
    int256 diff = interestRate - premiumIndex;
    int256 clamped = diff;
    if (diff > clampRange) clamped = clampRange;
    if (diff < -clampRange) clamped = -clampRange;
    
    int256 rate = premiumIndex + clamped;

    // Step 4: 应用全局上限
    if (maxFundingRatePerInterval > 0) {
        if (rate > maxFundingRatePerInterval) rate = maxFundingRatePerInterval;
        if (rate < -maxFundingRatePerInterval) rate = -maxFundingRatePerInterval;
    }

    // Step 5: 累加到全局费率
    cumulativeFundingRate += rate;
    lastFundingTime = block.timestamp;

    // Step 6: 触发事件
    emit FundingUpdated(cumulativeFundingRate, block.timestamp);
}
```

---

### Step 3: 实现 `_applyFunding()`

```solidity
function _applyFunding(address trader) internal virtual {
    Account storage a = accounts[trader];
    Position storage p = a.position;
    
    // Step 1: 无持仓则更新 index 并返回
    if (p.size == 0) {
        lastFundingIndex[trader] = cumulativeFundingRate;
        return;
    }

    // Step 2: 确保全局费率最新
    settleFunding();
    
    // Step 3: 计算费率差值
    int256 diff = cumulativeFundingRate - lastFundingIndex[trader];
    if (diff == 0) return;

    // Step 4: 计算应付金额
    // Payment = Size * MarkPrice * Diff / 1e36
    int256 payment = (int256(p.size) * int256(markPrice) * diff) / 1e36;
    
    // Step 5: 更新用户保证金
    uint256 free = a.margin;
    if (payment > 0) {
        // 需要支付
        uint256 pay = uint256(payment);
        if (pay > free) {
            // debt 情况：margin 不足，全部扣除
            a.margin = 0;
        } else {
            a.margin = free - pay;
        }
    } else if (payment < 0) {
        // 获得收入
        uint256 credit = uint256(-payment);
        a.margin = free + credit;
    }
    
    // Step 6: 更新用户费率 index
    lastFundingIndex[trader] = cumulativeFundingRate;
    
    // Step 7: 触发事件
    emit FundingPaid(trader, payment);
}

/**
 * 外部结算接口：手动为特定账户结算资金费
 */
function settleUserFunding(address trader) external virtual {
    _applyFunding(trader);
}

/**
 * 参数更新接口：设置结算周期与费率上限 (仅管理员)
 */
function setFundingParams(uint256 interval, int256 maxRatePerInterval) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
    require(interval > 0, "interval=0");
    require(maxRatePerInterval >= 0, "cap<0");
    fundingInterval = interval;
    maxFundingRatePerInterval = maxRatePerInterval;
    emit FundingParamsUpdated(interval, maxRatePerInterval);
}
```

---

### Step 4: 实现 `_unrealizedPnl()`

```solidity
function _unrealizedPnl(Position memory p) internal view returns (int256) {
    if (p.size == 0) return 0;
    int256 priceDiff = int256(markPrice) - int256(p.entryPrice);
    if (p.size < 0) priceDiff = -priceDiff;  // 空头方向需要取反
    return (priceDiff * int256(SignedMath.abs(p.size))) / 1e18;
}
```

---

### Step 5: 实现 `_ensureWithdrawKeepsMaintenance()`

修改：

- `contract/src/modules/MarginModule.sol`

Day 1 中我们预留了这个函数的 TODO，现在有了 `_unrealizedPnl()` 和维持保证金参数，可以实现完整的提现检查逻辑：

```solidity
/// @notice 确保提现后仍满足维持保证金要求
/// @dev Day 6: 提现时的维持保证金检查
function _ensureWithdrawKeepsMaintenance(address trader, uint256 amount) internal view {
    Position memory p = accounts[trader].position;

    // 1. 如果没有持仓，直接返回
    if (p.size == 0) return;

    // 2. 计算提现后的 marginBalance
    int256 marginAfter = int256(accounts[trader].margin) - int256(amount);
    int256 unrealized = _unrealizedPnl(p);
    int256 marginBalance = marginAfter + unrealized;

    // 3. 计算持仓价值和维持保证金
    uint256 priceBase = markPrice == 0 ? p.entryPrice : markPrice;
    uint256 positionValue = SignedMath.abs(int256(priceBase) * p.size) / 1e18;
    uint256 maintenance = (positionValue * maintenanceMarginBps) / 10_000;

    // 4. require(marginBalance >= maintenance)
    require(marginBalance >= int256(maintenance), "withdraw would trigger liquidation");
}
```

预期行为：

- 无持仓时提现不受限制
- 有持仓时，提现后的保证金余额必须大于维持保证金
- 如果提现会导致保证金不足，交易会 revert

---

### Step 6: 实现 FundingKeeper 定时结算

修改：`keeper/src/services/FundingKeeper.ts`

FundingKeeper 负责定时检查是否需要结算全局资金费率，在 `checkAndSettle` 方法中实现：

```typescript
private async checkAndSettle() {
    try {
        // Step 1: 读取合约状态
        const lastFundingTime = await publicClient.readContract({
            address: ADDRESS as `0x${string}`,
            abi: EXCHANGE_ABI,
            functionName: 'lastFundingTime',
        }) as bigint;

        const fundingInterval = await publicClient.readContract({
            address: ADDRESS as `0x${string}`,
            abi: EXCHANGE_ABI,
            functionName: 'fundingInterval',
        }) as bigint;

        // Step 2: 判断是否需要结算
        const now = BigInt(Math.floor(Date.now() / 1000));
        if (now < lastFundingTime + fundingInterval) {
            console.log(`[FundingKeeper] Not yet time. Next settlement in ${Number(lastFundingTime + fundingInterval - now)}s`);
            return;
        }

        // Step 3: 调用 settleFunding
        console.log('[FundingKeeper] Time to settle funding...');
        const hash = await walletClient.writeContract({
            address: ADDRESS as `0x${string}`,
            abi: EXCHANGE_ABI,
            functionName: 'settleFunding',
            args: []
        });
        await publicClient.waitForTransactionReceipt({ hash });
        console.log(`[FundingKeeper] Settlement tx: ${hash}`);

    } catch (e) {
        console.error('[FundingKeeper] Error:', e);
    }
}
```

**工作原理**：
1. 读取 `lastFundingTime` 和 `fundingInterval`
2. 判断 `now >= lastFundingTime + fundingInterval`
3. 满足条件时调用 `settleFunding()` 触发全局费率更新

---

### Step 7: 前端资金费与强平展示

#### 6.1 在 Store 中计算预测资金费率
在 `exchangeStore.tsx` 的 `refresh` 中增加币安公式计算：

```typescript
const m = Number(formatEther(mark));
const i = Number(formatEther(index));
const premiumIndex = (m - i) / i;
const interestRate = 0.0001; // 0.01%
const clampRange = 0.0005;   // 0.05%

let diff = interestRate - premiumIndex;
if (diff > clampRange) diff = clampRange;
if (diff < -clampRange) diff = -clampRange;

this.fundingRate = premiumIndex + diff;
```

---

## 5) 解析：为什么这样写

### 5.1 为什么用累计费率（cumulativeFundingRate）？

**问题**：如果每次结算都遍历所有持仓用户扣钱，gas 成本极高。

**解决方案**：用**累计费率 + 延迟结算**模式，将结算分为两个部分：

| 函数 | 职责 | 频率 |
|------|------|------|
| `settleFunding()` | 计算并累加全局费率 | 每 interval 一次（如每小时） |
| `_applyFunding(trader)` | 根据费率差值结算用户保证金 | 用户操作时触发 |

**核心数据结构**：
```
全局: cumulativeFundingRate = r1 + r2 + r3 + ...  (不断累加)
用户: lastFundingIndex[trader] = 用户上次结算时的全局费率
```

当用户操作时，一次性结算所有累计的资金费：
```
Payment = Size × Mark × (cumulativeFundingRate - lastFundingIndex[trader])
```

**时间线示例**：

```
─────────────────────────────────────────────────────────────►
    T1         T2         T3         T4         T5
    │          │          │          │          │
    ├─ r=1% ──►├─ r=2% ──►├─ r=1% ──►├─ r=1% ──►│
    │          │          │          │          │
   Alice       │         Bob        Alice      Bob
   开仓        │         开仓       平仓       平仓
              累计=1%   累计=3%    累计=4%    累计=5%
```

**Alice 的结算**（T1 开仓，T4 平仓）：
- T1: Alice 开多仓，`lastFundingIndex[Alice] = 0`
- T4: Alice 平仓，触发 `_applyFunding(Alice)`
  - diff = 4% - 0% = **4%**
  - Alice 支付 4% 资金费

**Bob 的结算**（T3 开仓，T5 平仓）：
- T3: Bob 开多仓，此时全局累计已是 3%
  - 关键：`_applyFunding` 检测到 Bob 无持仓，直接设置 `lastFundingIndex[Bob] = 3%`
  - Bob 的"起点"从 3% 开始，**不需要支付之前累积的费用**
- T5: Bob 平仓
  - diff = 5% - 3% = **2%**
  - Bob 只支付 2% 资金费

**代码实现**（见 `_applyFunding`）：
```solidity
if (p.size == 0) {
    // 无持仓时，更新起点为当前全局费率
    lastFundingIndex[trader] = cumulativeFundingRate;
    return;
}
```

**好处**：
- 不需要每小时遍历所有用户
- 新用户只从开仓时刻开始计费
- 老用户即使很久不操作，一次结算即可算清所有累计费用

### 5.2 资金费公式详解

币安公式分解：

```
Rate = Premium + clamp(Interest - Premium, -0.05%, +0.05%)
```

| 场景 | Premium | Interest | Rate | 效果 |
|------|---------|----------|------|------|
| 合约溢价 10% | +0.10 | +0.0001 | ~+0.10 | 多头付空头 |
| 合约折价 5% | -0.05 | +0.0001 | ~-0.05 | 空头付多头 |
| 价格平衡 | 0 | +0.0001 | +0.0001 | 多头付空头（极小） |

### 5.3 为什么需要 maxFundingRatePerInterval？

极端行情下，资金费可能过大导致用户瞬间爆仓。设置上限保护用户。

### 5.4 Payment 计算精度

```solidity
Payment = (Size × Mark × Diff) / 1e36
```

- Size: 1e18 精度
- Mark: 1e18 精度  
- Diff: 1e18 精度
- 结果: (1e18 × 1e18 × 1e18) / 1e36 = 1e18 (MON)

---

## 6) 测试与验证

### 6.1 运行合约测试

```bash
cd contract
forge test --match-contract Day6FundingTest -vvv
```

通过标准：11 个测试全部 `PASS`

测试用例覆盖：

**资金费率测试：**
1. `testFundingFlowsFromLongToShort` - Mark 高于 Index，多头付空头
2. `testSettleFundingNoIndexPriceSkips` - Index 为 0 时跳过
3. `testFundingAccumulatesAcrossIntervals` - 跨 interval 累加
4. `testFundingSequentialEntrantsAccruesCorrectly` - 多用户分批进入
5. `testFundingCapAndIntervalChange` - 费率上限保护
6. `testFundingShortPaysWhenMarkBelowIndex` - 空头付多头

**提现维持保证金测试（Step 5）：**
7. `testWithdrawNoPositionAllowsFullWithdrawal` - 无持仓可全额提取
8. `testWithdrawWithProfitablePositionSuccess` - 有盈利持仓提取成功
9. `testWithdrawRevertsWhenWouldTriggerLiquidation` - 提取会触发清算时 revert
10. `testWithdrawAtExactMaintenanceBoundary` - 刚好在维持保证金边界成功
11. `testWithdrawOneWeiBelowMaintenanceReverts` - 比边界多提 1 wei 时 revert

### 6.2 前端验证

```bash
./quickstart.sh
```

打开 `http://localhost:3000`，验证资金费率显示：

**Step 1: 检查资金费率显示**

1. 在页面顶部或价格区域，应该能看到 "Funding Rate" 字段
2. 当 Mark Price > Index Price 时，资金费率为正（多头付空头）
3. 当 Mark Price < Index Price 时，资金费率为负（空头付多头）

**Step 2: 验证资金费率计算**

假设当前价格：
- Mark Price: 101 MON
- Index Price: 100 MON

预期资金费率计算：
```
Premium = (101 - 100) / 100 = 0.01 (1%)
diff = 0.0001 - 0.01 = -0.0099, clamp 到 -0.0005
Rate = 0.01 + (-0.0005) = 0.0095 (0.95%)
```

页面应显示约 `0.95%` 的资金费率。

> 注意：合约有 `maxFundingRatePerInterval` 上限保护，极端价格偏离时费率会被 cap。

**Step 3: 测试资金费结算（可选）**

由于默认 `fundingInterval` 为 1 小时，实际测试时可以：

1. 在合约部署后，用管理员调用缩短 interval：
   ```bash
   cast send $EXCHANGE "setFundingParams(uint256,int256)" 60 "50000000000000000" \
     --rpc-url $RPC --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
   ```
   这将 interval 设为 60 秒，maxRate 设为 5%。

2. 下单建仓后等待 1 分钟
3. 刷新页面，观察保证金变化

**预期结果：**
- 多头（Mark > Index）：保证金减少
- 空头（Mark > Index）：保证金增加

### 6.3 Keeper 验证

启动 Keeper 服务验证 FundingKeeper 是否正常工作：

```bash
cd keeper && pnpm start
```

**预期日志输出：**

```
--- Monad Exchange Keeper Service ---
[PriceKeeper] Starting price updates every 1000ms...
[FundingKeeper] Starting funding settlement checks every 60000ms...
[FundingKeeper] Not yet time. Next settlement in 3542s
```

如果 `fundingInterval` 已到期且 `indexPrice > 0`，会看到：

```
[FundingKeeper] Time to settle funding...
[FundingKeeper] Settlement tx: 0x...
```

> 注意：默认 `fundingInterval` 为 1 小时。测试时可用 `setFundingParams` 缩短为 60 秒。

---

## 7) 常见问题（排错思路）

1. **测试报错 "funding not accumulated"**
   - 确认 `settleFunding()` 中正确累加 `cumulativeFundingRate += rate`
   - 确认 `lastFundingTime = block.timestamp` 已更新

2. **Payment 计算结果为 0**
   - 检查精度：`/ 1e36` 而不是 `/ 1e18`
   - 确认 `diff != 0`

3. **用户资金费未扣除**
   - 确认调用了 `settleUserFunding(trader)`
   - 检查 `lastFundingIndex[trader]` 是否更新

4. **资金费方向错误**
   - 检查 `payment > 0` 表示用户需要支付
   - 多头在 mark > index 时 payment > 0

5. **maxFundingRatePerInterval 不生效**
   - 确认 `setFundingParams` 被调用
   - 检查正负方向都有 cap

---

## 8) Indexer：索引资金费率事件

Day 6 会触发 `FundingUpdated` 和 `FundingPaid` 事件。

### Step 1: 配置事件监听

在 `indexer/config.yaml` 的 `events` 列表中添加：

```yaml
      - event: FundingUpdated(int256 cumulativeFundingRate, uint256 timestamp)
      - event: FundingPaid(address indexed trader, int256 amount)
```

### Step 2: 定义 FundingEvent Schema

在 `indexer/schema.graphql` 中添加（注意：修改后需运行 `pnpm codegen`）：

```graphql
type FundingEvent @entity {
  id: ID!
  eventType: String!  # "GLOBAL_UPDATE" 或 "USER_PAID"
  trader: String      # 仅 USER_PAID 时有值
  cumulativeRate: BigInt
  payment: BigInt     # 仅 USER_PAID 时有值
  timestamp: Int!
}
```

### Step 3: 实现 Funding Event Handlers

在 `indexer/src/EventHandlers.ts` 中添加（先添加 import）：

```typescript
import { Exchange, MarginEvent, Order, Trade, Position, Candle, LatestCandle, FundingEvent } from "../generated";
```

然后添加 handlers：

```typescript
Exchange.FundingUpdated.handler(async ({ event, context }) => {
    const entity: FundingEvent = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        eventType: "GLOBAL_UPDATE",
        trader: null,
        cumulativeRate: event.params.cumulativeFundingRate,
        payment: null,
        timestamp: event.block.timestamp,
    };
    context.FundingEvent.set(entity);
});

Exchange.FundingPaid.handler(async ({ event, context }) => {
    const entity: FundingEvent = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        eventType: "USER_PAID",
        trader: event.params.trader,
        cumulativeRate: null,
        payment: event.params.payment,
        timestamp: event.block.timestamp,
    };
    context.FundingEvent.set(entity);
});
```

### Step 4: 验证 Indexer

**启动服务：**

```bash
# 终端 1: 启动本地链并部署合约
./scripts/run-anvil-deploy.sh

# 终端 2: 启动 Indexer
cd indexer && pnpm codegen && pnpm dev
```

**触发资金费率事件：**

资金费率需要满足两个条件才会触发：
1. `indexPrice > 0`（需要先设置价格）
2. 时间过了 `fundingInterval`（默认 1 小时）

**权限说明：**
- `updateIndexPrice()` - 需要 `OPERATOR_ROLE`（Anvil Account 0）
- `setFundingParams()` - 需要 `ADMIN_ROLE`（部署者地址）

测试时可以用 `cast` 手动触发：

```bash
# 设置环境变量
export EXCHANGE=<部署的合约地址>
export RPC=http://127.0.0.1:8545
export PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80  # Account 0 (OPERATOR)

# Step 1: 设置价格（使用 OPERATOR 账户）
cast send $EXCHANGE "updateIndexPrice(uint256)" 100000000000000000000 \
  --rpc-url $RPC --private-key $PK

# Step 2: 缩短 fundingInterval 为 10 秒（需要 ADMIN 权限）
# 注意：ADMIN 是部署者地址，从部署日志获取 private key
export DEPLOYER_PK=<部署日志中的 ephemeral deployer key>
cast send $EXCHANGE "setFundingParams(uint256,int256)" 10 50000000000000000 \
  --rpc-url $RPC --private-key $DEPLOYER_PK

# Step 3: 等待超过 interval
sleep 12

# Step 4: 触发资金费结算
cast send $EXCHANGE "settleFunding()" --rpc-url $RPC --private-key $PK

# Step 5: 检查累计费率
cast call $EXCHANGE "cumulativeFundingRate()" --rpc-url $RPC
```

**GraphQL 验证：**

打开 http://localhost:8080/console 执行查询：

```graphql
query {
  FundingEvent(order_by: { timestamp: desc }, limit: 10) {
    id
    eventType
    trader
    cumulativeRate
    payment
    timestamp
  }
}
```

**预期结果示例：**

```json
{
  "data": {
    "FundingEvent": [
      {
        "id": "0x...-0",
        "eventType": "GLOBAL_UPDATE",
        "trader": null,
        "cumulativeRate": "499500000000000000",
        "payment": null,
        "timestamp": 1234567890
      },
      {
        "id": "0x...-1",
        "eventType": "USER_PAID",
        "trader": "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        "cumulativeRate": null,
        "payment": "14985000000000000000000",
        "timestamp": 1234567890
      }
    ]
  }
}
```

---

## 9) 前端：资金费显示与强平价格

### 9.1 资金费率预估计算

在 `frontend/store/exchangeStore.tsx` 的 `refresh` 函数中添加：

```typescript
// 在 refresh 函数中
const m = Number(formatEther(markPrice));
const i = Number(formatEther(indexPrice));
const premiumIndex = (m - i) / i;
const interestRate = 0.0001; // 0.01%
const clampRange = 0.0005;   // 0.05%

let diff = interestRate - premiumIndex;
if (diff > clampRange) diff = clampRange;
if (diff < -clampRange) diff = -clampRange;

this.fundingRate = premiumIndex + diff;
```

---

## 10) 小结 & 为 Day 7 铺垫

今天我们完成了"资金费率机制"：

- `settleFunding()`：全局费率计算（币安公式）
- `_applyFunding()`：用户级资金费结算
- `_unrealizedPnl()`：未实现盈亏计算
- Indexer：索引 `FundingUpdated` 和 `FundingPaid` 事件
- 前端：显示资金费率

Day 7 会在此基础上实现"清算系统"：

- `canLiquidate()`：健康度判定
- `liquidate()`：清算执行
- Keeper 扫描风险账户
- 完整风控闭环测试
