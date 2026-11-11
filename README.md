# junit-delta

纯 MoonBit JUnit XML 创建、读取、编辑、写回与比较库。复用 Milky2018/xml，支持 wasm、wasm-gc、JavaScript 和 native。

## 功能

- **文档处理**：创建与编辑套件、用例、结果、properties 和输出，保存为 JUnit XML。
- **扩展保留**：完整消息、自定义属性和元素、混合文本、CDATA、注释及命名空间声明。
- **合并与统计**：拼接独立报告，显式处理元数据冲突，更新用例统计和微秒时长。
- **差异比较**：保留原有分片、重试、历史回归和 CI 门禁能力。

`merge_documents` 合并完整 XML；`merge_reports` 归并比较数据。参考 junitparser 5.0.3，具体对应能力及差异见[对标说明](docs/JUNIT_XML.md#与-junitparser-503-对标)。

## 安装与使用

```sh
moon add tc-adventureking/junit_delta@0.3.0
```

应用包使用以下 `moon.pkg`，将示例保存为 `main.mbt`，运行 `moon run . --target js`：

```moonbit
import { "tc-adventureking/junit_delta" @junit, }
pkgtype(kind: "executable")
```

```moonbit
fn main raise {
  let case = @junit.JUnitElement::testcase("login", classname=Some("api"))
  let suite = @junit.JUnitElement::suite("service")
    .add_property("build", "12")
    .append(@junit.JUnitNode::Element(case))
  let report = @junit.JUnitDocument::new(root=suite)
  let edited = report.map_cases(c => Some(c.with_attribute("file", "login.mbt")))
  edited.with_statistics().write_to(xml => println(xml))
}
```

输出带有 `build` 属性、`login` 用例及统计的 XML。已有报告可用 `JUnitDocument::from_xml(text)` 读取；写文件时向 `write_to` 传入宿主保存函数。编辑返回新值，统计需显式更新，输入和输出错误由调用者处理。

[完整 API](pkg.generated.mbti) · [文档处理与对标](docs/JUNIT_XML.md) · [比较和 CLI](docs/USAGE.md)

## 许可

项目使用 [MIT](LICENSE)，来源与依赖许可见[第三方声明](third_party/NOTICE.md)。本项目使用 AI 辅助设计与实现。
