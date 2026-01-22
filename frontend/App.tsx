import React from 'react';
import { Header } from './components/Header';
import { TradingChart } from './components/TradingChart';
import { OrderForm } from './components/OrderForm';
import { OrderBook } from './components/OrderBook';
import { RecentTrades } from './components/RecentTrades';
import { Positions } from './components/Positions';
import { Leaderboard } from './components/Leaderboard';
import { ExchangeStoreProvider } from './store/exchangeStore';

const App: React.FC = () => {
  return (
    <ExchangeStoreProvider>
      <div className="flex flex-col h-screen bg-[#05050A] text-gray-200 overflow-hidden font-sans">
        <Header />
        
        <main className="flex-1 p-2 grid grid-cols-12 gap-2 min-h-0 overflow-hidden">
          {/* Left Column: Chart & Positions */}
          <div className="col-span-9 grid grid-rows-[65%_35%] gap-2 min-h-0">
            <TradingChart />
            <Positions />
          </div>

          {/* Right Column: OrderBook & OrderForm */}
          <div className="col-span-3 grid grid-rows-[55%_45%] gap-2 min-h-0">
            <div className="grid grid-rows-[60%_40%] gap-2 min-h-0">
               <OrderBook />
               <RecentTrades />
            </div>
            <OrderForm />
          </div>
        </main>
        
        <Leaderboard />
      </div>
    </ExchangeStoreProvider>
  );
};

export default App;
