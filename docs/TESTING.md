# 验证记录

## 可复现检查

```sh
npm ci --ignore-scripts
bash scripts/verify.sh
node scripts/scale.mjs
node scripts/boundaries.mjs
```

验证工具链：MoonBit `moon 0.1.20261104`、编译器 `0.10.20+65efd5b93`、Node.js 24。公共脚本使用 PATH 中的工具。

## 当前结果

| 检查 | 实际执行范围 | 结果 |
|---|---|---|
| MoonBit 核心 | 47 个测试块，在 wasm、wasm-gc、js、native 各运行一次 | 188 次执行通过，零告警 |
| 成熟库动态差分 | 实际 junitparser 5.0.3；1,053 份共同支持输入与 26 份明确拒绝输入 | 1,079 份零未解释差异 |
| 独立比较与畸形输入 | 固定种子 500 组历史/状态/时长比较与 1,004 份 ElementTree 确认的非法 XML | 1,504 项通过 |
| 真实生产端 | 两代 pytest（两种 XML 家族、参数化、分片）、Surefire/JUnit（flaky、重跑）、Node24 | 24 份实际报告生成与 API 检查通过 |
| CLI 端到端 | 真正的 Node 进程、文件/stdin、UTF-8/BOM、错误码、JSONL、历史与分片 | 24 项通过 |
| 公共成熟库回归向量 | 207 份保存的独立期望，Node CLI 实际解析 | 181 匹配 + 26 拒绝，零差异 |
| 源码包与消费者 | 官方 ZIP 在仓库外解压；消费者每目标 2 个公共 API 测试 | 四目标合计 8 次执行通过 |
| 便携 CLI | 不含 MoonBit manifest 的目录，由真实启动器读取黄金示例 | 退出码与完整 JSON 一致 |
| 三个完整场景 | 源码及 Windows 便携包；回归、重试、迁移加两种分支 | 各 5 条命令通过，4 份黄金报告符合 Schema |
| 重复构建 | 同源提交及工具链独立构建两次 | 三个 ZIP 与两个摘要文件逐字节相同 |
| 输出协议 Schema | Ajv 8.20.0 的严格 Draft 2020-12 校验 | 黄金报告通过，8 个非法报告反例全部拒绝 |

成熟库参考 wheel 的 SHA-256 与投影字段见 [COMPATIBILITY](COMPATIBILITY.md)。完整生成语料固定种子为 `20261109`，公开工具可在隔离环境重新执行真实 Python 库：

```sh
python3 -m pip download --no-deps --only-binary=:all: --require-hashes -r scripts/reference/requirements.txt -d _build/reference
python3 -m venv --without-pip _build/reference/venv
_build/reference/venv/bin/python -I scripts/reference/junitparser_diff.py --wheel _build/reference/junitparser-5.0.3-py3-none-any.whl --oracle-output _build/reference/oracle.json
cmp fixtures/junitparser-contract.json _build/reference/oracle.json
```

Windows 将 venv 解释器路径换为 `_build/reference/venv/Scripts/python.exe`，用文件摘要或二进制比较代替 `cmp`。公共 CI 同时执行全部动态差分、207 份保存的期望回放及再生文件逐字节一致性检查。程序默认不改期望文件，只有显式 `--write-oracle` 才刷新受版本控制的向量。

47 个测试块包含 35 组状态转换以及更多循环内断言，不把断言数量冒称为独立测试数。真实生产端生成脚本为 `scripts/producers.py`，配置固定为 legacy / current。GitLab 样例仍为注明来源的作者构造输入，没有声称执行 GitLab 服务。独立消费者另外验证公开只读集合的非法修改被编译器拒绝。

## 规模检查

`node scripts/scale.mjs` 创建两份各 100,000 个用例的报告，只把一个通过改为失败。它检查 1 个 new_failure、99,999 个 unchanged、三次完整 JSON 的同一 SHA-256，并记录包含启动/I/O/JSON 输出的墙钟耗时及子进程峰值 RSS。Windows x64、Node 24.22.1 本地三次耗时 2.915 / 3.010 / 2.850 秒，峰值 RSS 972,916–974,552 KiB（约 950–952 MiB）。

`node scripts/boundaries.mjs` 验证 50/51 历史与分片、深度 128/129、XML 10M 单元、文件 20M 字节、事件 2M 的通过/拒绝边界，并检查延迟 stdin 管道、属性预检及 JSONL 整批输出上限。50,000 用例共享 200,000 字符套件名，概要比较本地耗时 0.527 秒；请求完整超大 JSON 明确拒绝，未降低比较容量。JSONL 压力输入保留 952,377 条完整结果（末条为限额错误），输出 99,999,623 单元。

规模脚本只说明该合成输入下的结果，不作为跨机器吞吐保证或相对其他库的速度结论。

## 打包与 CI

`scripts/verify-package.sh` 只使用本次 `moon package` 返回的源码 ZIP，检查归档路径及必要文件，再在仓库以外解压并建立新的消费者 workspace。消费者通过公开 API 测试比较、门禁、原始记录和重试归并；不会因同仓库的私有可见性而误通过。

GitHub Actions 配置安装官方 stable 工具链并运行公共验证脚本。[公开 CI](https://github.com/tc-adventureking/moon-junit-delta/actions) 验证：源码四目标与独立消费者、固定成熟库动态差分、两次归档字节一致性，以及 Ubuntu/Windows 对同一解压便携包各 24 项 CLI 和 5 项场景检查；另有两组真实生产端作业，仅上传不含机器路径的验证摘要。便携验证作业没有安装 MoonBit。

工具链升级后应重新验证。

真实生产端复现需 Python 3.13、Java 21+ 和 Maven，先在隔离环境安装对应 pytest 版本，再运行 `python scripts/producers.py --profile legacy` 或 `--profile current`。原始 XML 和日志可能含机器路径，只保留在 `_build/`，不作为公开夹具或归档。
