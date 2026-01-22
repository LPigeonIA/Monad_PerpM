# Day 4 - 价格服务与标记价格（Pricing & Mark Price）

本节目标：引入价格服务层，实现 `updateIndexPrice()` 让外部 Keeper 推送价格到链上，并通过 `_calculateMarkPrice()` 计算标记价格（三价取中 + 偏离保护），为后续的资金费率和清算打下基础。

---

## 1) 学习目标

完成本节后，你将能够：

- 理解"指数价格（Index Price）"与"标记价格（Mark Price）"的区别与用途。
- 实现 `updateIndexPrice()`：仅限 Operator 角色调用的价格推送入口。
- 实现 `_calculateMarkPrice()`：三价取中逻辑 + 5% 偏离钳位。
- 编写 Keeper 服务从 Binance/Pyth 获取价格并推送上链。

---

## 2) 前置准备

Day4 建立在 Day3 之上，请先确认：

- Day1 / Day2 / Day3 测试已通过
- `_executeTrade` / `_updatePosition` 已实现（成交与持仓逻辑可用）

你可以先跑：

```bash
cd contract
forge test --match-contract Day3MatchingTest -vvv
```

---

## 3) 当天完成标准

- `forge test --match-contract Day4PriceUpdateTest -vvv` 全部通过（5 个测试）
- Operator 可成功调用 `updateIndexPrice()`
- 非 Operator 调用 `updateIndexPrice()` 必须 revert
- 当订单簿为空时，`markPrice == indexPrice`
- 当订单簿有挂单时，`markPrice` 使用三价取中逻辑
- 前端 Header 显示实时 Index Price 与 Mark Price

---

## 4) 开发步骤

### Step 1: 读测试，先把规则写清楚

打开：

- `contract/test/Day4PriceUpdate.t.sol`

你会看到四类要求：

1. **Operator 可更新价格**：调用后 `indexPrice` 与 `markPrice` 更新
2. **非 Operator 被拒绝**：普通用户调用必须 revert
3. **更新触发事件**：`MarkPriceUpdated(indexPrice, markPrice)` 必须触发
4. **价格影响保证金检查**：有持仓时提现需要使用最新价格判断

---

### Step 2: 理解 Index Price 与 Mark Price

| 概念 | 说明 | 来源 |
|------|------|------|
| **Index Price** | 现货市场加权平均价 | Binance/OKX 等 CEX |
| **Mark Price** | 合约结算用价 | 订单簿 + Index 综合计算 |
| **用途** | 资金费率、清算、盈亏计算 | 防止价格操纵 |

为什么不直接用 Index Price？

- 链上订单簿价格可能与外部市场有偏差
- 使用"三价取中"可减少单一价格源的操纵风险
- 设置 ±5% 偏离上限防止极端情况

---

### Step 3: 实现 `updateIndexPrice()`

修改：

- `contract/src/modules/PricingModule.sol`

这个函数需要：

1. 验证调用者有 `OPERATOR_ROLE`（已通过 `onlyRole` 修饰器）
2. 更新 `indexPrice` 存储变量
3. 调用 `_calculateMarkPrice()` 计算标记价
4. 更新 `markPrice` 存储变量
5. 触发 `MarkPriceUpdated` 事件

```solidity
function updateIndexPrice(uint256 newIndexPrice) external virtual onlyRole(OPERATOR_ROLE) {
    indexPrice = newIndexPrice;
    markPrice = _calculateMarkPrice(newIndexPrice);
    emit MarkPriceUpdated(markPrice, indexPrice);
}
```

预期行为：

- `exchange.indexPrice()` 返回最新推送的价格
- `exchange.markPrice()` 返回经过计算的标记价

---

### Step 4: 实现 `_calculateMarkPrice()`（三价取中）

仍在：

- `contract/src/modules/PricingModule.sol`

核心逻辑：

