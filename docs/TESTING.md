# 验证记录

## 可复现检查

```sh
bash scripts/verify.sh
node scripts/scale.mjs
```

环境：Windows 11 x64 上的 Node.js 24.22.1；WSL Ubuntu 中的 MoonBit `moon 0.10.17`、编译器 `0.1.20261023`，native 使用 Zig C 工具链。公共脚本使用 PATH 中的 MoonBit、Node、C 编译器和 unzip，不包含本机绝对路径。

## 当前结果

| 检查 | 实际执行范围 | 结果 |
|---|---|---|
| MoonBit 核心 | 26 个测试块，在 wasm、wasm-gc、js、native 各运行一次 | 104 次执行通过，零告警 |
| 比较独立差分 | 700 组随机/边界比较，独立 Python 标准库与 Decimal 参考；另有四类夹具 | 零差异 |
| 成熟库动态差分 | 实际 junitparser 5.0.3；1,051 份共同支持输入与 22 份明确拒绝输入 | 1,073 份零未解释差异 |
| CLI 端到端 | 真正的 Node 进程、文件/stdin、UTF-8/BOM、错误码、JSONL、历史与分片 | 24 项通过 |
| 公共成熟库回归向量 | 201 份保存的独立期望，Node CLI 实际解析 | 179 匹配 + 22 拒绝，零差异 |
| 源码包与消费者 | 官方 ZIP 在仓库外解压；消费者每目标 2 个公共 API 测试 | 四目标合计 8 次执行通过 |
| 便携 CLI | 不含 MoonBit manifest 的目录，由真实启动器读取黄金示例 | 退出码与完整 JSON 一致 |

成熟库参考 wheel 的 SHA-256 与投影字段见 [COMPATIBILITY](COMPATIBILITY.md)。完整生成语料固定种子为 `20261109`，公开工具可在隔离环境重新执行真实 Python 库：

```sh
python3 -m pip download --no-deps --only-binary=:all: --require-hashes -r scripts/reference/requirements.txt -d _build/reference
python3 -m venv --without-pip _build/reference/venv
_build/reference/venv/bin/python -I scripts/reference/junitparser_diff.py --wheel _build/reference/junitparser-5.0.3-py3-none-any.whl --oracle-output _build/reference/oracle.json
cmp fixtures/junitparser-contract.json _build/reference/oracle.json
```

Windows 将 venv 解释器路径换为 `_build/reference/venv/Scripts/python.exe`，用文件摘要或二进制比较代替 `cmp`。公共 CI 同时执行全部动态差分、201 份保存的期望回放及再生文件逐字节一致性检查。程序默认不改期望文件，只有显式 `--write-oracle` 才刷新受版本控制的向量。

26 个测试块包含 35 组状态转换以及更多循环内断言，不把断言数量冒称为独立测试数。真实 Node 夹具与上游 pytest 夹具、有意构造的 Surefire/GitLab/pytest 示例分别说明来源；没有声称执行 Maven 或 GitLab 服务。

## 规模检查

`node scripts/scale.mjs` 创建两份各 20,000 个用例的报告，只把一个通过改为失败。它检查 1 个 new_failure、19,999 个 unchanged 和三次完整 JSON 的同一 SHA-256；打印主机、CPU、Node 版本与包含进程启动/I/O/JSON 输出的墙钟耗时。

本机 Node.js 24.22.1 / Windows x64 / Intel Core i9-14900HX 的三次结果为 1.204、1.111、1.078 秒；完整输出 SHA-256 均为 `01cf73878d173cf99f45045b01f35576ddd60fef25f7e015712942bf6d48af37`。该数据仅描述这个合成输入与当前环境，不是跨机器吞吐保证、内存上界或相对其他库的速度优势。资源拒绝边界另见 [SPEC](SPEC.md)。

## 打包与 CI

`scripts/verify-package.sh` 只使用本次 `moon package` 返回的源码 ZIP，检查归档路径及必要文件，再在仓库以外解压并建立新的消费者 workspace。消费者通过公开 API 测试比较、门禁、原始记录和重试归并；不会因同仓库的私有可见性而误通过。

GitHub Actions 配置安装官方 stable 工具链并运行公共验证脚本。远端结果以实际 workflow run 为准；工具链升级后应重新验证。Claude 的最终审查与本地运行是不同证据，不将“审查通过”当作执行测试的证明。
