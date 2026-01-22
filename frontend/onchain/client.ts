import { createPublicClient, createWalletClient, custom, defineChain, http, publicActions, walletActions } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { CHAIN_ID, RPC_URL } from './config';
import { anvil } from 'viem/chains';

const TEST_PK_1 = '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d'; // anvil index 1 (Bob)
const TEST_PK_2 = '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a'; // anvil index 2 (Carol)
const TEST_PK_0 = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'; // anvil index 0 (Alice)

export const ACCOUNTS = [
  privateKeyToAccount(TEST_PK_0),
  privateKeyToAccount(TEST_PK_1),
  privateKeyToAccount(TEST_PK_2),
];

export const chain = anvil

export const publicClient = createPublicClient({
  chain,
  transport: http(RPC_URL),
  pollingInterval: 500, // 500ms 轮询，配合 Anvil 1秒出块
});

export const fallbackAccount = ACCOUNTS[0];


export const getWalletClient = (account = fallbackAccount) => {
  return createWalletClient({
    chain,
    transport: http(RPC_URL),
    account,
  }).extend(publicActions).extend(walletActions);
};