1. 获取订单簿的 `bestBid`（最高买价）和 `bestAsk`（最低卖价）
2. 如果订单簿为空（买卖盘都没有），直接返回 `indexPrice`
3. 计算三价取中：`median(bestBid, bestAsk, indexPrice)`
4. 应用 ±5% 偏离保护：结果不能超过 `indexPrice * 1.05` 或低于 `indexPrice * 0.95`

```solidity
function _calculateMarkPrice(uint256 indexPrice_) internal view virtual returns (uint256) {
    uint256 bestBid = bestBuyId == 0 ? 0 : orders[bestBuyId].price;
    uint256 bestAsk = bestSellId == 0 ? 0 : orders[bestSellId].price;

    // If both empty, return index
    if (bestBid == 0 && bestAsk == 0) {
        return indexPrice_;
    }

    // If one side empty, use index for that side
    if (bestBid == 0) bestBid = indexPrice_;
    if (bestAsk == 0) bestAsk = indexPrice_;

    // Median of (Bid, Ask, Index) using bubble sort
    uint256 a = bestBid;
    uint256 b = bestAsk;
    uint256 c = indexPrice_;
    
    if (a > b) (a, b) = (b, a);
    if (b > c) (b, c) = (c, b);
    if (a > b) (a, b) = (b, a);
    
    uint256 median = b;

    // ±5% Deviation Clamp
    uint256 maxDeviation = (indexPrice_ * 500) / 10_000;
    if (median > indexPrice_ + maxDeviation) return indexPrice_ + maxDeviation;
    if (indexPrice_ > maxDeviation && median < indexPrice_ - maxDeviation) return indexPrice_ - maxDeviation;

    return median;
}
```

---

### Step 5: 实现 Keeper 服务（TypeScript）

修改：

- `keeper/src/services/PriceKeeper.ts`

Keeper 需要定期执行以下操作：

1. 从外部 Pyth Network API 获取 ETH/USD 价格
2. 转换为合约精度（`1e18`）
3. 调用 `updateIndexPrice()` 推送到链上

参考实现（替换 `updatePrice` 函数内的 TODO）：

```typescript
private async updatePrice() {
    try {
        // 1. 从 Pyth 获取价格
        const res = await fetch(`https://hermes.pyth.network/v2/updates/price/latest?ids[]=${this.PYTH_ETH_ID}`);
        const data = await res.json();
        const priceInfo = data.parsed[0].price;

        // 2. 解析价格 (price = p * 10^expo)
        const p = BigInt(priceInfo.price);
        const expo = priceInfo.expo;

        // 3. 转换为 1e18 精度 (Wei)
        // 公式: p * 10^expo * 10^18 = p * 10^(18 + expo)
        const priceWei = p * (10n ** BigInt(18 + expo));

        console.log(`[PriceKeeper] Fetched ETH price: $${Number(p) * Math.pow(10, expo)} -> ${priceWei} wei`);

        // 4. 调用合约更新价格
        const hash = await walletClient.writeContract({
            address: ADDRESS as `0x${string}`,
            abi: EXCHANGE_ABI,
            functionName: 'updateIndexPrice',
            args: [priceWei]
        });
        await publicClient.waitForTransactionReceipt({ hash });
        console.log(`[PriceKeeper] Price updated on-chain, tx: ${hash}`);

    } catch (e) {
        console.error('[PriceKeeper] Error updating price:', e);
    }
}
```

> **注意**：运行 Keeper 前需要设置环境变量 `EXCHANGE_ADDRESS`，或在 `keeper/.env` 中配置。

---

### Step 6: 前端价格展示

确认以下组件已正确显示价格。如果不显示，说明 Keeper 未运行或合约函数未实现：

- **Header 组件**：显示 Index Price 和 Mark Price
- **MarketStats 组件**：显示价格相关统计

修改文件：`frontend/store/exchangeStore.tsx`

在 `refresh` 函数中（约第 340 行），找到读取 `markPrice` 的代码块，在 `Promise.all` 中增加 `indexPrice` 的读取：

```typescript
// 在 refresh 函数内
// 修改前：
// const [mp, im] = await Promise.all([...]);

