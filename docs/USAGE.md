# 使用指南

Mooncakes 提供库与 API；以下命令在源码仓库运行，需要 MoonBit 和 Node.js 24。源码启动器自动增量编译，报告写入 stdout，错误写入 stderr。

## CLI 参数

```sh
node bin/junit-delta.mjs compare --baseline baseline.xml --candidate current.xml --format json
```

| 参数 | 默认值 | 用途 |
|---|---|---|
| `--baseline FILE` | 必需 | 可重复，按时间从旧到新；最后一个是直接基准 |
| `--candidate FILE` | 必需 | 可重复，归并为当前运行的分片 |
| `--format json\|md\|text` | text | 输出格式 |
| `--duplicates error\|attempts` | error | 是否将重复 ID 解释为有序重试 |
| `--fail-on LIST\|none` | new_failure,added_failing,removed,empty_report | 逗号分隔，替换默认门禁集合 |
| `--slowdown-pct N` | 50 | 相对耗时增加阈值，严格大于 |
| `--slowdown-floor-ms N` | 200 | 绝对增加下限，大于等于，整数毫秒 |
| `--limit N` | 50 | Markdown 展示数量，0..100000；不影响判定 |

其他可选门禁为 `still_failing,newly_skipped,flaky,slowdown`。`--fail-on none` 只输出报告。退出码 `0` 表示通过，`1` 表示门禁命中，`2` 表示输入或运行错误。单个文件名 `-` 读取标准输入；一次比较最多使用一次。

## JSONL 协议

每行一个 JSON 请求。把下方任一场景的完整 JSON 保存为 UTF-8 `request.jsonl`，在 POSIX shell 中运行：

```sh
node bin/junit-delta.mjs jsonl < request.jsonl
```

PowerShell 可使用 `Get-Content -Raw -Encoding utf8 request.jsonl | node bin/junit-delta.mjs jsonl`，终端编码须支持输入字符。

`baselines` 外层数组按时间排列；每个元素为一个 document 或同次运行的 document 数组。`candidate` 同样接受单份或分片数组。document 含 `xml` 和可选 `source`。可选字段为 `duplicates`、`fail_on`、`slowdown_pct`、`slowdown_floor_us`；JSON 的绝对时长阈值使用微秒。

只读取原始报告时使用：

```json
{"op":"parse","document":{"xml":"<testsuite><testcase name='a'/></testsuite>"}}
```

比较请求的 `op` 默认为 `compare`。成功响应含 `ok:true,exit_code,report`；错误响应含 `ok:false,exit_code:2,error_code,error`。未知或重复字段拒绝，每行独立处理，进程取最大退出码。空白行忽略，空输入返回 0；达到整批输出上限时追加带行号的 `output_limit` 错误并停止。

## 三个使用场景

### 合并请求回归检查

开发者比较主分支与合并请求报告。两次都只有一个失败，但失败对象发生变化：

```json
{"baselines":[{"xml":"<testsuite><testcase classname='api' name='login'/><testcase classname='api' name='refresh'><failure/></testcase></testsuite>"}],"candidate":{"xml":"<testsuite><testcase classname='api' name='login'><failure/></testcase><testcase classname='api' name='refresh'/></testsuite>"}}
```

运行上述 JSONL 命令，报告包含 login 的 `new_failure` 和 refresh 的 `fixed`，退出码 **1**。CI 据此阻断合并，开发者定位新增问题，同时保留修复记录。

### 重试与历史波动审查

维护者提供先失败、后通过的历史，以及当前先通过、后失败的有序重试，显式启用 `attempts`：

```json
{"baselines":[{"xml":"<testsuite><testcase classname='api' name='login'><failure/></testcase></testsuite>"},{"xml":"<testsuite><testcase classname='api' name='login'/></testsuite>"}],"candidate":{"xml":"<testsuite><testcase classname='api' name='login'/><testcase classname='api' name='login'><failure/></testcase></testsuite>"},"duplicates":"attempts"}
```

报告将最终结果列为 `new_failure`，保留历史波动与当前重试注记，退出码 **1**。维护者可以审查不稳定用例，当前失败仍阻断合并。

### 分片迁移完整性检查

CI 维护者将原有 auth、billing、audit 用例迁入两个分片；当前报告遗漏 audit：

