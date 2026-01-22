import { PriceKeeper } from './services/PriceKeeper';
import { Liquidator } from './services/Liquidator';
import { FundingKeeper } from './services/FundingKeeper';

async function main() {
    console.log('--- Monad Exchange Keeper Service ---');

    const priceKeeper = new PriceKeeper(1000); // Update every 1 second
    const liquidator = new Liquidator(5000);   // Check every 5 seconds
    const fundingKeeper = new FundingKeeper(60000); // Check every 60 seconds

    priceKeeper.start();
    await liquidator.start();
    fundingKeeper.start();

    // Handle shutdown
    process.on('SIGINT', () => {
        console.log('\nShutting down...');
        priceKeeper.stop();
        liquidator.stop();
        fundingKeeper.stop();
        process.exit(0);
    });
}

main().catch(console.error);
