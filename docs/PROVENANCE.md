# 来源、复用与 AI 协作

XML 解析复用生态内的实现，JUnit 读取层通过固定版本的成熟库差分验证；比较和门禁遵循本项目行为规格。

| 来源 | 用途 | 许可 / 固定版本 |
|---|---|---|
| [moonbit-community/xml-mbt](https://github.com/moonbit-community/xml-mbt) | XML pull reader，实际运行依赖 | Milky2018/xml 0.6.1，Apache-2.0 |
| [moonbitlang/core](https://github.com/moonbitlang/core) | 标准库，随编译产物包含相关实现 | MoonBit 当前 2026-11-05 编译器工具链，Apache-2.0 |
| [weiwei/junitparser](https://github.com/weiwei/junitparser) | 直接读取语义基准与期望结果生成 | 5.0.3，Apache-2.0；不作为运行依赖 |
| [EnricoMi/publish-unit-test-result-action](https://github.com/EnricoMi/publish-unit-test-result-action) | 上游 pytest XML 夹具 | 固定树 da5b7be67623cd59bbbd1a0ce4f022050a55605f，Apache-2.0 |
| [Apache Maven Surefire](https://github.com/apache/maven-surefire) | 上游重试夹具及实际 reporter 属性布局 | 固定树 c0d85abd7496ea2f0be9a6bf3915b11196596793，Apache-2.0 |
| [Ajv](https://github.com/ajv-validator/ajv) | 输出 JSON Schema 的独立开发校验器 | 8.20.0，MIT；不随 CLI 分发 |
| Surefire、pytest、GitLab、Node 官方文档 | 已声明输入范围与作者构造的示例 | 链接及实际执行情况见夹具来源 |

第三方许可全文在 `third_party/`。上游 pytest XML 文件按原文本保存；其在 JSON 回归向量中的重复内容同样保留上游署名。Node 夹具来自本项目测试代码生成，主机名及绝对路径做了便携替换。其他夹具和完整来源见 [fixtures/SOURCES.md](https://github.com/tc-adventureking/moon-junit-delta/blob/main/fixtures/SOURCES.md)。

固定 wheel 的成熟库动态差分工具在完整开发源码 `scripts/reference/` 公开，可在隔离环境重跑；不进入运行时或 MoonBit 模块包。公共回归向量保存实际成熟库输出，不是由待测 MoonBit 实现自举期望值；公共 CI 执行动态差分并回放向量，见 [TESTING](https://github.com/tc-adventureking/moon-junit-delta/blob/main/docs/TESTING.md)。

本项目开发使用 AI 辅助设计与实现。公开测试和提交记录用于核对实现行为。
