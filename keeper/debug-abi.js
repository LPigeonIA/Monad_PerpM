const fs = require('fs');
const path = require('path');

const abiPath = path.resolve(__dirname, '../frontend/onchain/ExchangeABI.ts');
const content = fs.readFileSync(abiPath, 'utf8');

// 简单的提取逻辑，假设文件格式是 export const EXCHANGE_ABI = [...];
const match = content.match(/export const EXCHANGE_ABI = (\[.*\])(?: as const)?;/s);

if (!match) {
    // 尝试直接查找 JSON 数组
    const start = content.indexOf('[');
    const end = content.lastIndexOf(']');
    if (start !== -1 && end !== -1) {
        const jsonStr = content.substring(start, end + 1);
        try {
            const abi = JSON.parse(jsonStr);
            const func = abi.find(item => item.name === 'updateIndexPrice');
            console.log('Found function:', JSON.stringify(func, null, 2));
        } catch (e) {
            console.log('JSON parse error:', e.message);
        }
    } else {
        console.log('Could not find ABI array');
    }
} else {
    try {
        const abi = JSON.parse(match[1]);
        const func = abi.find(item => item.name === 'updateIndexPrice');
        console.log('Found function:', JSON.stringify(func, null, 2));
    } catch (e) {
        console.log('JSON parse error from regex match:', e.message);
    }
}
