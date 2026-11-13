# 通用 JUnit 报告接口

导入 `tc-adventureking/junit_delta/junit`。本包提供可变报告处理；根包中的 `JUnitDocument` 和 `Report` 保留原有不可变编辑与比较规则。两者不是相同统计/归并策略的别名。

## 创建、读取与编辑

`JUnitXml`、`TestSuite`、`TestCase` 是 XML 节点的共享视图。修改已插入的用例或迭代返回的视图会修改同一报告；`clone()` 深拷贝。追加已有节点会将它移到新父节点。

```moonbit
let report = @junit.JUnitXml::from_string("<testsuite><testcase name=\"a\"/></testsuite>")
let suite = report.suites().next().unwrap()
let case = suite.cases().next().unwrap()
case.set_results([@junit.TestResult::new(Failure, message=Some("assertion"))])
case.set_system_out(Some("captured output"))
suite.add_property("build", "12")
report.update_statistics()
let xml = report.element().write_xml()
```

`set_results` 接收最终结果；`add_interim_result` 追加结果节点。以 `flavor=XUnit2` 创建或解析时，`interim_results`、`rerun_failures`、`flaky_errors` 等查询包含 xUnit2 重试记录，`stack_trace` 等访问器读写其子节点。`group`、`id`、`package_`、`file`、`log`、`url`、`version` 有对应方法。

`Element` 支持任意属性、子元素、混合文本、注释和处理指令，名称采用 `{namespace}local` 形式。`element()` 取得共享节点；`from_element` 将节点包装成所需视图。`read_attribute` / `write_attribute` 接受自定义类型转换函数。CDATA 在通用模型中合并为文本；需要保留 CDATA 节点时使用原始 `JUnitDocument` API。

## 文件、字节、流与解析扩展

核心库通过回调与宿主集成，不直接绑定文件系统或网络。

| 入口 | 行为 |
|---|---|
| `from_string(text)` | Unicode XML；含 encoding 声明时拒绝，改用字节或已解码入口 |
| `from_bytes(bytes, decode?)` | 内置 UTF-8/UTF-16；其他编码提供解码回调 |
| `from_decoded(text)` | 宿主已按原编码解码的 XML，允许 encoding 声明 |
| `from_file(path, read, parse?)` | 路径/URL由读取回调处理，记住路径供默认写回 |
| `from_reader(read, parse?)` | 从字节源读取，不记住文件路径 |
| `from_file_with(path, parse)` | 完全替换读取和解析，返回 `Element`，可用于其他报告格式转换 |
| `write(writer, path?, pretty?)` | 写出 UTF-8 字节；缺省路径使用当前视图记住的原路径 |
| `write_to(sink, pretty?)` | 写入字节接收器；宿主错误原样传播 |
| `element().write_xml(pretty?)` | 获取含 UTF-8 声明的完整字符串 |

`pretty=true` 按 minidom 的规则插入缩进，混合内容中的空白可能变化。此接口构造完整输出，不是恒定内存的流式处理。`filepath` 属于视图；重新包装节点不会继承旧视图的文件路径。

## 与 junitparser 5.0.3 的对应关系

参考环境为 CPython 3.13.2、junitparser 5.0.3、lxml 6.1.1。以下是功能与行为映射，不是 Python 运行时的替代品。

| Python 能力 | MoonBit 对应 |
|---|---|
| Element、Attr、IntAttr、FloatAttr、自定义描述符 | `Element` 属性/子节点操作与类型转换；报告视图的自定义数值 getter 同样支持惰性统计 |
| Result / FinalResult / Failure / Error / Skipped | `TestResult` 与 `ResultKind`，正文及 message/type 访问器 |
| SystemOut / SystemErr / StackTrace | `output_element(OutputKind)` 与文本访问器 |
| Property / Properties | 同名类型，添加、删除、排序比较与稳定的重复键语义 |
| TestCase / TestSuite / JUnitXml | 同名共享视图、创建、编辑、迭代、比较、克隆、合并与写回 |
| xunit2 | `Flavor::XUnit2`、全部附加字段、四种 interim result 及相关查询 |
| `+` / `+=` | `merged`、`merged_suite`、`merge_inplace`、`merge_suite_inplace`、`extend_suites`；套件结果用 `SuiteMerge` 区分套件和文档 |
| fromfile / 自定义 parse_func / write | 文件、流、解码和解析回调；默认路径写回及 pretty |
| merge / verify / glob | 同名 CLI 子命令与宿主 glob；比较、JSONL 命令继续保留 |

关键语义沿用参考版本：套件先遍历直接用例，再递归嵌套套件；每个最终结果分别计数；缺失的统计 getter 会更新 XML，空字符串字段不触发更新；时间按 Python 浮点顺序累加并舍入。套件等价按 name/hostname/timestamp/properties 判断，重复属性稳定排序。根级合并会合并等价套件；根 `+` 不继承输入根的元数据。xUnit2 根的 skipped 赋值保存在视图中，不写 XML，`clear_skipped()` 可清除它。

## 明确的适配差异

- Python 的描述符、继承、运算符和异常类型以 MoonBit 方法、枚举和 `JUnitError` 表达。强类型接口不模拟所有 Python 动态类型强制转换；`set_time_int` 保留整数赋值的字符串形式。
- 用例相等比较使用 Python ASCII 序列化的内容。`comparison_key()` 提供此内容，不复现 Python 随进程变化的哈希数值及偶然碰撞。
- 默认字节解码器内置 UTF-8/UTF-16，其他编码由解码或解析回调提供；CLI 使用 Node 宿主编码能力。UTF-16 的 BOM/字节序特征优先于声明，与参考解析器一致；其余字节遇到不支持的声明会要求显式解码，不会静默按 UTF-8 解读。
- 使用 Milky2018/xml 的解析器，内部实体和 DTD 默认属性可用，不加载外部资源。DTD 保留源排版，命名空间前缀在部分新建/迁移场景可与 lxml 不同；不承诺任意 XML 的逐字节一致。迁移时保留未类型化 QName 字符串使用的前缀声明，不改写其属性值。有效的 BOM Unicode 字符串会被接受，包括参考 Windows lxml 对部分补充字符拒绝的输入。
- 解析上限为 1,000 万 UTF-16 单元、200 万事件、128 层元素、每元素 1,024 个属性；字节输入上限为 2,000 万字节。统计最多处理 100 万用例，迭代合并最多处理 100 万套件。超过限额抛错，失败前已完成的修改不回滚。
- 自加使用有界快照，避免上游部分输入不终止。共享节点池在最后一个句柄释放时回收；长期保留句柄会保留池中的已删除节点，可通过深拷贝形成独立池。

旧版根包有自己的有意差异：不可变 `JUnitDocument` 保留原始节点形式，比较 `Report` 采用整数微秒、最终结果归一和历史身份规则。不要将它们的归并结果当作 `junit` 模型的替代品。
