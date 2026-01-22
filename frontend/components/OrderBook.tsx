import React from 'react';
import { observer } from 'mobx-react-lite';
import { useExchangeStore } from '../store/exchangeStore';
import { formatEther } from 'viem';

export const OrderBook: React.FC = observer(() => {
  const { orderBook, markPrice, trades, refresh, syncing } = useExchangeStore();
  // Use last traded price if available, otherwise fallback to markPrice
  const lastTradePrice = trades.length > 0 ? trades[0].price : undefined;
  const currentPrice = lastTradePrice || (markPrice > 0n ? Number(formatEther(markPrice)) : undefined);
  const bids = orderBook.bids;
  const asks = orderBook.asks;
  const hasOrders = bids.length > 0 || asks.length > 0;

  return (
    <div className="bg-[#10121B] rounded-xl border border-white/5 p-3 flex flex-col h-full min-h-0">
      <div className="flex justify-between items-center mb-2 shrink-0">
        <h3 className="text-sm font-semibold text-gray-200">Orderbook</h3>
        <button
          onClick={refresh}
          className="text-[10px] px-2 py-1 rounded bg-white/5 text-gray-400 hover:text-white"
        >
          {syncing ? 'Syncing…' : 'Refresh'}
        </button>
      </div>
      <div className="text-[10px] text-gray-500 flex justify-between px-1">
        <span>Debug bids: {bids.length}</span>
        <span>Debug asks: {asks.length}</span>
      </div>


      <div className="grid grid-cols-3 text-[10px] text-gray-500 mb-1 px-1 shrink-0">
        <span>Price</span>
        <span className="text-center">Size</span>
        <span className="text-right">Total</span>
      </div>

      <div className="flex-1 flex flex-col min-h-0">

        {/* Asks (Sells) - Align to bottom of top section */}
        <div className="flex-1 overflow-hidden flex flex-col justify-end">
          <div className="overflow-y-auto scrollbar-hide flex flex-col-reverse">
            {asks.length === 0 && (
              <div className="text-xs text-gray-500 px-2 pb-2">No asks yet</div>
            )}
            {asks.map((ask, i) => (
              <div key={`ask-${i}`} className="relative grid grid-cols-3 text-xs py-0.5 hover:bg-white/5 cursor-pointer group">
                <div
                  className="absolute top-0 right-0 h-full bg-nebula-pink/10 transition-all"
                  style={{ width: `${ask.depth}%` }}
                />
                <span className="relative z-10 text-nebula-pink pl-1 font-mono">{ask.price.toLocaleString()}</span>
                <span className="relative z-10 text-gray-300 text-center font-mono opacity-80 group-hover:opacity-100">{ask.size.toLocaleString()}</span>
                <span className="relative z-10 text-gray-400 text-right pr-1 font-mono">{ask.total.toLocaleString()}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Current Price */}
        <div className="py-2 my-1 border-y border-white/5 flex items-center justify-center space-x-2 shrink-0 bg-[#10121B] z-10">
          <span className={`text-lg font-bold font-mono ${trades.length > 1 && trades[0].price < trades[1].price ? 'text-nebula-pink' : 'text-nebula-teal'
            }`}>
            {currentPrice ? currentPrice.toLocaleString() : '--'}
          </span>
          <svg
            className={`w-3 h-3 ${trades.length > 1 && trades[0].price < trades[1].price ? 'text-nebula-pink rotate-180' : 'text-nebula-teal'
              }`}
            fill="currentColor"
            viewBox="0 0 20 20"
          >
            <path fillRule="evenodd" d="M5.293 7.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 5.414V17a1 1 0 11-2 0V5.414L6.707 7.707a1 1 0 01-1.414 0z" clipRule="evenodd" />
          </svg>
        </div>

        {/* Bids (Buys) - Align to top of bottom section */}
        <div className="flex-1 overflow-hidden">
          <div className="overflow-y-auto scrollbar-hide">
            {bids.length === 0 && (
              <div className="text-xs text-gray-500 px-2 pt-1">No bids yet</div>
            )}
            {bids.map((bid, i) => (
              <div key={`bid-${i}`} className="relative grid grid-cols-3 text-xs py-0.5 hover:bg-white/5 cursor-pointer group">
                <div
                  className="absolute top-0 right-0 h-full bg-nebula-teal/10 transition-all"
                  style={{ width: `${bid.depth}%` }}
                />
                <span className="relative z-10 text-nebula-teal pl-1 font-mono">{bid.price.toLocaleString()}</span>
                <span className="relative z-10 text-gray-300 text-center font-mono opacity-80 group-hover:opacity-100">{bid.size.toLocaleString()}</span>
                <span className="relative z-10 text-gray-400 text-right pr-1 font-mono">{bid.total.toLocaleString()}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
});
