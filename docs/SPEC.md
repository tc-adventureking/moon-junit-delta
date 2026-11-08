# 行为规格 v1

## 输入与身份

支持根 `testsuite` 或 `testsuites`；`testsuite` 可以嵌套，`testcase` 必须是套件的直接子元素。套件属性中的汇总 tests/failures/errors/time 不参与结果判断，实际 testcase 才是数据来源。

`TestId` 使用带类型标签的 JSON 数组序列化：

- 有 classname：`["class", classname, name]`。
- 缺少 classname：`["suite", [完整套件路径], name]`。未命名套件使用空字符串作为路径分量。

XML 属性正规化后不再 trim、折叠空白或 Unicode 正规化。file、line、timestamp 不参与身份；同类中同名测试应由生产者提供参数化名称。两个无名、同路径套件中的同名用例会触发重复，不能通过文件顺序补造身份。

`parse_document` 保留全部记录，按 junitparser 的套件遍历顺序返回；每条记录另存 `document_order`。`parse_report` 按原文顺序归并，`merge_reports` 按参数中报告顺序归并。重复默认报错；`Attempts` 取最后记录的 outcome、time、message、source，累加 attempts。只有曾混合通过与失败/错误，或任一记录带 flaky 标记，才标注 flaky；error 与 failure 的切换不算 flaky。skipped 与其他状态混合归并拒绝为 `retry_conflict`，避免后续跳过掩盖失败；重复 skipped 可以归并。套件缺少 name 与显式空 name 均使用空字符串路径分量。

## 结果与重试

原始 `is_*` 标记互相独立。比较用最终状态优先级：`error > failure > skipped > passed`。多个最终结果发出 `multiple_outcomes` 诊断。

| XML 结果 | 最终状态 | attempts | flaky |
|---|---|---|---|
| 无结果元素 | passed | 1 | false |
| failure / error / skipped | 对应状态 | 1 | false |
| 仅 flakyFailure / flakyError | passed | 1 + 临时结果数 | true |
| failure/error + rerun | failed/errored | 1 + 临时结果数 | false |
| failure/error + flaky（可兼有 rerun） | failed/errored | 1 + 临时结果数 | true，并给诊断 |
| skipped + retry；无 failure/error 的 rerun | 输入错误 | — | — |

只读取结果元素的 message 和文本，最多 2,048 UTF-16 代码单元；截断不会切开代理对。system-out/system-err 不进入消息；输出 Markdown 将控制语法与 HTML 转义。未知元素每个不同名称产生一条诊断；嵌在未知元素中的已知结果拒绝。

## 分类矩阵

P=passed，F=failed，E=errored，S=skipped，∅=缺失。flaky 是附加标记，不是第五种最终状态。

| 基准 \ 当前 | ∅ | P | F/E | S |
|---|---|---|---|---|
| ∅ | 不产生条目 | added | added_failing | added |
| P | removed | unchanged | new_failure | newly_skipped |
| F/E | removed | fixed | still_failing | newly_skipped |
| S | removed | unskipped | new_failure | unchanged |

比较对象为“最后一个基准运行的 ID 集合 ∪ 当前 ID 集合”。更早历史只辅助注记和时长参考，不重新加入最后基准已消失的用例。历史同时出现通过和失败/错误，或含显式 flaky，设置 `known_flaky`；它不改变类别或默认门禁。

## 时长

只接受非负十进制秒数，整数部分必需，小数点后至少一位；缺失或空值为 None。向下截断到微秒，范围 `0..9,000,000,000,000 µs`（9,000,000 秒）。JSON 使用精确可表示的数值，不使用字符串或 Option 数组。

历史中有有效时长的 passed 记录形成参考样本，取排序后的下中位数（偶数时取较小的中间值）。只有最后基准和当前均 passed 时检查：

```text
current * 100 > median * (100 + slowdown_pct)
且 current - median >= slowdown_floor_us
```

默认 50% 与 200,000 µs。百分比范围 0..1,000,000，时长上界保证 Int64 乘法不会溢出。零参考时长仍受绝对增量下限约束。历史成功重试也会进入通过记录样本；这是候选筛查，应结合 CI 环境再次测量。

## 门禁和输出

默认 `new_failure,added_failing,removed,empty_report`。可选 `still_failing,newly_skipped,flaky,slowdown`；空门禁集合只报告。`flaky` 检查当前显式或归并出的 flaky，不是历史 `known_flaky`。

JSON `schema_version=1`，完整 entries 按 `(category, ID JSON)` 字典序排列，counts 只包含出现的类别，violations 去重排序。诊断保持输入顺序。Markdown 默认展示前 50 条有变化或注记的记录，JSON 不截断用例条目。退出码 0=通过，1=门禁命中，2=输入/用法错误；JSONL 对每行输出结果并以最大退出码结束。

## 资源边界

每份 XML 最多 10,000,000 UTF-16 代码单元、深度 128、2,000,000 次读取事件、100,000 条 testcase。比较每个运行归并后不超过 100,000 个 ID；最多 50 个历史运行、每运行最多 50 个分片。CLI 单次输入文件/标准输入最多 20,000,000 字节，compare 合计 XML 最多 20,000,000 代码单元；JSONL 整批读取，有同样的 20,000,000 代码单元上限，不是无限流式协议。

重复归并后单个 ID 的 attempts 不超过 1,000,000。XML、JSON 重复属性/键拒绝；DTD、命名空间化的 JUnit 元素和非 UTF-8 声明不受支持。根节点可携带 Surefire 的 `xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"` 和 `xsi:noNamespaceSchemaLocation`，二者只作元数据，schema URL 从不读取；其他命名空间属性拒绝。CLI 不执行报告中的代码，不读取实体地址，也不访问网络。
