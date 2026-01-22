import {
    Exchange,
    Trade,
    Candle,
    Order,
    Position,
    MarginEvent,
    LatestCandle,
    FundingEvent,
    Liquidation,
    TraderStat
} from "../generated";

const updateTraderStat = async (context: any, trader: string, volume: bigint, pnl: bigint, timestamp: number) => {
    let stat = await context.TraderStat.get(trader);
    if (!stat) {
        stat = {
            id: trader,
            totalVolume: 0n,
            totalPnl: 0n,
            tradeCount: 0,
            winCount: 0,
            lastTradeTime: 0,
        };
    }
    
    stat.totalVolume += volume;
    stat.totalPnl += pnl;
    if (volume > 0n) {
         stat.tradeCount += 1;
         stat.lastTradeTime = timestamp;
    }
    if (pnl > 0n) stat.winCount += 1;
    
    context.TraderStat.set(stat);
};

/**
 * Event Handlers - 脚手架版本
 * 
 * 这个文件定义了如何处理合约事件并存储到数据库。
 * 1. MarginDeposited - 记录充值事件
 * 2. MarginWithdrawn - 记录提现事件
 * 3. OrderPlaced - 记录新订单
 * 4. OrderRemoved - 更新订单状态 (取消/成交)
 * 5. TradeExecuted - 记录成交，更新订单、K线、持仓
 */

/**
 * 处理保证金充值事件
 * 步骤:
 * 1. 从 event.params 获取 trader 和 amount
 * 2. 创建 MarginEvent 实体
 * 3. 使用 context.MarginEvent.set 保存
 */

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
/**
 * 处理订单移除事件
 * 
 * TODO: 实现此处理器
 * 步骤:
 * 1. 获取现有订单 context.Order.get
 * 2. 根据剩余数量判断是 CANCELLED 还是 FILLED
 * 3. 更新订单状态
 */
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

    // Update Stats
    await updateTraderStat(context, event.params.buyer, event.params.amount, 0n, event.block.timestamp);
    await updateTraderStat(context, event.params.seller, event.params.amount, 0n, event.block.timestamp);

    // 更新 K 线 (1m)
    const resolution = "1m";
    const timestamp = event.block.timestamp - (event.block.timestamp % 60);
    const candleId = `${resolution}-${timestamp}`;

    const existingCandle = await context.Candle.get(candleId);

    if (!existingCandle) {
        // 新 K 线：尝试获取上一根 K 线的收盘价作为开盘价
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


Exchange.PositionUpdated.handler(async ({ event, context }) => {
    const position: Position = {
        id: event.params.trader,
        trader: event.params.trader,
        size: event.params.size,
        entryPrice: event.params.entryPrice,
    };
    context.Position.set(position);
});

Exchange.FundingUpdated.handler(async ({ event, context }) => {
    const entity: FundingEvent = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        eventType: "GLOBAL_UPDATE",
        trader: undefined,
        cumulativeRate: event.params.cumulativeFundingRate,
        payment: undefined,
        timestamp: event.block.timestamp,
    };
    context.FundingEvent.set(entity);
});

Exchange.FundingPaid.handler(async ({ event, context }) => {
    const entity: FundingEvent = {
        id: `${event.transaction.hash}-${event.logIndex}`,
        eventType: "USER_PAID",
        trader: event.params.trader,
        cumulativeRate: undefined,
        payment: event.params.amount,
        timestamp: event.block.timestamp,
    };
    context.FundingEvent.set(entity);
});

Exchange.RealizedPnl.handler(async ({ event, context }) => {
    await updateTraderStat(context, event.params.trader, 0n, event.params.pnl, event.block.timestamp);
});
