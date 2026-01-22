import React, { createContext, useContext, useEffect } from 'react';
import { makeAutoObservable, runInAction } from 'mobx';
import { Address, Hash, parseAbiItem, parseEther, formatEther } from 'viem';
import { EXCHANGE_ABI } from '../onchain/ExchangeABI';
import { EXCHANGE_ADDRESS, EXCHANGE_DEPLOY_BLOCK } from '../onchain/config';
import { chain, getWalletClient, publicClient, fallbackAccount, ACCOUNTS } from '../onchain/client';
import { OrderBookItem, OrderSide, OrderType, PositionSnapshot, Trade, CandleData, TraderStat } from '../types';
import { client, GET_CANDLES, GET_RECENT_TRADES, GET_POSITIONS, GET_OPEN_ORDERS, GET_MY_TRADES, GET_LEADERBOARD } from './IndexerClient';

type OrderStruct = {
  id: bigint;
  trader: Address;
  isBuy: boolean;
  price: bigint;
  amount: bigint;
  initialAmount: bigint;
  timestamp: bigint;
  next: bigint;
};

type OrderBookState = {
  bids: OrderBookItem[];
  asks: OrderBookItem[];
};

export type OpenOrder = {
  id: bigint;
  isBuy: boolean;
  price: bigint;
  amount: bigint;
  initialAmount: bigint;
  timestamp: bigint;
  trader: Address;
};

class ExchangeStore {
  account?: Address;
  accountIndex = 0; // New observable state
  margin = 0n;

  position?: PositionSnapshot;
  markPrice = 0n;
  indexPrice = 0n;
  initialMarginBps = 100n; // Default 1%
  fundingRate = 0; // Estimated hourly funding rate
  orderBook: OrderBookState = { bids: [], asks: [] };
  trades: Trade[] = [];
  candles: CandleData[] = [];
  myOrders: OpenOrder[] = [];
  myTrades: Trade[] = [];
  leaderboard: TraderStat[] = [];
  syncing = false;
  cancellingOrderId?: bigint; // Day 2: 正在取消的订单 ID
  error?: string;
  walletClient = getWalletClient();

  constructor() {
    makeAutoObservable(this);
    this.autoConnect();
    this.refresh();
    this.refreshLeaderboard();
    // 定时刷新（静默模式，不触发 syncing 状态变化）
    setInterval(() => {
      this.refresh(true).catch(() => { });
    }, 3000);
    console.info('[store] 交易所 store 初始化完成');
  }

  ensureContract() {
    if (!EXCHANGE_ADDRESS) throw new Error('Set VITE_EXCHANGE_ADDRESS');
    return EXCHANGE_ADDRESS;
  }

  autoConnect = async () => {
    // Check URL params first
    const params = new URLSearchParams(window.location.search);
    const urlAccount = params.get('account');
    if (urlAccount && urlAccount.startsWith('0x')) {
      runInAction(() => (this.account = urlAccount as Address));
      return;
    }

    if (fallbackAccount) {
      runInAction(() => (this.account = fallbackAccount.address));
      return;
    }

  };

  connectWallet = async () => {
    if (!this.walletClient) {
      runInAction(() => (this.error = 'No wallet configured'));
      return;
    }
    if ((this.walletClient as any).account?.address) {
      runInAction(() => (this.account = (this.walletClient as any).account.address));
    } else if (fallbackAccount) {
      runInAction(() => (this.account = fallbackAccount.address));
    }
  };

  switchAccount = () => {
    this.accountIndex = (this.accountIndex + 1) % ACCOUNTS.length;
    const newAccount = ACCOUNTS[this.accountIndex];
    this.walletClient = getWalletClient(newAccount);
    runInAction(() => {
      this.account = newAccount.address;
      this.refresh();
    });
  };

  mapOrder(data: any): OrderStruct {
    // 优先检查命名属性（viem 通常返回带命名属性的数组）
    if (data && typeof data.price !== 'undefined') {
      return {
        id: data.id,
        trader: data.trader,
        isBuy: data.isBuy,
        price: data.price,
        amount: data.amount,
        initialAmount: data.initialAmount,
        timestamp: data.timestamp,
        next: data.next,
      };
    }

    if (Array.isArray(data)) {
      return {
        id: data[0],
        trader: data[1],
        isBuy: data[2],
        price: data[3],
        amount: data[4],
        initialAmount: data[5],
        timestamp: data[6],
        next: data[7],
      };
    }
    return data as OrderStruct;
  }

