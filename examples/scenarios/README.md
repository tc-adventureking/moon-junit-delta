# 三个完整使用场景

这些是本项目编写的业务示例，XML 已包含在仓库和便携包中；不声称执行过相应业务的真实 CI。以下命令均在项目根目录运行。源码需 MoonBit 和 Node.js 24；便携包只需 Node.js 24。命中门禁的退出码 **1** 是预期业务结果。

## 1. 合并请求的回归门禁

**使用者与输入：** 维护 API 服务的开发者从 CI 保存主分支和合并请求的 JUnit 报告。示例中两次运行都只有一个失败，但失败从 refresh 转移到了 login。

**处理：** 按 `(classname, name)` 比较，不以总失败数判断是否通过。

```sh
node bin/junit-delta.mjs compare --baseline examples/scenarios/pr/baseline.xml --candidate examples/scenarios/pr/candidate.xml --format json
```

**输出与动作：** [完整期望报告](pr/expected.json) 包含 login 的 `new_failure`、refresh 的 `fixed` 和 logout 的 `unchanged`。退出码 1 阻断合并，开发者定位 HTTP 500，同时保留修复记录。基准的下载、报告保存和合并权限仍由现有 CI 负责。

## 2. 重试与历史波动审查

**使用者与输入：** 测试维护者收集较早运行、最近基准和当前重试报告。transport 曾失败后恢复，当前先通过后失败；cache 当前先失败后通过。同一 ID 的重复记录已明确是有顺序的尝试。

**处理：** 指定 `attempts`，用末次尝试确定当前状态；较早历史只提供 `known_flaky` 注记。

```sh
node bin/junit-delta.mjs compare --baseline examples/scenarios/retry/history.xml --baseline examples/scenarios/retry/baseline.xml --candidate examples/scenarios/retry/candidate.xml --duplicates attempts --format json
```

**输出与动作：** [完整期望报告](retry/expected.json) 中 transport 为 `new_failure`，即使 `known_flaky=true` 也返回退出码 1；cache 最终通过，附有 `flaky=true` 和两次尝试。维护者修复当前失败，并单独跟踪恢复的波动测试。若重复记录只是重复上传，不能使用 attempts；跳过与其他状态混合的重试会被拒绝。

## 3. 测试分片迁移后的完整性检查

**使用者与输入：** CI 平台维护者把单报告任务拆为两个分片。基准包含 parse、store、audit，当前 core 和 extra 分片都通过，但漏掉 audit，并新增 export。

**处理：** 同一次当前运行的两份报告一起归并，然后与迁移前基准逐项比较。

```sh
node bin/junit-delta.mjs compare --baseline examples/scenarios/shards/baseline.xml --candidate examples/scenarios/shards/core.xml --candidate examples/scenarios/shards/extra.xml --format json
```

**输出与动作：** [完整期望报告](shards/expected.json) 有一个 `removed`、一个 `added`、两个 `unchanged`，退出码 1 阻断漏测。维护者检查任务筛选和分片配置；若 audit 是有意删除，需人工确认后更新可信基准。仅观察时追加 `--fail-on none` 得到退出码 0；再次传入 core 分片会因重复 ID 返回 2。基准自身也有分片时，使用 [JSONL 的运行数组](../../docs/USAGE.md#历史与分片)。

## 可复验结果

完成 JS 构建后运行 `node scripts/scenarios.mjs`，检查三个完整黄金输出以及第三个场景的观察/重复上传两种分支，共 5 条命令。也可用 `--portable 便携目录` 检查实际便携启动器；黄金文件也受公开 JSON Schema 校验。
