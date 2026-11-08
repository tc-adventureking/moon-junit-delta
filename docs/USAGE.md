# 使用指南

## 两份报告

```sh
node bin/junit-delta.mjs compare --baseline examples/baseline.xml --candidate examples/candidate.xml --format json
```

源码启动器要求 `moon` 在 PATH 中，会执行增量构建；便携包只需要 Node.js 24。退出码 1 表示选中的门禁命中，2 才是输入/用法错误。通过时退出码为 0。CLI 的错误信息写到 stderr，正常报告写到 stdout。

## 参数

| 参数 | 默认值 | 用途 |
|---|---|---|
| `--baseline FILE` | 必需 | 可重复，代表从旧到新的历史运行；最后一个是直接基准 |
| `--candidate FILE` | 必需 | 可重复，合并为同一次当前运行的分片 |
| `--format json\|md\|text` | text | 输出格式 |
| `--duplicates error\|attempts` | error | 是否明确把重复 ID 当作顺序重试 |
| `--fail-on LIST\|none` | new_failure,added_failing,removed,empty_report | 逗号分隔的门禁集合；替换默认值 |
| `--slowdown-pct N` | 50 | 相对耗时增加阈值（严格大于） |
| `--slowdown-floor-ms N` | 200 | 绝对增加下限（大于等于），整数毫秒 |
| `--limit N` | 50 | Markdown 展示数量，0..100000；不影响 JSON 或判定 |

门禁全集为 `new_failure,added_failing,still_failing,removed,newly_skipped,flaky,slowdown,empty_report`。未知参数、未知门禁和重复的单值选项报错，避免拼写错误导致静默放行。

`-` 作为文件名读取 stdin，一次比较最多使用一次。UTF-8 BOM 可接受；其他编码或非法 UTF-8 字节拒绝。没有 shell 通配符展开，使用多个 `--candidate` 或 JSONL 描述分片。

## 历史与分片

```sh
# 两个基准是不同运行：旧历史、最近基准
node bin/junit-delta.mjs compare --baseline examples/history.xml --baseline examples/baseline.xml --candidate examples/candidate.xml --format md
```

若**基准运行也有多个分片**，使用 JSONL，避免把分片误当历史。每行一个 JSON 对象：

```json
{"baselines":[[{"xml":"<testsuite><testcase name='a'/></testsuite>","source":"base-1"},{"xml":"<testsuite><testcase name='b'/></testsuite>","source":"base-2"}]],"candidate":[{"xml":"<testsuite><testcase name='a'/></testsuite>","source":"head-1"},{"xml":"<testsuite><testcase name='b'/></testsuite>","source":"head-2"}]}
```

将内容存为 UTF-8 `requests.jsonl`，运行：

```sh
node bin/junit-delta.mjs jsonl < requests.jsonl
```

上例使用 POSIX shell 重定向。PowerShell 可用 `Get-Content -Raw -Encoding utf8 requests.jsonl | node bin/junit-delta.mjs jsonl`；源文件必须 UTF-8，终端编码也需支持输入字符。

`baselines` 外层数组是时间顺序，一个元素可为单个 document 或 document 数组。`candidate` 同样支持 document 或数组。document 字段为 `xml` 和可选 `source`（默认 `<input>`）。可选顶层字段：

```json
{"duplicates":"error","fail_on":["new_failure","added_failing","removed","empty_report"],"slowdown_pct":50,"slowdown_floor_us":200000}
```

JSON 协议的绝对阈值使用微秒；CLI 使用毫秒。比较请求 `op` 默认为 `compare`。仅解析原始报告：

```json
{"op":"parse","document":{"xml":"<testsuite><testcase name='x'/></testsuite>","source":"report.xml"}}
```

成功响应含 `ok:true,exit_code,report`；失败响应含 `ok:false,exit_code:2,error_code,error`。每行独立处理，某一行失败不会吞掉其他行的结果；进程退出码为所有行最大值。空白行忽略。

请求根对象和每个 document 都拒绝未知字段。拼错 `fail_on` 不会静默使用默认策略：响应为 `error_code:"unknown_field"`、退出码 2，并提供括号式 JSON 路径，例如 `$["baselines"][0]["sorce"]`。不同操作只接受各自的字段，`op:"parse"` 不接受比较门禁选项。

## CI 集成

先从可信构建产物取得基准与当前 XML，再运行：

```sh
node bin/junit-delta.mjs compare --baseline baseline.xml --candidate current.xml --format md > junit-delta.md
```

默认 `set -e` 的 CI shell 在门禁命中时停止，报告文件仍保留。只想先观察时用 `--fail-on none`。希望任何当前失败都阻断时，把 `still_failing` 加入列表；希望失败变跳过也阻断时，加上 `newly_skipped`。自定义列表会替换默认集合，因此需要显式保留仍想要的默认项。

它不会为你下载基准、上传产物、评论 PR 或重跑测试。这些操作由现有 CI 配置完成。报告字段来自输入，应按你所在 CI 的权限策略保存或公开。

## 库入口

| 入口 | 用途 |
|---|---|
| `parse_document(xml, source?)` | 原始 JUnit 读取，保留重复与标记 |
| `parse_report(xml, source?, duplicates?)` | 加入测试身份和重复策略 |
| `merge_reports(reports, duplicates?)` | 归并一次运行的分片 |
| `compare(history, candidate, config?)` | 按最终基准比较，附加历史信息 |
| `diff_config(...)` | 校验门禁与时长配置 |
| `to_json / to_json_string / to_markdown / to_text` | 渲染比较结果 |
| `evaluate_request(text)` | 无 I/O 的结构化 JSON 请求 |
| `run_cli(args, read)` | 可注入读取函数的纯核心 CLI |

完整类型见 `pkg.generated.mbti`。`InputError` 由调用方处理，不能把解析错误替换为空报告。公开结构字段可读取；跨目标核心不依赖 Node，Node 仅负责文件/标准输入、UTF-8 解码与退出码。
