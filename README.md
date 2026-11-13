# junit-delta

MoonBit JUnit XML 创建、读取、编辑、写回与比较库。支持 base/xunit2 报告模型，以及 wasm、wasm-gc、JavaScript 和 native。

## 功能

- 创建和修改套件、用例、结果、properties、日志及自定义 XML 扩展。
- 可变共享视图、深拷贝、惰性统计、套件归并和 xUnit2 重试结果。
- 文件/字节/流回调、可替换解析器、普通及 pretty 写回。
- CLI `merge`、`verify`、`--glob`，保留原有比较、重试归并和 CI 门禁。

通用接口适配 junitparser 5.0.3；[对标与边界](docs/JUNIT.md)说明语言、解析器和资源差异。原有不可变 XML 与比较接口继续可用。

## 安装与使用

```sh
moon add tc-adventureking/junit_delta@0.4.0
```

应用包的 `moon.pkg`：

```moonbit
import { "tc-adventureking/junit_delta/junit", }
pkgtype(kind: "executable")
```

将以下内容保存为 `main.mbt`，运行 `moon run . --target js`：

```moonbit
fn main raise {
  let suite = @junit.TestSuite::new(name=Some("service"))
  suite.add_case(@junit.TestCase::new(name=Some("login"), time=Some(0.12)))
  suite.add_property("build", "12")
  let report = @junit.JUnitXml::new()
  report.add_suite(suite)
  report.update_statistics()
  println(report.element().write_xml(pretty=true))
}
```

[通用 API](junit/pkg.generated.mbti) · [处理与对标](docs/JUNIT.md) · [不可变 XML](docs/JUNIT_XML.md) · [比较和 CLI](docs/USAGE.md)

## 许可

原创实现使用 MIT，适配文件标注 Apache-2.0，见[第三方声明](third_party/NOTICE.md)。项目使用 AI 辅助设计与实现。
