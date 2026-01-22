import { CandleData, DisplayPosition, OrderBookItem, Trade } from './types';

// Generate realistic looking candle data
export const generateCandleData = (count: number): CandleData[] => {
  let price = 4280.00;
  const data: CandleData[] = [];
  const now = new Date();
  
  for (let i = 0; i < count; i++) {
    const time = new Date(now.getTime() - (count - i) * 15 * 60000); // 15 min intervals
    const volatility = 15 + Math.random() * 20;
    const change = (Math.random() - 0.5) * volatility;
    
    const open = price;
    const close = price + change;
    const high = Math.max(open, close) + Math.random() * 10;
    const low = Math.min(open, close) - Math.random() * 10;
    const volume = Math.floor(Math.random() * 1000) + 500;
    
    price = close;
    
    data.push({
      time: time.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
      open,
      high,
      low,
      close,
      volume
    });
  }
  return data;
};

export const MOCK_CANDLES = generateCandleData(60);

export const MOCK_ASKS: OrderBookItem[] = [
  { price: 1294.30, size: 0.5, total: 12.5, depth: 30 },
  { price: 1293.20, size: 0.5, total: 12.0, depth: 45 },
  { price: 1289.30, size: 0.9, total: 11.5, depth: 20 },
  { price: 1283.30, size: 0.9, total: 10.6, depth: 60 },
  { price: 1298.30, size: 0.9, total: 9.7, depth: 15 },
  { price: 1282.30, size: 0.9, total: 8.8, depth: 80 },
].sort((a, b) => b.price - a.price);

export const MOCK_BIDS: OrderBookItem[] = [
  { price: 1293.30, size: 0.5, total: 0.5, depth: 20 },
  { price: 1293.30, size: 0.5, total: 1.0, depth: 25 },
  { price: 1284.30, size: 0.5, total: 1.5, depth: 50 },
  { price: 1284.30, size: 0.5, total: 2.0, depth: 55 },
  { price: 1289.30, size: 0.5, total: 2.5, depth: 70 },
  { price: 1289.30, size: 0.5, total: 3.0, depth: 85 },
].sort((a, b) => b.price - a.price);

export const MOCK_TRADES: Trade[] = [
  { id: '1', price: 1299.00, amount: 0.0100, time: '5m ago', side: 'sell' },
  { id: '2', price: 1298.00, amount: 0.0201, time: '3m ago', side: 'sell' },
  { id: '3', price: 1258.00, amount: 0.0704, time: '3m ago', side: 'buy' },
  { id: '4', price: 1258.00, amount: 0.0105, time: '3m ago', side: 'buy' },
  { id: '5', price: 1258.00, amount: 0.0108, time: '3m ago', side: 'buy' },
  { id: '6', price: 1258.00, amount: 0.0104, time: '3m ago', side: 'sell' },
  { id: '7', price: 1258.00, amount: 0.0103, time: '3m ago', side: 'buy' },
];

export const MOCK_POSITIONS: DisplayPosition[] = [
  {
    symbol: 'ETH-USD',
    leverage: 10,
    size: 2500.00,
    entryPrice: 1280.50,
    markPrice: 1298.30,
    liqPrice: 1160.00,
    pnl: 178.00,
    pnlPercent: 13.9,
    side: 'long'
  },
  {
    symbol: 'BTC-USD',
    leverage: 5,
    size: 15000.00,
    entryPrice: 48000.00,
    markPrice: 47500.00,
    liqPrice: 56000.00,
    pnl: -500.00,
    pnlPercent: -3.3,
    side: 'short'
  }
];
