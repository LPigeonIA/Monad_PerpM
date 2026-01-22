<div align="center">
<img width="1200" height="475" alt="GHBanner" src="https://github.com/user-attachments/assets/0aa67016-6eaf-458a-adb2-6e31a0763ed6" />
</div>

# Run and deploy your AI Studio app

This contains everything you need to run your app locally.

View your app in AI Studio: https://ai.studio/apps/temp/1

## Run Locally

**Prerequisites:**  Node.js


1. Install dependencies:
   `npm install`
2. Set the `GEMINI_API_KEY` in [.env.local](.env.local) to your Gemini API key
3. Run the app:
   `npm run dev`

## On-chain configuration
The UI now reads/writes against the `MonadPerpExchange` contract. Set the following in `.env.local`:
```
VITE_RPC_URL=http://127.0.0.1:8545
VITE_CHAIN_ID=31337
VITE_EXCHANGE_ADDRESS=0x...   # address from forge script output
VITE_EXCHANGE_DEPLOY_BLOCK=0   # optional, narrows log queries
VITE_TEST_PRIVATE_KEY=0x...    # 可选，测试私钥（本地链，用于无注入钱包的场景）
```
Start an `anvil --fork-url <rpc>` node, deploy via `forge script script/DeployExchange.s.sol:DeployExchangeScript --broadcast`, then connect your injected wallet to the anvil network.