```json
{"baselines":[{"xml":"<testsuite><testcase classname='api' name='auth'/><testcase classname='api' name='billing'/><testcase classname='api' name='audit'/></testsuite>"}],"candidate":[{"xml":"<testsuite><testcase classname='api' name='auth'/></testsuite>","source":"core"},{"xml":"<testsuite><testcase classname='api' name='billing'/></testsuite>","source":"extra"}]}
```

归并结果有两个 `unchanged`、一个 `removed`，退出码 **1**。维护者检查分片筛选；有意移除的用例经确认后更新基准。再次上传相同分片会因重复 ID 返回 **2**。

## 比较 API 与行为约定

| 入口 | 用途 |
|---|---|
| `parse_document(xml, source?)` | 原始读取，保留重复项与独立结果标记 |
| `parse_report(xml, source?, duplicates?)` | 建立身份并应用重复策略 |
| `merge_reports(reports, duplicates?)` | 归并一次运行的分片 |
| `compare(history, candidate, config?)` | 按最后基准比较，附加历史信息 |
| `diff_config(...)` | 校验门禁与耗时配置 |
| `to_json / to_json_string / to_markdown / to_text` | 渲染比较结果 |
| `evaluate_request(text)` | 无 I/O 的 JSON 请求入口 |
| `run_cli(args, read)` | 可注入读取函数的 CLI 核心 |

完整签名见[公开 API](../pkg.generated.mbti)。比较 JSON 的 [Schema](../schemas/report.schema.json) 对应 `schema_version:1`，只约束比较 report，不约束请求或原始读取结果。

- 身份有 classname 时使用 `(classname, name)`，否则使用完整套件路径与名称；保留空白和大小写。支持嵌套套件及 Node 根 `testsuites` 直接包含 `testcase` 的布局，汇总属性不代替逐条结果。
- 默认重复报错；`Attempts` 按 XML 原文及传入分片顺序采用最后记录，累加尝试次数。跳过与其他状态混合拒绝；Surefire flaky 与 rerun 标记参与重试解释。原始结果标记互相独立，最终状态优先级为 error、failure、skipped、passed。
- 比较范围为最后基准与当前 ID 的并集；更早历史只提供波动和耗时参考。历史波动不改变分类或默认门禁。
- 时长接受非负十进制秒数，向下截断到整数微秒，范围 `0..9,000,000,000,000`。耗时筛查只检查最后基准及当前均通过的记录，以历史通过时长的下中位数为参考，同时满足百分比与绝对增量阈值。
- 公开集合为只读；需要可变副本时用 `items.iter().to_array()`。解析、比较及渲染可能抛出 `InputError`，调用方应处理。

## 比较接口的输入与输出边界

| 对象 | 上限 |
|---|---|
| 单份 XML | 10,000,000 UTF-16 单元、深度 128、2,000,000 读取事件 |
| XML 元素属性 | 每元素 1,024 个 |
| 用例 | 单份或单次归并 100,000 个；单 ID 最多 1,000,000 次尝试 |
| 历史与分片 | 50 次历史运行，每运行最多 50 份报告 |
| CLI 输入 | 单文件/标准输入 20,000,000 字节；比较或 JSONL 合计 20,000,000 UTF-16 单元 |
| 渲染 | 单次或 JSONL 整批 100,000,000 UTF-16 单元；可用 `max_units` 调低 |

XML 采用 UTF-8，可含 BOM；拒绝 DTD、损坏结构、重复属性以及命名空间化的 JUnit 元素。仅放行根节点的 Surefire `xmlns:xsi` 与 `xsi:noNamespaceSchemaLocation` 元数据，不访问其 URL。JSONL 整批读取。

结果消息最多保留 2,048 UTF-16 单元，截断附 `message_truncated`；忽略 system-out/system-err。Markdown 默认展示前 50 条变化或注记，JSON 保留全部条目，超限报 `output_limit`。`to_json` 预算按默认紧凑 `stringify()` 计量，调用方额外缩进或修改后需管理新的大小。

读取行为参考 junitparser 5.0.3。完整 XML 创建、编辑、写回和扩展保留使用新增的 [JUnitDocument 接口](JUNIT_XML.md)；本页的消息截断与命名空间限制只描述比较接口。自动重跑、基准下载及 GitHub 网络集成仍由宿主管理。
