# 与成熟生态的兼容范围

## 直接对标：junitparser 5.0.3

基准是 [weiwei/junitparser](https://github.com/weiwei/junitparser) 的 xUnit2 读取 API。发布文件为 `junitparser-5.0.3-py3-none-any.whl`，SHA-256：

```text
553535b8cd1672a9c8bd2c7326ae1ae69279267fbc562106b5aa44d3c5f769af
```

以 UTF-8 字节调用 `xunit2.JUnitXml.fromstring`，随后遍历 suite / testcase，并调用公开属性。对每份共同支持的输入，逐条比较以下字段，不把 MoonBit 的单一最终状态反推为上游原始标记。

| 上游行为 | 本项目 API | 契约 |
|---|---|---|
| `name` / `classname` | 同名字段 | XML 解码后的精确字符串；缺失 classname 为 None，空字符串仍为空 |
| testcase 遍历 | `parse_document().cases` | 同一套件的直接用例在其子套件之前；套件间保留顺序 |
| 重复 testcase | `parse_document` | 原样保留，不静默去重 |
| `is_passed` | 同名方法 | 没有 final result 元素 |
| `is_failure` / `is_error` / `is_skipped` | 同名方法 | 独立布尔值，可能同时为真 |
| `is_flaky` / `is_rerun` | 同名方法 | 分别来自 flaky、rerun 临时结果元素 |
| `interim_result` 数量 | `interim_results.length()` | 临时结果数一致 |

这些方法描述原始 XML 标记。`TestCase.flaky` 还可能在显式重复项归并后为真，它与原始 `is_flaky()` 的含义不同。

额外支持 Node 报告器将 `testcase` 直接放在根 `testsuites` 下的平铺布局。这是实际生产端验证的扩展，不宣称其遍历行为与 junitparser 等价；普通套件布局仍执行上述逐字段对标。

## 验证范围

固定随机种子 `20261109`，1,079 份输入：1,053 份支持范围内结果一致，26 份由本项目明确拒绝，零未解释差异。输入包含 35 组状态组合、重复及嵌套套件、Unicode/空白/XML 实体、七份夹具、1,000 份生成报告和拒绝边界。

公共 [回归向量](https://github.com/tc-adventureking/moon-junit-delta/blob/main/fixtures/junitparser-contract.json) 保存其中 207 份输入及成熟库产生的期望投影，包含全部手工边界与 128 份生成报告。`node scripts/contract.mjs` 不依赖 Python，逐条比较输出或拒绝代码；任何字段或顺序差异都会失败。

完整开发源码提供 `scripts/reference/junitparser_diff.py`，固定 wheel 哈希、生成全部输入、调用上游公开 API 并与实际 MoonBit 输出比较。它直接从 wheel 导入纯 Python 包，无需安装上游代码；Python 只用于开发验证。可在新 venv 中再生 207 份向量并逐字节比较，步骤见 [TESTING](https://github.com/tc-adventureking/moon-junit-delta/blob/main/docs/TESTING.md)。CI 同时执行动态差分与保存向量回放，二者是不同检查。

## 有意收窄的输入

| 情况 | 拒绝代码 | 原因 |
|---|---|---|
| name 缺失或为空 | `missing_name` | 比较器需要稳定测试身份 |
| 负数、指数、非有限数、带空白时长或超界 | `invalid_time` | 明确十进制整数微秒契约，避免浮点舍入与无意义耗时 |
| skipped 与 retry 同时出现；无外层失败的 rerun | `retry_conflict` | 不猜测矛盾的最终状态 |
| 默认命名空间、带前缀的元素或非白名单命名空间属性 | `unsupported_namespace` | 仅放行根节点上绑定 W3C 实例 URI 的 xmlns:xsi 和 xsi:noNamespaceSchemaLocation 元数据；JUnit 元素仍必须无命名空间 |
| DTD | `doctype` | 不解析或读取外部实体 |
| 非 UTF-8 编码声明 | `unsupported_encoding` | CLI 与库采用统一编码范围 |
| 包裹在未知元素中的 testcase / result、嵌套 testsuites | `invalid_structure` | 不把隐藏的结果误作正常用例 |
| 损坏 XML、重复属性或多个根 | `malformed_xml` | 解析失败不能当成测试通过 |
| 超过资源边界 | `limit_exceeded` | 有界的本地处理 |

并非表中每一项都被上游接受；拒绝测试同时记录上游是否接受。未列出的共同支持输入出现差异会视为缺陷，不通过调整基准输出掩盖。

## 比较层是本项目的契约

`parse_report` 在原始读取之上增加重复策略，`compare` 增加回归分类、历史注记和门禁；它们没有宣称与 junitparser 的写入、合并或统计 API 等价。时长由原始十进制文本计算，不对标上游浮点属性。

[junit-xml-diff](https://github.com/insightsengineering/junit-xml-diff) 主要侧重耗时/计数，未采用其身份与重复聚合逻辑；[publish-unit-test-result-action](https://github.com/EnricoMi/publish-unit-test-result-action) 提供实际夹具与结果报告场景参考，但 GitHub 网络集成不是本项目范围。

不实现 XML 编辑或写回、任意 xUnit 扩展、跨平台自动重命名匹配、自动重跑、JUnit5 测试执行器或统计显著性分析。已真实执行 pytest 8.4.2 / 9.2.0（xunit1、xunit2、参数化及分片）、Maven Surefire 3.5.4 / 3.6.1（JUnit 5.11.4 / 6.1.3、失败重跑及 flaky 成功）和 Node.js 24 的报告生成与端到端检查。公共 CI 持续运行两组生产端配置；原始机器报告只保留在忽略的构建目录中。GitLab 使用注明来源的作者构造样例，没有声称执行 GitLab 服务。
