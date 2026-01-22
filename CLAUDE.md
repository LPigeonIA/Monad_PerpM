# Claude Code 项目规则

## Git 提交规范

- commit 消息使用中文
- 不要添加 Claude Code 生成标记
- 不要添加 Co-Authored-By 信息

## Day Guide 验证规范

当用户请求验证某一天的 Guide（如 `验证 day1`、`verify day 3`、`测试第5天`）时，**必须先阅读并严格遵循 `VERIFY_DAY_GUIDE.md` 中的完整验证流程**：

1. 首先执行 `Read VERIFY_DAY_GUIDE.md` 获取完整验证规范
2. 按照规范中的流程进行验证：
   - 确认脚手架状态
   - 严格按 Guide 填充代码
   - 生成填充报告
   - 执行测试验证
   - 报告发现的问题
