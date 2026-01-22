import dotenv from 'dotenv';
import path from 'path';

// 优先读取 frontend/.env.local（部署脚本自动更新）
dotenv.config({ path: path.resolve(__dirname, '../../frontend/.env.local') });

export const RPC_URL = process.env.VITE_RPC_URL || 'http://127.0.0.1:8545';
export const PRIVATE_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'; // Anvil Account #0 (Operator)
export const EXCHANGE_ADDRESS = process.env.VITE_EXCHANGE_ADDRESS || '0x4a77a17932864b4e29f3aa65246f65f2e8a91bdb';
