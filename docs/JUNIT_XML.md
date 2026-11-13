# JUnit XML 文档处理

`JUnitDocument` 是保留完整内容的报告树；旧 `Report` 是用于比较的精简数据。XML 解析、转义、命名空间和写入校验复用 Milky2018/xml 0.6.1，库不绑定文件系统，支持 wasm、wasm-gc、JavaScript、native。

## 创建、编辑与写回

[完整示例](../examples/edit/main.mbt) 可从源码运行：

```sh
moon run examples/edit --target js
```

输出是一份带 `build` 属性、一个 `login` 用例和汇总统计的 JUnit XML。应用也可以用 `JUnitDocument::from_xml(text)` 读取原报告，再执行同样的编辑。

| 操作 | API |
|---|---|
| 创建套件、用例、结果 | `JUnitElement::suite / testcase / result` |
| 自定义节点、混合内容 | `JUnitElement::new`、`JUnitNode` |
| 查找直接子元素、属性 | `elements(name?)`、`attribute(name)` |
| 修改或删除属性 | `with_attribute`、`without_attribute` |
| 添加或批量替换子节点 | `append`、`with_content` |
| 添加属性项、替换输出和最终结果 | `add_property`、`with_output`、`with_results` |
| 修改或删除用例、顶层套件 | `map_cases`、`map_suites`；回调返回 `None` 表示删除 |
| 更新统计 | `with_statistics(overwrite_time?)` |
| 合并完整文档 | `merge_documents` |
| 序列化、保存到宿主 | `to_xml(max_units?)`、`write_to(sink, max_units?)` |
| 转为比较数据 | `to_report(source?)` |

值不可变，修改返回新值；传入的数组会复制。批量操作使用 `with_content` 或 `map_cases`，避免循环 `append` 的重复数组复制。构造和通用编辑允许中间状态，`to_xml` 会校验完整 XML；`write_to` 先完成全部序列化和校验，再调用一次宿主回调。回调可保存到文件或流，I/O 错误向外传播，文件原子替换由宿主处理。

`with_results` 只替换直接 `failure/error/skipped`，保留重试及其他节点；要同时删除重试，应显式过滤 `content`。`add_property` 追加属性项，保留重复名称。`with_output` 替换同类直接输出节点为一个文本节点。

## 保留范围与扩展

完整保留解析后的属性值、未知元素、properties、system-out/system-err、多重结果、重试节点、正文、混合内容、CDATA、注释与处理指令。完整树没有比较数据的 2,048 字符消息截断。自定义属性或 `<vendor:metadata>` 直接通过通用节点 API 编辑，无需新增 XML 解析器。

支持 XML 1.0、UTF-8、根 `testsuite/testsuites`。JUnit 核心元素必须无命名空间；扩展可以使用已声明的前缀或自己的默认命名空间。保留命名空间声明，但不自动重新绑定移动的子树：从另一位置取出的子树必须显式携带所需声明，未绑定或重复展开名会报错。`to_report` 仍使用旧比较 profile，命名空间扩展的文档能写回，不代表它一定能转为比较数据。

这是内容往返，不是字节级往返。引号、实体写法、空标签和属性顺序可能规范化；XML 解析规则规范化原始换行。保留已有 XML 声明，只接受 UTF-8 声明，宿主应以 UTF-8 保存。不生成美化缩进，以免改变混合文本。拒绝 DTD，不访问 schema URL 或外部实体。

## 合并与统计

`merge_documents` 按输入顺序拼接独立套件，保留重复用例；不会按套件名称合并，也不解释重试。`merge_reports` 则归并比较用的数据并应用重复 ID 策略。

多输入合并时，`testsuites` 的非派生根属性必须完全一致，包括命名空间声明；任一缺失或冲突都会报 `merge_conflict`。文档外的内容和 XML 声明也必须一致，避免静默丢弃或移动处理指令。裸 `testsuite` 保留自己的全部属性。调用者可用 `with_root` 统一元数据，或显式用 `JUnitDocument::new(root=old.root)` 放弃文档外内容后合并。空列表产生空 `testsuites`，单输入原样返回。

