import React from 'react';
import { observer } from 'mobx-react-lite';
import { useExchangeStore } from '../store/exchangeStore';
import { formatEther } from 'viem';

export const MarketStats: React.FC = observer(() => {
    const { trades, markPrice, indexPrice, fundingRate } = useExchangeStore();

    // Last Price
    const lastTradePrice = trades.length > 0 ? trades[0].price : undefined;
    const previousTradePrice = trades.length > 1 ? trades[1].price : undefined;

    // Price Change Direction
    const isUp = lastTradePrice && previousTradePrice ? lastTradePrice >= previousTradePrice : true;
    const priceColor = isUp ? 'text-nebula-teal' : 'text-nebula-pink';

    // Format Mark Price
    const formattedMarkPrice = markPrice > 0n
        ? Number(formatEther(markPrice)).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
        : '--';

    // Format Funding Rate (e.g., 0.0001 -> 0.01%)
    const formattedFundingRate = (fundingRate * 100).toFixed(4) + '%';

    return (
        <div className="grid grid-cols-3 gap-4 mb-4 p-3 bg-white/5 rounded-lg border border-white/5">
            {/* Mark Price */}
            <div className="flex flex-col">
                <span className="text-xs text-gray-400 mb-1">Mark Price</span>
                <span className="text-lg font-bold font-mono text-gray-200">{formattedMarkPrice}</span>
            </div>

            {/* Index Price */}
            <div className="flex flex-col">
                <span className="text-xs text-gray-400 mb-1">Index Price</span>
                <span className="text-lg font-bold font-mono text-gray-200">
                    {indexPrice > 0n ? Number(formatEther(indexPrice)).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : '--'}
                </span>
            </div>

            {/* Funding Rate */}
            <div className="flex flex-col">
                <span className="text-xs text-gray-400 mb-1">Funding / 1h</span>
                <span className={`text-lg font-bold font-mono ${fundingRate >= 0 ? 'text-nebula-orange' : 'text-nebula-teal'}`}>
                    {formattedFundingRate}
                </span>
            </div>
        </div>
    );
});
