import json
import os

# 路径配置
artifact_path = '../contract/out/Exchange.sol/MonadPerpExchange.json'
output_path = '../frontend/onchain/ExchangeABI.json'

try:
    # 1. 读取 Artifact
    if not os.path.exists(artifact_path):
        print(f"Error: Artifact not found at {artifact_path}")
        print("Please run 'cd contract && forge build' first.")
        exit(1)
        
    with open(artifact_path, 'r') as f:
        data = json.load(f)
        
    # 2. 提取 ABI
    if 'abi' not in data:
        print("Error: 'abi' field not found in artifact.")
        exit(1)
        
    abi = data['abi']
    
    # 3. 写入目标文件
    with open(output_path, 'w') as f:
        json.dump(abi, f, indent=2)
        
    print(f"Success! ABI extracted to {output_path}")
    
except Exception as e:
    print(f"Failed: {e}")
