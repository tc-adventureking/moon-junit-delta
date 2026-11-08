# 来源、复用与 AI 协作

本项目先调查已有实现，再补齐 MoonBit JUnit 输入比较与门禁这一范围。没有把成熟 XML 解析器重写一遍，也没有把参考项目的业务实现复制成 MoonBit。

| 来源 | 用途 | 许可 / 固定版本 |
|---|---|---|
| [moonbit-community/xml-mbt](https://github.com/moonbit-community/xml-mbt) | XML pull reader，实际运行依赖 | Milky2018/xml 0.6.1，Apache-2.0 |
| [moonbitlang/core](https://github.com/moonbitlang/core) | 标准库，随编译产物包含相关实现 | 本地 2026-10-23 工具链，Apache-2.0 |
| [weiwei/junitparser](https://github.com/weiwei/junitparser) | 直接读取语义基准与期望结果生成 | 5.0.3，Apache-2.0；不作为运行依赖 |
| [EnricoMi/publish-unit-test-result-action](https://github.com/EnricoMi/publish-unit-test-result-action) | 上游 pytest XML 夹具 | 固定树 da5b7be67623cd59bbbd1a0ce4f022050a55605f，Apache-2.0 |
| Surefire、pytest、GitLab、Node 官方文档 | 已声明输入范围与作者构造的示例 | 链接及实际执行情况见夹具来源 |

第三方许可全文在 `third_party/`。上游 pytest XML 文件按原文本保存；其在 JSON 回归向量中的重复内容同样保留上游署名。Node 夹具来自本项目测试代码生成，主机名及绝对路径做了便携替换。其他夹具和完整来源见 [fixtures/SOURCES.md](../fixtures/SOURCES.md)。

固定 wheel 的成熟库动态差分工具在完整开发源码 `scripts/reference/` 公开，可在隔离环境重跑；不进入运行时或 MoonBit 模块包。独立的比较层 Python 参考和模型日志保留在本地。公共回归向量保存实际成熟库输出，不是由待测 MoonBit 实现自举期望值；公共 CI 执行动态差分并回放向量，见 [TESTING](TESTING.md)。

选题调研同时查看 TapTrail、MoonProbe、mcpconftest 与 SARIF 相关项目。它们分别侧重 TAP 输入、测试执行/结果输出或其他报告格式；这次检索没有找到同范围的 MoonBit JUnit 输入比较器，不等于证明生态中绝无类似项目。

## AI 协作声明

Claude Opus 5.5 参与选题、设计裁决和最终审查，调用请求 effort=xhigh；响应模型名称通过本地 CLI 元数据核验。Codex 负责实现、文档、实际构建和验证，设计中关于精确身份、重复项、retry 冲突和历史 flaky 的意见经过来回修订。

代码是否正确以运行测试和可检查的结果为准，模型审查不能代替验证。交付内容不包含个人配置、会话日志、凭据或模型调用脚本。对项目的熟悉程度不能由 AI 完成度替代；演示者应能解释输入→身份→分类→门禁这一条主路径，并独立复现示例。