  loadOrderChain = async (headId?: bigint | null) => {
    const head: OrderStruct[] = [];
    if (!headId || headId === 0n) return head;
    const visited = new Set<string>();
    let current: bigint | undefined | null = headId;
    for (let i = 0; i < 128 && typeof current === 'bigint' && current !== 0n; i++) {
      if (visited.has(current.toString())) break;
      visited.add(current.toString());
      const raw = await publicClient.readContract({
        abi: EXCHANGE_ABI,
        address: this.ensureContract(),
        functionName: 'orders',
        args: [current],
      } as any);
      const data = this.mapOrder(raw);
      if (data.id === 0n) break;
      head.push(data);
      current = data.next;
    }
    return head;
  };

  formatOrderBook = (orders: OrderStruct[], isBuy: boolean): OrderBookItem[] => {
    // 1. Filter valid orders
    const filtered = orders.filter((o) => o.isBuy === isBuy && o.amount > 0n);

    // 2. Aggregate by price
    const aggregated = new Map<number, number>();
    filtered.forEach((o) => {
      const price = Number(formatEther(o.price));
      const size = Number(formatEther(o.amount));
      aggregated.set(price, (aggregated.get(price) || 0) + size);
    });

    // 3. Convert to array
    const rows = Array.from(aggregated.entries()).map(([price, size]) => ({
      price,
      size,
      total: 0,
      depth: 0,
    }));

    // 4. Sort: Bids Descending / Asks Ascending
    rows.sort((a, b) => (isBuy ? b.price - a.price : a.price - b.price));

    // 5. Calculate cumulative total
    let running = 0;
    const result = rows.map((r) => {
      running += r.size;
      return { ...r, total: running };
    });

    // 6. Calculate relative depth
    const maxTotal = result.length > 0 ? result[result.length - 1].total : 0;
    return result.map((r) => ({
      ...r,
      depth: maxTotal > 0 ? Math.min(100, Math.round((r.total / maxTotal) * 100)) : 0,
    }));
  };

  // ============================================
  // Day 5 TODO: 从 Indexer 获取 K 线数据
  // ============================================
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

  // ============================================
  // Day 5 TODO: 从 Indexer 获取最近成交
  // ============================================
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
  // ============================================
  // Day 2 TODO: 从 Indexer 获取用户订单
  // ============================================
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
  // ============================================
  // Day 5 TODO: 从 Indexer 获取用户的成交历史
  // ============================================
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

  // 在 refresh() 方法中，替换现有的 position 读取代码};

  refreshLeaderboard = async () => {
    try {
      const result = await client.query(GET_LEADERBOARD, {}).toPromise();
      const data = result.data;
      if (data?.TraderStat) {
        runInAction(() => {
          this.leaderboard = data.TraderStat.map((s: any) => ({
            ...s,
            totalPnl: BigInt(s.totalPnl),
            totalVolume: BigInt(s.totalVolume),
          }));
        });
      }
    } catch (e) {
      console.error('Failed to load leaderboard', e);
    }
  };

  refresh = async (silent = false) => {
    try {
      if (!silent) {
        runInAction(() => {
          this.syncing = true;
          this.error = undefined;
        });
      }
      const address = this.ensureContract();

      // 1. 获取全局市场数据
      // 注意：确保 ABI 中包含 indexPrice, bestBuyId, initialMarginBps 等定义
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

        const m = Number(formatEther(mark));
        const i = Number(formatEther(index));
        const premiumIndex = (m - i) / i;
        const interestRate = 0.0001; // 0.01%
        const clampRange = 0.0005;   // 0.05%

        let diff = interestRate - premiumIndex;
        if (diff > clampRange) diff = clampRange;
        if (diff < -clampRange) diff = -clampRange;

        this.fundingRate = premiumIndex + diff;
      });

