import React, { useEffect, useRef } from 'react';
import { observer } from 'mobx-react-lite';
import { useExchangeStore } from '../store/exchangeStore';
import { createChart, ColorType, CrosshairMode, IChartApi, ISeriesApi, CandlestickSeries } from 'lightweight-charts';
import { formatEther } from 'viem';

export const TradingChart: React.FC = observer(() => {
  const { candles, currentPrice } = useExchangeStore();
  console.log('[TradingChart] candles from store:', candles);
  const chartContainerRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<IChartApi | null>(null);
  const seriesRef = useRef<ISeriesApi<"Candlestick"> | null>(null);

  // Sort candles by time (ascending) for TradingView
  // Indexer returns descending, so we reverse.
  // We also need to ensure unique timestamps if any.
  const sortedCandles = [...candles]
    .reverse()
    .map(c => ({
      time: c.time.split('T')[0] === new Date().toISOString().split('T')[0]
        ? (new Date(c.time).getTime() / 1000) as any // Use timestamp for intraday
        : c.time.split('T')[0], // Use string for daily? Actually for 1m candles timestamp is best.
      open: c.open,
      high: c.high,
      low: c.low,
      close: c.close,
    }));

  // Fix: lightweight-charts prefers unix timestamp (seconds) for intraday data
  const chartData = [...candles].reverse().map(c => ({
    time: Math.floor(new Date(c.time).getTime() / 1000) as any,
    open: c.open,
    high: c.high,
    low: c.low,
    close: c.close,
  }));

  useEffect(() => {
    if (!chartContainerRef.current) return;

    const chart = createChart(chartContainerRef.current, {
      layout: {
        background: { type: ColorType.Solid, color: 'transparent' },
        textColor: '#9CA3AF',
      },
      grid: {
        vertLines: { color: 'rgba(42, 46, 57, 0.5)' },
        horzLines: { color: 'rgba(42, 46, 57, 0.5)' },
      },
      width: chartContainerRef.current.clientWidth,
      height: chartContainerRef.current.clientHeight,
      crosshair: {
        mode: CrosshairMode.Normal,
      },
      timeScale: {
        borderColor: '#4B5563',
        timeVisible: true,
        secondsVisible: false,
      },
      rightPriceScale: {
        borderColor: '#4B5563',
      },
    });

    const candlestickSeries = chart.addSeries(CandlestickSeries, {
      upColor: '#00E0FF',
      downColor: '#FF409A',
      borderVisible: false,
      wickUpColor: '#00E0FF',
      wickDownColor: '#FF409A',
    });

    candlestickSeries.setData(chartData);
    seriesRef.current = candlestickSeries;

    // Add current price line if we have data
    if (chartData.length > 0) {
      // TradingView handles current price line automatically if we update the last candle
      // But for a specific "current price" line distinct from the candle close, we can use a PriceLine
      // However, usually the last candle's close IS the current price.
    }

    chartRef.current = chart;

    const handleResize = () => {
      if (chartContainerRef.current && chart) {
        chart.applyOptions({ width: chartContainerRef.current.clientWidth });
      }
    };

    window.addEventListener('resize', handleResize);

    return () => {
      window.removeEventListener('resize', handleResize);
      chart.remove();
    };
  }, []); // Init once

  useEffect(() => {
    if (!seriesRef.current) return;
    seriesRef.current.setData(chartData);
    if (chartRef.current) {
      chartRef.current.timeScale().fitContent();
    }
  }, [candles]); // Re-run when candles change.

  return (
    <div className="flex flex-col h-full bg-[#1A1D26] rounded-lg border border-gray-800 p-4">
      <div className="flex justify-between items-center mb-4">
        <div className="flex items-center gap-4">
          <h2 className="text-lg font-semibold text-white">ETH/USD</h2>
          <div className="flex gap-2">
            <span className="text-sm text-gray-400">15m</span>
            <span className="text-sm text-gray-600">1h</span>
            <span className="text-sm text-gray-600">4h</span>
            <span className="text-sm text-gray-600">1d</span>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {/* Price removed as requested */}
        </div>
      </div>

      <div className="flex-1 w-full min-h-0 relative">
        <div ref={chartContainerRef} className="w-full h-full" />
        {chartData.length === 0 && (
          <div className="absolute inset-0 flex items-center justify-center text-gray-500 text-sm pointer-events-none">
            Waiting for data...
          </div>
        )}
      </div>
    </div>
  );
});