多输入的新根不继承 `tests/failures/errors/skipped/time/disabled/assertions`，以免保留错误汇总；各输入套件的统计保留。需要新统计时显式调用 `with_statistics`：

- 遍历结构性套件及用例，包括嵌套 `testsuite` 和根 `testsuites` 下的直接用例；扩展子树中的同名节点不参与。
- 每个用例只计一个结果，优先级 `error > failure > skipped > passed`；重试标签本身不增加用例数。
- 重算 `tests/failures/errors/skipped`，不推断 `disabled/assertions`。
- 默认保留已有套件时长；`overwrite_time=true` 用已知用例时长重算。部分时长缺失时只汇总已知时长，全部缺失则省略 `time`。
- 文档统计采用非负十进制秒，超过六位小数向下截断到整数微秒；按完整 Int64 范围检查数值和总和溢出，写出六位小数。旧比较接口保持原有较低时长上限。

编辑与 `to_xml` 不自动更新统计；此行为保留报告中的实际运行墙钟时间。`with_statistics` 会校验全部结构性时长及中间总和，即使外层套件已有时长也不跳过非法值或溢出。

## 原始文档接口的行为边界

本页只描述根包中从 0.3.0 保留的不可变 `JUnitDocument` API。0.4.0 新增的可变 `junit` 子包提供与 junitparser 5.0.3 对应的统计、合并、解析回调和 pretty 写回，详见[通用接口与对标](JUNIT.md)。以下差异只适用于旧接口，不代表整个库的功能范围。

| 能力 | junitparser 5.0.3 | 根包不可变 API |
|---|---|---|
| 读取、创建、修改报告 | 支持 | 完整树及 JUnit 便利构造器 |
| XML 写回 | 文件或输出对象 | XML 字符串、宿主写入回调 |
| properties、输出、多个结果、xunit2 重试 | 类型与子类接口 | 便利方法及完整节点保留 |
| 自定义属性与元素 | Attr、Element 扩展 | 属性与混合内容节点 API |
| 文档合并 | 可按套件相等规则组合 | 保留独立套件，元数据冲突拒绝 |
| 统计 | 按结果元素计数，浮点时长取三位小数 | 每用例单桶，整数微秒，默认保留套件墙钟时间 |
| 重复 ID、历史回归、门禁 | 非其核心比较能力 | 保留原有 `Report/compare` 层 |
| 可替换 XML 引擎 | 支持 parse_func | 固定复用 Milky2018/xml |
| 文件 I/O 与美化写出 | 文件接口、`pretty` 输出选项 | 宿主回调保存；无 `pretty` 格式化 |
| 命令行操作 | `merge`、`verify` | 文档操作通过库 API 提供；全库 CLI 见[使用指南](USAGE.md) |

可复现的行为差异：一个用例包含两个 `failure` 时，Python 的失败统计为 2，本库为 1；两份具有相同套件身份的报告，Python 可归并为一个套件，本库保留两个；套件声明 `time=9`、用例时长合计 `0.3` 时，Python 更新统计后为 `0.3`，本库默认保留 `9`，仅显式覆盖时重算。

生态增量是 MoonBit 原生的可编辑 JUnit 报告模型及其与既有比较功能的衔接；底层 XML 能力直接复用已有库。不声称覆盖全部 xUnit 方言、XPath、XSD 校验或任意编码转换。

## 限额

单文档输入及写回最多 10,000,000 UTF-16 单元，深度 128、2,000,000 事件、100,000 个名为 `testcase` 的元素，每元素 1,024 个属性。`max_units` 可调低写回上限，预算在分配最终输出前计算。这是内存文档树和完整字符串写回，不是恒定内存的流式处理；逻辑上限不是进程 RSS 上界。