// 修改后：
const [mp, ip, im] = await Promise.all([
    publicClient.readContract({
        address: EXCHANGE_ADDRESS,
        abi: EXCHANGE_ABI,
        functionName: 'markPrice',
    }),
    publicClient.readContract({          // [新增]
        address: EXCHANGE_ADDRESS,
        abi: EXCHANGE_ABI,
        functionName: 'indexPrice',
    }),
    publicClient.readContract({
        address: EXCHANGE_ADDRESS,
        abi: EXCHANGE_ABI,
        functionName: 'initialMarginBps',
    }),
]);

runInAction(() => {
    this.markPrice = mp;
    this.indexPrice = ip;                // [新增]
    this.initialMarginBps = im;
});
```

---

## 5) 解析：为什么这样写

### 5.1 为什么需要 Operator 角色？

价格更新是敏感操作：

- 错误的价格会导致用户被错误清算
- 恶意价格操纵可套取资金

因此使用 AccessControl 的 `OPERATOR_ROLE` 限制：

```solidity
function updateIndexPrice(uint256 newIndexPrice) external virtual onlyRole(OPERATOR_ROLE) {
```

生产环境中，Operator 通常是：
- 可信的 Keeper 服务
- 多签钱包
- DAO 控制的合约

### 5.2 三价取中的原理

```
median(bestBid, bestAsk, indexPrice)
```

| 场景 | bestBid | bestAsk | indexPrice | 结果 |
|------|---------|---------|------------|------|
| 价格合理 | 2695 | 2705 | 2700 | 2700 |
| 买压大 | 2750 | 2760 | 2700 | 2750 |
| 卖压大 | 2640 | 2650 | 2700 | 2650 |
| 操纵买盘 | 3000 | 2705 | 2700 | **2705** |

最后一行是关键：即使有人恶意挂高价买单，中位数也会过滤掉极端值。

### 5.3 为什么需要 ±5% 偏离保护？

即使三价取中，如果买卖盘同时被操纵，标记价仍可能偏离真实价格。

钳位规则确保：
- `markPrice <= indexPrice * 1.05`
- `markPrice >= indexPrice * 0.95`

这样即使链上订单簿被操纵，标记价偏离外部市场的幅度也有上限。

### 5.4 Keeper 为什么用推送模式？

链上合约无法主动"拉取"外部价格（区块链是封闭系统）。

两种模式：

| 模式 | 说明 | 优缺点 |
|------|------|--------|
| **Push**（本课程） | Keeper 主动调用合约 | 简单，但依赖 Keeper 可用性 |
| **Pull**（Pyth） | 用户交易时带入价格证明 | 去中心化，但实现复杂 |

Day4 使用 Push 模式简化学习曲线。

---

## 6) 测试与验证

### 6.1 运行合约测试

```bash
cd contract
forge test --match-contract Day4PriceUpdateTest -vvv
```

通过标准：5 个测试全部 `PASS`

单独运行某个测试：

```bash
forge test --match-test testOperatorCanUpdatePrice -vvv
```

### 6.2 前端验证（必须）

启动本地环境：

```bash
./quickstart.sh
```

**环境变量设置**（从部署日志或 `frontend/.env.local` 获取合约地址）：

```bash
export EXCHANGE=0x...  # 替换为实际合约地址
export OPERATOR_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export RPC=http://localhost:8545
```

> 每次重启链后价格初始为 0，需要先初始化价格。

**验收路径 1：手动初始化并验证价格**

```bash
# 查看当前价格
cast to-unit $(cast call $EXCHANGE "indexPrice()" --rpc-url $RPC) ether

# 更新价格为 2500 USD
cast send $EXCHANGE "updateIndexPrice(uint256)" "2500000000000000000000" \
  --private-key $OPERATOR_KEY --rpc-url $RPC

# 验证更新成功
cast to-unit $(cast call $EXCHANGE "indexPrice()" --rpc-url $RPC) ether
```

打开 `http://localhost:3000`，确认 Header 显示 Index Price 和 Mark Price。

**验收路径 2：非 Operator 调用被拒绝**

```bash
# 使用非 Operator 账户（Bob）应该失败
cast send $EXCHANGE "updateIndexPrice(uint256)" "3000000000000000000000" \
  --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d \
  --rpc-url $RPC
# 预期：AccessControlUnauthorizedAccount 错误
```

**验收路径 3：Keeper 自动更新**

1. 配置合约地址（从部署日志或 `frontend/.env.local` 获取）：
   ```bash
   cd keeper
   echo "EXCHANGE_ADDRESS=0x..." > .env  # 替换为实际部署地址
   ```
2. 启动 Keeper 服务：`pnpm start`
3. 观察日志输出价格更新信息：
   ```
   [PriceKeeper] Fetched ETH price: $3245.34 -> 3245340000000000000000 wei
   [PriceKeeper] Price updated on-chain, tx: 0x...
   ```
4. 刷新前端，确认价格变化

---

## 7) 常见问题（排错思路）

1. **测试报错 `AccessControl: account ... is missing role`**
   - `updateIndexPrice` 需要 `OPERATOR_ROLE`
   - 测试中需要先 `grantRole`：`exchange.grantRole(exchange.OPERATOR_ROLE(), address(this));`

2. **`markPrice` 始终等于 `indexPrice`**
   - `_calculateMarkPrice()` 没有正确实现三价取中
   - 检查是否正确读取了 `bestBuyId` 和 `bestSellId`

3. **三价取中结果不对**
   - `_median()` 函数逻辑错误
   - 确保处理了只有买盘或只有卖盘的情况

4. **钳位逻辑不生效**
   - 检查 `upper = indexPrice_ * 105 / 100` 是否正确
   - 注意 Solidity 整数除法的精度问题

5. **Keeper 报错 `transaction failed`**
   - 确认 Keeper 使用的账户有 `OPERATOR_ROLE`
   - 检查 `EXCHANGE_ADDRESS` 配置是否正确

6. **前端价格不更新**
   - 点击 Refresh 按钮
   - 检查 Console 是否有 RPC 错误
   - 确认合约地址正确

---

## 8) 小结 & 为 Day 5 铺垫

今天我们完成了"价格服务"的核心逻辑：

- `updateIndexPrice()`：Operator 推送外部市场价格
- `_calculateMarkPrice()`：三价取中 + 偏离保护
- Keeper 服务：定时从 Binance/Pyth 获取价格并上链

至此，系统具备了：
1. 用户资金管理 → 2. 订单簿交易 → 3. 撮合成交 → **4. 价格服务**

Day 5 会使用这些价格实现"数据索引与 K 线"：

- 配置 Indexer（Envio）解析 `TradeExecuted` 事件
- 生成 OHLC（开高低收）K 线数据
- 前端集成图表库展示专业行情

---

## 9) 进阶开发（可选）

1. **实现完整的 Pyth 集成**
   - 解析 Pyth 的 `expo` 指数字段。
   - 处理价格置信区间（confidence interval）。

2. **添加价格历史记录**
   - 在合约中存储最近 N 次价格更新。
   - 实现 `getPriceHistory()` 视图函数。

3. **多资产价格支持**
   - 修改合约支持多个交易对。
   - 每个交易对有独立的 `indexPrice` 和 `markPrice`。

4. **价格延迟保护**
   - 记录 `lastPriceUpdateTime`。
   - 如果价格超过 N 分钟未更新，阻止新订单。

5. **Keeper 高可用**
   - 实现多 Keeper 竞争上链。
   - 添加价格有效性检查（与上次差异过大则跳过）。
