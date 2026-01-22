import React, { useState } from 'react';
import { formatEther } from 'viem';
import { OrderSide, OrderType } from '../types';
import { observer } from 'mobx-react-lite';
import { useExchangeStore } from '../store/exchangeStore';

import { MarketStats } from './MarketStats';

export const OrderForm: React.FC = observer(() => {
  const [orderType, setOrderType] = useState<OrderType>(OrderType.MARKET);
  const [leverage, setLeverage] = useState(20);
  const [amount, setAmount] = useState('');
  const [price, setPrice] = useState('');
  const [hintId, setHintId] = useState('');
  const [depositAmount, setDepositAmount] = useState('0.1');
  const [withdrawAmount, setWithdrawAmount] = useState('');
  const [status, setStatus] = useState<string | undefined>();
  const [isDepositing, setIsDepositing] = useState(false);
  const [isWithdrawing, setIsWithdrawing] = useState(false);
  const [isOrdering, setIsOrdering] = useState(false);
  const store = useExchangeStore();
  const { account, margin, markPrice, placeOrder, deposit, withdraw, connectWallet, syncing, error } =
    store;

  const availableMargin = Number(formatEther(margin));
  const locked = 0;
  const markDisplay = markPrice > 0n ? Number(markPrice) : undefined;

  const handleOrder = async (side: OrderSide) => {
    try {
      setStatus(undefined);
      setIsOrdering(true);
      const parsedAmount = parseFloat(amount);
      if (isNaN(parsedAmount) || parsedAmount <= 0) {
        throw new Error('Please enter a valid amount');
      }

      const parsedPriceVal = orderType === OrderType.LIMIT ? parseFloat(price) : 0;
      if (orderType === OrderType.LIMIT && (isNaN(parsedPriceVal) || parsedPriceVal <= 0)) {
        throw new Error('Please enter a valid price');
      }

      await placeOrder({
        side,
        orderType,
        price: orderType === OrderType.MARKET ? undefined : price,
        amount: parsedAmount.toString(),
        hintId,
      });
      setAmount('');
      setPrice('');
      setHintId('');
      setStatus(`${side === OrderSide.BUY ? 'Long' : 'Short'} order submitted`);
    } catch (e) {
      setStatus((e as Error)?.message || 'Order failed');
    } finally {
      setIsOrdering(false);
    }
  };

  const handleDeposit = async () => {
    try {
      setStatus(undefined);
      setIsDepositing(true);
      await deposit(depositAmount);
      setStatus('Deposit complete');
    } catch (e) {
      setStatus((e as Error)?.message || 'Deposit failed');
    } finally {
      setIsDepositing(false);
    }
  };

  const handleWithdraw = async () => {
    try {
      setStatus(undefined);
      setIsWithdrawing(true);
      await withdraw(withdrawAmount || '0');
      setStatus('Withdraw complete');
    } catch (e) {
      setStatus((e as Error)?.message || 'Withdraw failed');
    } finally {
      setIsWithdrawing(false);
    }
  };

  return (
    <div className="bg-[#10121B] rounded-xl border border-white/5 p-4 flex flex-col gap-4 h-full overflow-y-auto">
      <div className="flex items-center justify-between text-xs text-gray-500">
        <span>{account ? `Connected: ${account.slice(0, 6)}...${account.slice(-4)}` : 'No wallet connected'}</span>
      </div>

      {error && (
        <div className="text-xs text-red-400 bg-red-500/10 border border-red-500/30 rounded px-3 py-2">
          {error}
        </div>
      )}

      {/* Market Stats */}
      <MarketStats />

      {/* Type Selector */}
      <div className="flex bg-[#0B0E14] p-1 rounded-lg shrink-0">
        {Object.values(OrderType).map((type) => (
          <button
            key={type}
            onClick={() => setOrderType(type)}
            className={`flex-1 py-1.5 text-sm font-medium rounded-md transition-all ${orderType === type
              ? 'bg-[#1E2330] text-white shadow-sm'
              : 'text-gray-500 hover:text-gray-300'
              }`}
          >
            {type}
          </button>
        ))}
      </div>

      {/* Margin controls */}
      <div className="grid grid-cols-2 gap-2 text-xs">
        <div className="bg-[#0B0E14] border border-white/10 rounded-lg px-3 py-2 space-y-1">
          <div className="flex justify-between text-[10px] text-gray-500 uppercase">
            <span>Deposit</span>
            <span className="text-white font-mono">{availableMargin.toFixed(4)} USD</span>
          </div>
          <div className="flex flex-col gap-2">
            <input
              type="text"
              value={depositAmount}
              onChange={(e) => setDepositAmount(e.target.value)}
              className="bg-transparent border border-white/10 rounded px-2 py-1 text-white text-sm w-full outline-none"
              placeholder="0.1"
            />
            <button
              onClick={account ? handleDeposit : connectWallet}
              disabled={isDepositing}
              className="px-3 py-1 rounded bg-nebula-teal text-black font-semibold text-xs hover:bg-cyan-300 w-full disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isDepositing ? 'Pending...' : (account ? 'Deposit' : 'Connect')}
            </button>
          </div>
        </div>
        <div className="bg-[#0B0E14] border border-white/10 rounded-lg px-3 py-2 space-y-1">
          <div className="flex justify-between text-[10px] text-gray-500 uppercase">
            <span>Withdraw</span>
            <span className="text-white font-mono">{locked.toFixed(4)} locked</span>
          </div>
          <div className="flex flex-col gap-2">
            <input
              type="text"
              value={withdrawAmount}
              onChange={(e) => setWithdrawAmount(e.target.value)}
              className="bg-transparent border border-white/10 rounded px-2 py-1 text-white text-sm w-full outline-none"
              placeholder="0.0"
            />
            <button
              onClick={account ? handleWithdraw : connectWallet}
              disabled={isWithdrawing}
              className="px-3 py-1 rounded bg-[#1E2330] text-gray-200 font-semibold text-xs hover:bg-[#252b3b] w-full disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isWithdrawing ? 'Pending...' : (account ? 'Withdraw' : 'Connect')}
            </button>
          </div>
        </div>
      </div>

      {/* Leverage Slider */}
      <div className="shrink-0">
        <div className="flex justify-between text-xs mb-2">
          <span className="text-gray-400">Leverage</span>
          <span className="text-white font-mono">{leverage}x</span>
        </div>
        <div className="relative h-6 flex items-center">
          <input
            type="range"
            min="1"
            max="100"
            value={leverage}
            onChange={(e) => setLeverage(Number(e.target.value))}
            className="w-full h-1.5 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-nebula-violet"
          />
        </div>
        <div className="flex justify-between text-[10px] text-gray-600 font-mono mt-1">
          <span>1x</span>
          <span>25x</span>
          <span>50x</span>
          <span>75x</span>
          <span>100x</span>
        </div>
      </div>

      {/* Inputs */}
      <div className="space-y-3 shrink-0">
        <div className="bg-[#0B0E14] border border-white/10 rounded-lg px-3 py-2 flex items-center justify-between group focus-within:border-nebula-violet/50 transition-colors">
          <div className="flex flex-col">
            <label className="text-[10px] text-gray-500 uppercase">Amount (ETH)</label>
            <input
              type="text"
              placeholder="1 (units)"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="bg-transparent border-none outline-none text-white text-sm w-full font-mono placeholder-gray-700"
            />
          </div>
          <span className="text-xs text-gray-400 font-medium">ETH</span>
        </div>

        {orderType === OrderType.LIMIT && (
          <div className="bg-[#0B0E14] border border-white/10 rounded-lg px-3 py-2 flex items-center justify-between group focus-within:border-nebula-violet/50 transition-colors">
            <div className="flex flex-col">
              <label className="text-[10px] text-gray-500 uppercase">Price</label>
              <input
                type="text"
                placeholder="100 (raw units)"
                value={price}
                onChange={(e) => setPrice(e.target.value)}
                className="bg-transparent border-none outline-none text-white text-sm w-full font-mono placeholder-gray-700"
              />
            </div>
            <span className="text-xs text-blue-400 font-medium cursor-pointer hover:text-blue-300">Last</span>
          </div>
        )}

        <div className="bg-[#0B0E14] border border-white/10 rounded-lg px-3 py-2 flex items-center justify-between group focus-within:border-nebula-violet/50 transition-colors">
          <div className="flex flex-col">
            <label className="text-[10px] text-gray-500 uppercase">Hint Id (optional)</label>
            <input
              type="text"
              placeholder="0"
              value={hintId}
              onChange={(e) => setHintId(e.target.value)}
              className="bg-transparent border-none outline-none text-white text-sm w-full font-mono placeholder-gray-700"
            />
          </div>
          <span className="text-xs text-gray-500 font-medium">order queue</span>
        </div>

        {/* Position Size Display */}
        <div className="flex justify-between items-center text-xs px-1">
          <span className="text-gray-400">Est. Cost</span>
          <span className="text-white font-mono">
            {(() => {
              const qty = parseFloat(amount) || 0;
              const p = parseFloat(price) || (markPrice > 0n ? Number(formatEther(markPrice)) : 0);
              const cost = (qty * p) / leverage;
              return cost > 0 ? `${cost.toLocaleString(undefined, { maximumFractionDigits: 4 })} USD` : '--';
            })()}
          </span>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 mt-2 shrink-0">
        <button
          onClick={() => handleOrder(OrderSide.BUY)}
          disabled={syncing || isOrdering}
          className="bg-nebula-teal hover:bg-cyan-400 text-black font-bold py-3 rounded-lg transition-colors flex flex-col items-center justify-center disabled:opacity-60"
        >
          <span className="text-sm">{isOrdering ? 'Pending...' : 'Buy / Long'}</span>
        </button>
        <button
          onClick={() => handleOrder(OrderSide.SELL)}
          disabled={syncing || isOrdering}
          className="bg-nebula-pink hover:bg-fuchsia-400 text-white font-bold py-3 rounded-lg transition-colors flex flex-col items-center justify-center disabled:opacity-60"
        >
          <span className="text-sm">{isOrdering ? 'Pending...' : 'Sell / Short'}</span>
        </button>
      </div>

      {status && (
        <div className="text-xs text-amber-400 bg-amber-500/10 border border-amber-500/30 rounded px-3 py-2">
          {status}
        </div>
      )}

      {/* Account Info */}
      <div className="mt-auto pt-4">
        <div className="grid grid-cols-2 gap-y-2 text-xs border-t border-white/5 pt-4">
          <div className="text-gray-500">Available</div>
          <div className="text-white text-right font-mono">{availableMargin.toFixed(4)} USD</div>
          <div className="text-gray-500">Locked</div>
          <div className="text-white text-right font-mono">{locked.toFixed(4)} USD</div>
          <div className="text-gray-500">Order Type</div>
          <div className="text-right font-mono text-gray-300">{orderType}</div>
        </div>
      </div>
    </div>
  );
});
