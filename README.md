# junit-delta

纯 MoonBit JUnit XML 读取、归并与回归比较库。以 junitparser 5.0.3 的读取行为为参考，支持 wasm、wasm-gc、JavaScript 和 native；XML 解析依赖 Milky2018/xml 0.6.1。

## 功能

- **读取 `parse_document`**：嵌套套件、名称与类名、重复记录、独立结果标记和 Surefire 重试信息。
- **归并 `parse_report` / `merge_reports`**：精确测试身份、分片合并和显式重试策略；重复 ID 默认报错。
- **比较 `compare`**：新增失败、修复、持续失败、移除和跳过变化，以及历史波动注记和耗时变化筛查。
- **输出 `DiffResult`**：JSON、Markdown、文本摘要与可配置 CI 门禁；JSON 比较报告提供 Schema。

时长使用整数微秒；历史波动注记不放行当前失败。重试采用最后一次结果，跳过与其他状态混合时拒绝。

## 安装与使用

在 MoonBit 项目目录中安装：

```bash
moon add tc-adventureking/junit_delta@0.2.0
```

在 `moon.pkg` 中导入：

```moonbit
import { "tc-adventureking/junit_delta" @delta, }
```

将下例保存为 `example.mbt`，运行 `moon test --target all`：

```moonbit
test "new failure" {
  let before = @delta.parse_report(
    "<testsuite><testcase classname='api' name='login'/></testsuite>",
  )
  let after = @delta.parse_report(
    "<testsuite><testcase classname='api' name='login'><failure/></testcase></testsuite>",
  )
  let result = @delta.compare([before], after)
  assert_eq(result.entries[0].category, "new_failure")
  assert_eq(result.exit_code(), 1)
}
```

有 classname 时以 `(classname, name)` 作为身份，否则使用完整套件路径。调用方需处理 `InputError`；仅显式指定 `Attempts` 时才将重复记录解释为重试。

[完整 API](pkg.generated.mbti) · [0.2 迁移](docs/MIGRATION.md) · [junitparser 对照与差异](docs/COMPATIBILITY.md) · [使用场景](https://github.com/tc-adventureking/moon-junit-delta/blob/main/examples/scenarios/README.md)

## 示例与测试

安装 MoonBit 工具链后在仓库运行：

```bash
moon test --deny-warn --target all
bash scripts/verify-package.sh
```

第二条命令会从新源码包创建独立 workspace，运行读取、比较和重试归并的消费示例。完整场景涵盖合并请求回归、重试审查和分片迁移。完整公开检查先运行 `npm ci --ignore-scripts`，再运行 `bash scripts/verify.sh`，需要 Node.js 24、`unzip` 和 C 工具链。固定成熟库动态差分另需 Python。[验证范围](https://github.com/tc-adventureking/moon-junit-delta/blob/main/docs/TESTING.md)。

## JUnit 报告 CLI

[Release](https://github.com/tc-adventureking/moon-junit-delta/releases/tag/v0.2.0) 提供源码包、MoonBit 模块包和只需 Node.js 24 的便携 CLI，附 SHA-256 校验。在仓库内读取基准与当前 XML，支持多份历史、当前分片和标准输入 `-`：

```bash
node bin/junit-delta.mjs compare --baseline examples/baseline.xml --candidate examples/candidate.xml
node bin/junit-delta.mjs compare --baseline examples/baseline.xml --candidate examples/candidate.xml --format json
```

退出码：`0` 门禁通过，`1` 命中门禁，`2` 输入或运行错误。默认拦截新增失败、新增且失败的测试、移除和空报告；`--fail-on` 可替换门禁集合。源码启动器需要 MoonBit；`python scripts/release.py` 在 `_build/archives/` 生成便携包，解压后只需 Node.js 24。[参数与 JSONL 协议](docs/USAGE.md) · [构建说明](https://github.com/tc-adventureking/moon-junit-delta/blob/main/docs/RELEASING.md)。

## 许可

项目代码使用 [MIT](LICENSE)；XML 库、MoonBit 标准库及上游夹具保留各自许可。来源与参考范围见 [PROVENANCE](docs/PROVENANCE.md) 和 [第三方声明](third_party/NOTICE.md)。
