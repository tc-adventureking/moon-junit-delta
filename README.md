# moon-junit-delta

MoonBit 通用 JUnit XML 创建、读取、编辑、写回与比较库。通用报告接口以 junitparser 5.0.3 为行为参考，支持 wasm、wasm-gc、JavaScript 和 native；底层 XML 复用 Milky2018/xml。

[Mooncakes 包与 API](https://mooncakes.io/docs/tc-adventureking/junit_delta/) · [持续集成](https://github.com/tc-adventureking/moon-junit-delta/actions/workflows/test.yml)

## 功能

- **报告与套件 `JUnitXml` / `TestSuite`**：创建、解析、用例管理、properties、嵌套套件、惰性统计、归并和普通/pretty 写回。
- **用例与结果 `TestCase` / `TestResult`**：名称、类名、耗时、失败/错误/跳过结果、日志，以及 xUnit2 的重跑与不稳定测试记录。
- **XML 扩展 `Element`**：自定义元素和属性、命名空间、混合文本、类型转换回调，以及可替换的解码与解析入口。
- **文档与比较 `JUnitDocument` / `Report`**：保留不可变 XML 编辑、分片与重试归并、历史差异、JSON/Markdown 输出和 CI 门禁。

通用报告模型使用共享节点视图，修改视图会影响同一报告；`clone()` 创建深拷贝。文件和流通过宿主回调接入，解析与写回会构造完整报告树或输出。

## 安装与使用

最低编译器版本为 `moonc 1.0.0-rc1`。复现 CI 环境时，将环境变量 `MOONBIT_INSTALL_VERSION` 设为 `1.0.0-rc1+3c0520448` 后运行官方安装脚本，再用 `moonc -v` 核对版本。[MoonBit 安装指南](https://www.moonbitlang.com/download/)

在自己的 MoonBit 模块目录中安装库。如果要从空目录复现，先创建 `moon.mod`，写入一行 `name = "example/junit_demo"`。然后运行

```bash
moon update
moon add tc-adventureking/junit_delta@0.6.1
```

在同一目录的 `moon.pkg` 中添加测试依赖。

```moonbit
import { "tc-adventureking/junit_delta/junit" @junit, } for "test"
```

将下面的用例保存为同目录下的 `report_test.mbt`。

```moonbit
test "create and edit report" {
  let case = @junit.TestCase::new(name=Some("login"), time=Some(0.12))
  let suite = @junit.TestSuite::new(name=Some("service"))
  suite.add_case(case)
  let report = @junit.JUnitXml::new()
  report.add_suite(suite)

  case.element().set_attribute("file", Some("tests/login.mbt"))
  case.set_results([@junit.TestResult::new(Failure, message=Some("timeout"))])
  report.update_statistics()
  assert_false(case.is_passed())
  assert_eq(report.tests().unwrap().to_string(), "1")

  let xml = report.element().write_xml(pretty=true)
  let restored = @junit.JUnitXml::from_decoded(xml)
  let saved = restored.suites().next().unwrap().cases().next().unwrap()
  assert_eq(saved.element().attribute("file"), Some("tests/login.mbt"))
  assert_eq(restored.failures().unwrap().to_string(), "1")
}
```

运行 `moon test --deny-warn --target wasm-gc`。示例会创建一个用例，将它标记为失败，再读回 XML，检查文件名和失败数。

`from_string` 用于不含编码声明的 Unicode XML；带声明的字节输入使用 `from_bytes`，宿主已解码的文本使用 `from_decoded`。`pretty=true` 会调整混合内容的空白；通用模型与原不可变文档的统计、归并规则不同。

[完整 API](junit/pkg.generated.mbti) · [Python 对照与差异](docs/JUNIT.md) · [不可变 XML](docs/JUNIT_XML.md) · [使用场景](docs/USAGE.md)

## 示例与测试

安装 MoonBit、Node.js 24 和适用于 native 后端的 C 工具链后，在源码仓库根目录运行

```bash
moon update
moon check --deny-warn --target all
moon build --deny-warn --release --target all
moon test --deny-warn --target all
node --test tests/cli.test.mjs
moon run examples/edit --target wasm-gc
```

最后一条命令会输出 JUnit XML，其中 `service` 套件的 `tests="1"`，`login` 用例的 `file="login.mbt"`。回归测试覆盖 XML 解析与写回、可变和不可变编辑、分片与重试归并、历史差异、门禁退出码及 JSONL 协议。

## JUnit 报告 CLI

源码启动器需要 Node.js 24 和 MoonBit 工具链。`merge`、`verify` 支持 `--glob` 和标准输入 `-`，`merge` 的输出路径 `-` 表示 stdout：

```bash
node bin/junit-delta.mjs merge report-a.xml report-b.xml combined.xml
node bin/junit-delta.mjs verify combined.xml
node bin/junit-delta.mjs compare --baseline baseline.xml --candidate current.xml --format json
```

CLI 使用 `@junit.merge_shards` 的规则归并分片。无类名用例保留原套件路径，Node.js 的根级用例保留在根下；合并后会重算每层套件的数量、失败数和耗时。每个 glob 必须匹配输入，合并时会从 glob 匹配结果中排除输出文件。

`merge` / `verify` 退出码：`0` 成功，`1` 测试结果未通过或输入/运行错误，`2` 参数或启动器错误。`compare` / `jsonl` 退出码：`0` 通过，`1` 门禁违规，`2` 输入或运行错误。[命令与 JSONL 协议](docs/USAGE.md)。

## 许可

原创实现使用 [MIT](LICENSE)；junitparser 适配文件标注 [Apache-2.0](third_party/Apache-2.0.txt)，保留上游版权声明。XML 依赖和 MoonBit 标准库保留其自身许可。来源与修改说明见[第三方声明](third_party/NOTICE.md)。
