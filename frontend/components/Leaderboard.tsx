import React, { useEffect, useState } from 'react';
import { observer } from 'mobx-react-lite';
import { useExchangeStore } from '../store/exchangeStore';
import { formatEther } from 'viem';

export const Leaderboard: React.FC = observer(() => {
  const { leaderboard, refreshLeaderboard, syncing } = useExchangeStore();
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    if (isOpen) {
      refreshLeaderboard();
    }
  }, [isOpen]);

  if (!isOpen) {
    return (
      <button 
        onClick={() => setIsOpen(true)}
        className="fixed bottom-6 right-6 bg-gradient-to-r from-nebula-violet to-nebula-pink text-white px-4 py-2 rounded-full shadow-lg font-bold hover:opacity-90 transition-opacity z-50 flex items-center gap-2"
      >
        <span>🏆</span> Leaderboard
      </button>
    );
  }

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
      <div className="bg-[#10121B] rounded-2xl border border-white/10 w-full max-w-2xl max-h-[80vh] flex flex-col shadow-2xl">
        <div className="p-6 border-b border-white/10 flex justify-between items-center shrink-0">
          <div className="flex items-center gap-3">
            <span className="text-2xl">🏆</span>
            <div>
              <h2 className="text-xl font-bold text-white">Trading Leaderboard</h2>
              <p className="text-sm text-gray-400">Top traders by PnL</p>
            </div>
          </div>
          <button 
            onClick={() => setIsOpen(false)}
            className="w-8 h-8 rounded-full bg-white/5 hover:bg-white/10 flex items-center justify-center text-gray-400 hover:text-white transition-colors"
          >
            ✕
          </button>
        </div>

        <div className="overflow-y-auto p-6">
          <table className="w-full text-left">
            <thead>
              <tr className="text-xs text-gray-500 uppercase tracking-wider border-b border-white/5">
                <th className="pb-4 pl-4">Rank</th>
                <th className="pb-4">Trader</th>
                <th className="pb-4 text-right">Trades</th>
                <th className="pb-4 text-right">Win Rate</th>
                <th className="pb-4 text-right pr-4">Total PnL</th>
              </tr>
            </thead>
            <tbody className="text-sm">
              {leaderboard.map((stat, index) => {
                const pnl = Number(formatEther(stat.totalPnl));
                const winRate = stat.tradeCount > 0 ? (stat.winCount / stat.tradeCount) * 100 : 0;
                
                return (
                  <tr key={stat.id} className="border-b border-white/5 last:border-0 hover:bg-white/5 transition-colors">
                    <td className="py-4 pl-4">
                      {index < 3 ? (
                        <span className={`
                          w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold
                          ${index === 0 ? 'bg-yellow-500/20 text-yellow-500' : ''}
                          ${index === 1 ? 'bg-gray-300/20 text-gray-300' : ''}
                          ${index === 2 ? 'bg-amber-700/20 text-amber-700' : ''}
                        `}>
                          {index + 1}
                        </span>
                      ) : (
                        <span className="text-gray-500 ml-2">#{index + 1}</span>
                      )}
                    </td>
                    <td className="py-4 font-mono text-gray-300">
                      {stat.id.slice(0, 6)}...{stat.id.slice(-4)}
                    </td>
                    <td className="py-4 text-right text-gray-400">
                      {stat.tradeCount}
                    </td>
                    <td className="py-4 text-right text-gray-400">
                      {winRate.toFixed(1)}%
                    </td>
                    <td className={`py-4 text-right pr-4 font-bold ${pnl >= 0 ? 'text-nebula-teal' : 'text-nebula-pink'}`}>
                      {pnl >= 0 ? '+' : ''}{pnl.toFixed(4)} MON
                    </td>
                  </tr>
                );
              })}
              {leaderboard.length === 0 && (
                <tr>
                  <td colSpan={5} className="py-12 text-center text-gray-500">
                    No trading data available yet
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
});
