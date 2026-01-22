import { walletClient, publicClient } from '../client';
import { EXCHANGE_ABI } from '../abi';
import { EXCHANGE_ADDRESS as ADDRESS } from '../config';

/**
 * FundingKeeper Service - 脚手架版本
 *
 * 这个服务负责定期调用合约的 settleFunding() 函数，
 * 触发全局资金费率结算。
 *
 * TODO: 学生需要实现以下功能：
 * 1. 定时检查是否到达 fundingInterval
 * 2. 调用合约的 settleFunding 函数
 */
export class FundingKeeper {
    private intervalId: NodeJS.Timeout | null = null;
    private isRunning = false;

    constructor(private intervalMs: number = 60000) { } // 默认每分钟检查一次

    start() {
        if (this.isRunning) return;
        this.isRunning = true;
        console.log(`[FundingKeeper] Starting funding settlement checks every ${this.intervalMs}ms...`);

        this.checkAndSettle();
        this.intervalId = setInterval(() => this.checkAndSettle(), this.intervalMs);
    }

    stop() {
        if (this.intervalId) {
            clearInterval(this.intervalId);
            this.intervalId = null;
        }
        this.isRunning = false;
        console.log('[FundingKeeper] Stopped.');
    }

    /**
     * 检查并结算资金费率
     *
     * TODO: 实现以下逻辑：
     * 1. 读取合约的 lastFundingTime 和 fundingInterval
     * 2. 判断当前时间是否超过 lastFundingTime + fundingInterval
     * 3. 如果是，调用 settleFunding()
     */
    private async checkAndSettle() {
    try {
        // Step 1: 读取合约状态
        const lastFundingTime = await publicClient.readContract({
            address: ADDRESS as `0x${string}`,
            abi: EXCHANGE_ABI,
            functionName: 'lastFundingTime',
        }) as bigint;

        const fundingInterval = await publicClient.readContract({
            address: ADDRESS as `0x${string}`,
            abi: EXCHANGE_ABI,
            functionName: 'fundingInterval',
        }) as bigint;

        // Step 2: 判断是否需要结算
        const now = BigInt(Math.floor(Date.now() / 1000));
        if (now < lastFundingTime + fundingInterval) {
            console.log(`[FundingKeeper] Not yet time. Next settlement in ${Number(lastFundingTime + fundingInterval - now)}s`);
            return;
        }

        // Step 3: 调用 settleFunding
        console.log('[FundingKeeper] Time to settle funding...');
        const hash = await walletClient.writeContract({
            address: ADDRESS as `0x${string}`,
            abi: EXCHANGE_ABI,
            functionName: 'settleFunding',
            args: []
        });
        await publicClient.waitForTransactionReceipt({ hash });
        console.log(`[FundingKeeper] Settlement tx: ${hash}`);

    } catch (e) {
        console.error('[FundingKeeper] Error:', e);
    }
}
}
