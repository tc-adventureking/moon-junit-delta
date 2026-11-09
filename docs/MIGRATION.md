# 从 0.1 升级到 0.2

读取、归并和比较入口不变，JSON 比较协议仍为 `schema_version:1`。请更新依赖并重新编译。

- 报告、结果、诊断、身份路径和门禁集合改为 `ReadOnlyArray`。索引、长度和遍历照旧；需要可变副本时用 `items.iter().to_array()`，修改副本不会影响报告。
- `to_json`、`to_json_string`、`to_markdown`、`to_text` 现在可能抛出 `InputError`。渲染前检查 100,000,000 UTF-16 单元上限；可传 `max_units` 设置更低预算。JSON 按默认紧凑 `stringify()` 计量，额外缩进、转义或修改后需自行管理大小。超限报 `output_limit`，不会丢弃 JSON 条目；概要可用 `to_markdown(limit=0)`。
- 结果消息的属性与正文之间新增换行，超过 2,048 单元发出 `message_truncated` 诊断；诊断中的来源和身份预览有界，用例自身仍保留完整来源与身份。
- `merge_reports` 现在自身校验 50 分片和 100,000 唯一用例上限，嵌套套件重试按原文顺序处理。归并后顺序编号用于继续归并；原始编号由 `parse_document` 提供。
- 新增 Node 根 `testsuites` 直接包含 `testcase` 的兼容支持。每元素属性上限为 1,024，在成熟 XML 读取器之前线性检查；未减少原有用例、历史或输入大小上限。

最后一次结果决定分类，历史波动仍只作注记。原始 `is_flaky` / `is_rerun` 描述最后一条记录，累计 `flaky` / `attempts` 描述归并结果。完整规则见 [SPEC](SPEC.md)。
