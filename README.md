# junit-delta

**从两份 JUnit XML 找出本次 CI 新增了什么问题。** MoonBit 库与本地 CLI，输出 JSON、Markdown 或终端摘要，并给出可用于 CI 的退出码。

例如，同样是“2 个失败”，旧问题可能已经修复，同时引入了两个新问题。junit-delta 按测试身份逐项比较，区分新增失败、仍然失败、修复、移除和跳过变化；历史失败不会自动成为放行理由。

当前版本：`0.1.0`，发布候选。[GitHub 仓库](https://github.com/tc-adventureking/moon-junit-delta) 已建立；尚未发布到 Mooncakes，不能通过 `moon add` 下载本项目。最新交付状态见 [project.md](project.md)。

## 成熟生态对标

读取层直接对标 [junitparser 5.0.3](https://github.com/weiwei/junitparser)，复用 [Milky2018/xml 0.6.1](https://github.com/moonbit-community/xml-mbt) 解析 XML。固定版本的真实 Python 库参与差分验证，比较精确名称、类名、记录顺序、重复项和六项原始结果标记。

1,079 份差分输入中，1,053 份支持范围内的读取结果一致，26 份按明确规则拒绝，零未解释差异。仓库保留 207 份独立生成的回归向量，`node scripts/contract.mjs` 可复验。范围及差异见 [COMPATIBILITY](docs/COMPATIBILITY.md)；这不是 junitparser 的全量移植。

## 快速运行

源代码运行需要 MoonBit 和 Node.js 24；安装依赖需联网，日常比较不访问网络。

```sh
moon update
node bin/junit-delta.mjs compare --baseline examples/baseline.xml --candidate examples/candidate.xml --format md
```

示例应返回退出码 **1**：一个新增失败、一个新增且失败的用例、一个修复、一个移除；另有一次显式重试和一项耗时增加。完整结果见 [JSON](examples/expected.json) 与 [Markdown](examples/expected.md)。退出码 1 是门禁命中，不是程序故障。

便携 CLI 包包含编译好的 MoonBit JavaScript，仅需 Node.js 24：解压后运行相同命令，无需安装 MoonBit。源码启动器每次执行增量构建，避免误用旧产物。

```sh
# 只生成报告，不因变化拦截
node bin/junit-delta.mjs compare --baseline examples/baseline.xml --candidate examples/candidate.xml --fail-on none

# 加入按时间排列的历史；最后一个 baseline 是直接比较基准
node bin/junit-delta.mjs compare --baseline examples/history.xml --baseline examples/baseline.xml --candidate examples/candidate.xml --format json
```

## MoonBit API

三个完整业务示例见 [使用场景](examples/scenarios/README.md)：合并请求回归门禁、重试与历史波动审查、分片迁移完整性检查。每个场景都有输入、命令、完整输出、预期退出码和后续动作。

在本地 workspace 中将本模块与消费者并列，消费者依赖 `tc-adventureking/junit_delta@0.1.0`，包中导入别名 `@delta`。独立包验证脚本会从新生成的源码包执行这一流程。

```moonbit
let before = @delta.parse_report(
  "<testsuite><testcase classname='api' name='login'/></testsuite>",
)
let after = @delta.parse_report(
  "<testsuite><testcase classname='api' name='login'><failure/></testcase></testsuite>",
)
let result = @delta.compare([before], after)
assert_eq(result.entries[0].category, "new_failure")
assert_eq(result.exit_code(), 1)
```

调用方需处理 `InputError`。`parse_document` 保留原始重复记录，提供与 junitparser 对齐的读取行为；`parse_report` 增加身份和重复策略；`compare` 接收按时间排列的基准运行。JSON 请求接口适合脚本集成。

## 行为约定

- 身份为精确的 `(classname, name)`；缺少 classname 时使用完整套件路径。不会裁剪或折叠名称空白，也不会把文件路径拼入身份。
- 重复 ID 默认报错。显式设置 `--duplicates attempts` 才按文件、文档顺序作为重试，最后一次结果决定最终状态。
- Surefire 的成功重试仍是通过，另外标注 flaky；原始 failure/error 不会被 flaky 标记覆盖。
- 默认拦截 `new_failure,added_failing,removed,empty_report`。可额外拦截仍然失败、变为跳过、flaky 和耗时增加。
- 耗时用整数微秒；默认相对历史通过记录的下中位数增加超过 50%，且至少增加 200 ms 才标记。它是筛查候选项，不是统计显著性结论。
- 输出顺序固定，错误输入不转换为空的通过报告。退出码：0 通过，1 门禁命中，2 输入或用法错误。

## 验证与文档

```sh
npm ci --ignore-scripts    # 开发期输出 Schema 校验器
bash scripts/verify.sh     # 四目标、CLI、成熟库回归向量、打包和独立消费者
node scripts/scale.mjs    # 两份各 20,000 用例的可复现规模检查
```

公共检查需要 MoonBit、Node.js 24、Bash、unzip 和 C 编译器；动态参考与归档脚本另需 Python 3.10+。已验证版本与实际结果见 [TESTING](docs/TESTING.md)。[远端 CI](https://github.com/tc-adventureking/moon-junit-delta/actions/runs/42518258496) 已通过源码验证、两次相同归档构建，以及 Ubuntu/Windows 对同一便携包的各 24 项 CLI 和 5 项场景检查。

| 文档 | 内容 |
|---|---|
| [USAGE](docs/USAGE.md) | CLI、分片、历史、JSONL 与集成示例 |
| [SPEC](docs/SPEC.md) | 身份、结果矩阵、时长、门禁和资源边界 |
| [COMPATIBILITY](docs/COMPATIBILITY.md) | junitparser 直接对标及明确差异 |
| [PROVENANCE](docs/PROVENANCE.md) | 依赖、夹具、许可和 AI 协作说明 |
| [HACKATHON](docs/HACKATHON.md) | 选题依据、参赛介绍与演示流程 |
| [SUBMISSION](docs/SUBMISSION.md) | 按八项要求整理的简洁项目申报书 |
| [RELEASING](docs/RELEASING.md) | 源码包、便携 CLI 与发布步骤 |

项目代码为 MIT；复用组件及夹具保留其原许可，见 [第三方声明](third_party/NOTICE.md)。
