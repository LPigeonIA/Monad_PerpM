import type { Address } from 'viem';

const rpcUrl = import.meta.env.VITE_RPC_URL || 'http://127.0.0.1:8545';
const chainId = Number(import.meta.env.VITE_CHAIN_ID || 31337);
const exchangeAddressEnv = (import.meta.env.VITE_EXCHANGE_ADDRESS || '').trim();
const exchangeDeployBlockEnv = (import.meta.env.VITE_EXCHANGE_DEPLOY_BLOCK || '').trim();

export const RPC_URL = rpcUrl;
export const CHAIN_ID = chainId;
export const EXCHANGE_ADDRESS = exchangeAddressEnv && exchangeAddressEnv !== '0x' ? (exchangeAddressEnv as Address) : undefined;
export const EXCHANGE_DEPLOY_BLOCK = exchangeDeployBlockEnv ? BigInt(exchangeDeployBlockEnv) : 0n;
