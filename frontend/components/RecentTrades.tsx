import React from 'react';
import { observer } from 'mobx-react-lite';
import { useExchangeStore } from '../store/exchangeStore';

export const RecentTrades: React.FC = observer(() => {
  const { trades, refresh, syncing } = useExchangeStore();

  return (
    <div className="bg-[#10121B] rounded-xl border border-white/5 p-4 flex flex-col h-full">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-semibold text-gray-200">Recent Trades</h3>
        <button
          onClick={refresh}
          className="text-[10px] px-2 py-1 rounded bg-white/5 text-gray-400 hover:text-white"
        >
          {syncing ? 'Syncing…' : 'Refresh'}
        </button>
      </div>
      
      <div className="grid grid-cols-3 text-[10px] text-gray-500 mb-2">
        <span>Price</span>
        <span className="text-right">Amount</span>
        <span className="text-right">Time</span>
      </div>

      <div className="flex-1 overflow-y-auto scrollbar-hide space-y-1">
        {trades.length === 0 && (
          <div className="text-xs text-gray-500">No trades yet</div>
        )}
        {trades.map((trade) => (
          <div key={trade.id} className="grid grid-cols-3 text-xs font-mono hover:bg-white/5 py-0.5 rounded cursor-default">
             <span className={trade.side === 'buy' ? 'text-nebula-teal' : 'text-nebula-pink'}>
               {trade.price.toLocaleString()}
             </span>
             <span className="text-gray-300 text-right">{trade.amount.toLocaleString()}</span>
             <span className="text-gray-500 text-right">{trade.time || '--'}</span>
          </div>
        ))}
      </div>
    </div>
  );
});
