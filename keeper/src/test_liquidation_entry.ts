import { Liquidator } from './services/Liquidator';

async function main() {
    console.log('--- Monad Exchange Liquidator Service (Test Mode) ---');

    const liquidator = new Liquidator(1000);   // Check every 1 second for faster testing

    await liquidator.start();

    // Handle shutdown
    process.on('SIGINT', () => {
        console.log('\nShutting down...');
        liquidator.stop();
        process.exit(0);
    });
}

main().catch(console.error);
