# junit-delta

纯 MoonBit JUnit XML 读取、归并与回归比较库。以 junitparser 5.0.3 的读取行为为参考，支持 wasm、wasm-gc、JavaScript 和 native；XML 解析依赖 Milky2018/xml 0.6.1。

## 功能

- **读取 `parse_document`**：嵌套套件、精确身份、独立结果标记和 Surefire 重试信息。
- **归并 `parse_report` / `merge_reports`**：分片合并和显式重试策略；重复 ID 默认报错。
- **比较 `compare`**：新增失败、修复、持续失败、移除和跳过变化，以及历史波动注记和耗时变化筛查。
- **输出 `DiffResult`**：JSON、Markdown、文本摘要与可配置 CI 门禁；JSON 比较报告提供 Schema。

时长使用整数微秒；历史波动注记不放行当前失败。重试采用最后一次结果，跳过与其他状态混合时拒绝。

## 安装与使用

在 MoonBit 项目目录中安装：

```bash
moon add tc-adventureking/junit_delta@0.2.0
```

运行下方示例的包使用以下 `moon.pkg`：

```moonbit
import { "tc-adventureking/junit_delta" @delta, }

pkgtype(kind: "executable")
```

## 示例

将下例保存为该包的 `main.mbt`，运行 `moon run . --target js`：

```moonbit
fn main raise {
  let before = @delta.parse_report(
    "<testsuite><testcase classname='api' name='login'/></testsuite>",
  )
  let after = @delta.parse_report(
    "<testsuite><testcase classname='api' name='login'><failure/></testcase></testsuite>",
  )
  let result = @delta.compare([before], after)
  println(result.entries[0].category)
  println(result.exit_code())
}
```

输出 `new_failure` 和 `1`。调用方需处理 `InputError`；库返回的门禁码可供应用设置进程退出码。

[完整 API](pkg.generated.mbti) · [使用指南与三个场景](docs/USAGE.md) · [JSON Schema](schemas/report.schema.json)

## JUnit 报告 CLI

在源码仓库中运行，需要 MoonBit 和 Node.js 24：

```bash
node bin/junit-delta.mjs compare --baseline baseline.xml --candidate current.xml
node bin/junit-delta.mjs compare --baseline baseline.xml --candidate current.xml --format json
```

退出码：`0` 门禁通过，`1` 命中门禁，`2` 输入或运行错误。支持多份历史、当前分片、标准输入 `-` 和 JSONL。默认拦截新增失败、新增且失败的用例、移除和空报告；`--fail-on` 可替换门禁集合。[参数与协议](docs/USAGE.md)。

## 许可

项目代码使用 [MIT](LICENSE)。成熟库参考、XML 依赖及 MoonBit 标准库的来源与许可见[第三方声明](third_party/NOTICE.md)。本项目使用 AI 辅助设计与实现。