      // 2. 获取用户个人数据 (余额与持仓)
      if (this.account) {
        const [bal, pos] = await Promise.all([
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
          } as any) as Promise<any>, 
        ]);

        runInAction(() => {
          this.margin = bal; 
          // 如果 viem 返回数组，可能需要映射；如果返回对象则直接使用
          // 这里假设返回结构体兼容 PositionSnapshot
          this.position = pos as PositionSnapshot; 
        });
      }

      // 3. 加载订单簿 (链表遍历)
      let bidsRaw: OrderStruct[] = [];
      let asksRaw: OrderStruct[] = [];
      try {
        // 如果 bestBid/bestAsk 为 0，loadOrderChain 会直接返回空数组，不会报错
        [bidsRaw, asksRaw] = await Promise.all([
          this.loadOrderChain(bestBid), 
          this.loadOrderChain(bestAsk)
        ]);
      } catch (inner) {
        const msg = (inner as Error)?.message || 'Failed to load orderbook linked list';
        console.error('[orderbook] loadOrderChain error', msg);
        // 不中断整个 refresh，仅记录日志
      }

      // 4. 扫描部分订单槽位 (Fallback 机制)
      const scanned: OrderStruct[] = [];
      const SCAN_LIMIT = 20;
      for (let i = 1; i <= SCAN_LIMIT; i++) {
        try {
          const id = BigInt(i);
          const raw = await publicClient.readContract({
            abi: EXCHANGE_ABI,
            address,
            functionName: 'orders',
            args: [id],
          } as any);
          const data = this.mapOrder(raw);
          // console.debug('[orderbook] slot', i, data);
          if (data.id !== 0n) scanned.push(data);
        } catch (inner) {
          // 忽略读取错误的槽位
          break; 
        }
      }

      // 5. 合并与格式化订单簿
      const merged = new Map<bigint, OrderStruct>();
      [...bidsRaw, ...asksRaw, ...scanned].forEach((o) => {
        if (o && o.id) merged.set(o.id, o);
      });
      const allOrders = Array.from(merged.values());
      const bids = allOrders.filter((o) => o.isBuy && o.amount > 0n);
      const asks = allOrders.filter((o) => !o.isBuy && o.amount > 0n);

      runInAction(() => {
        this.orderBook = { 
          bids: this.formatOrderBook(bids, true), 
          asks: this.formatOrderBook(asks, false) 
        };
      });

      // 6. 加载 Indexer 数据 (Trades / Candles)
      // 使用 await 确保数据同步，但 loadTrades 内部已吞掉错误，不会导致 refresh 失败
      await this.loadTrades();
      this.loadCandles();
      
      // 7. 加载我的订单
      if (this.account) {
        try {
          const orders = await this.loadMyOrders(this.account);
          runInAction(() => {
            this.myOrders = orders;
          });
        } catch (e) {
            console.warn('[Indexer] Failed to load my orders', e);
        }
        await this.loadMyTrades(this.account);
      }

    } catch (e) {
      console.error('Refresh failed:', e);
      runInAction(() => (this.error = (e as Error)?.message || 'Failed to sync exchange data'));
    } finally {
      if (!silent) {
        runInAction(() => (this.syncing = false));
      }
    }
  };
  // ============================================
  // Day 1 TODO: 实现充值函数
  // ============================================
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
  // ============================================
  //  实现提现函数
  // ============================================
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
  // ============================================
  //  实现下单函数
  // ============================================
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
  // ============================================
  // Day 2 TODO: 实现取消订单函数
  // ============================================
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
}
const ExchangeStoreContext = createContext<ExchangeStore | null>(null);

export const ExchangeStoreProvider: React.FC<React.PropsWithChildren> = ({ children }) => {
  const storeRef = React.useRef<ExchangeStore>();
  if (!storeRef.current) {
    storeRef.current = new ExchangeStore();
  }
  return <ExchangeStoreContext.Provider value={storeRef.current}>{children}</ExchangeStoreContext.Provider>;
};

export const useExchangeStore = () => {
  const ctx = useContext(ExchangeStoreContext);
  if (!ctx) throw new Error('useExchangeStore must be used within ExchangeStoreProvider');
  return ctx;
};
