import { createPublicClient, createWalletClient, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { foundry } from 'viem/chains';
import { RPC_URL, PRIVATE_KEY } from './config';

export const account = privateKeyToAccount(PRIVATE_KEY as `0x${string}`);

export const publicClient = createPublicClient({
    chain: foundry,
    transport: http(RPC_URL)
});

export const walletClient = createWalletClient({
    account,
    chain: foundry,
    transport: http(RPC_URL)
});
