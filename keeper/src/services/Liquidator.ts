import { formatEther } from 'viem';
import { walletClient, publicClient } from '../client';
import { EXCHANGE_ABI } from '../abi';
import { EXCHANGE_ADDRESS as ADDRESS } from '../config';

/**
 * Liquidator Service - 脚手架版本
 * 
 * 这个服务负责监控用户健康度并执行清算。
 * 
 * TODO: 学生需要实现以下功能：
 * 1. 监听 OrderPlaced 和 TradeExecuted 事件，跟踪活跃交易者
 * 2. 定期检查每个交易者的健康度
 * 3. 对可清算的仓位调用合约的 liquidate 函数
 */
export class Liquidator {
    private intervalId: NodeJS.Timeout | null = null;
    private isRunning = false;
    private activeTraders = new Set<string>();

    constructor(private intervalMs: number = 10000) { }

    async start() {
        if (this.isRunning) return;
        this.isRunning = true;
        console.log(`[Liquidator] Starting liquidation checks every ${this.intervalMs}ms...`);

        // TODO: 实现事件监听
        // 提示: 使用 publicClient.watchContractEvent 监听 OrderPlaced 和 TradeExecuted

        this.intervalId = setInterval(() => this.checkHealth(), this.intervalMs);
    }

    stop() {
        if (this.intervalId) {
            clearInterval(this.intervalId);
            this.intervalId = null;
        }
        this.isRunning = false;
        console.log('[Liquidator] Stopped.');
    }

    /**
     * 检查所有活跃交易者的健康度
     * 
     * TODO: 实现此函数
     * 步骤:
     * 1. 遍历 activeTraders
     * 2. 读取每个交易者的 margin 和 position
     * 3. 模拟调用 liquidate 检查是否可清算
     * 4. 如果可清算，发送实际交易
     */
    private async checkHealth() {
        if (this.activeTraders.size === 0) {
            console.log('[Liquidator] No active traders to check.');
            return;
        }

        console.log(`[Liquidator] Checking health for ${this.activeTraders.size} traders...`);

        // TODO: 实现健康度检查逻辑
        // 提示:
        // - 使用 publicClient.readContract 读取 margin 和 getPosition
        // - 使用 publicClient.simulateContract 测试是否可清算
        // - 使用 walletClient.writeContract 执行清算

        console.log('[Liquidator] Health check not implemented yet.');
    }
}
