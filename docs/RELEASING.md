# 构建与发布包

在完整 Git 仓库中安装 MoonBit stable、Node.js 24、Python 3.10+（仅打包/差分工具）、Bash、unzip 和 C 编译器。运行 `npm ci --ignore-scripts` 及 `bash scripts/verify.sh`，确认所有修改提交后：

```sh
python3 scripts/release.py --output _build/archives
python3 scripts/verify-release.py _build/archives --extract-cli _build/extracted-release
node _build/extracted-release/junit-delta-0.2.0-cli/bin/junit-delta.mjs --version
```

输出包含三个 ZIP：

- `junit-delta-0.2.0-source.zip`：从 Git HEAD 导出的完整开发源码，含 CI、开发工具及独立消费者。
- `tc-adventureking-junit_delta-0.2.0.zip`：`moon package` 产生的模块文件，重新固定 ZIP 元数据；面向 MoonBit 库集成；仅包含库源码、测试、公开 API、必要文档、Schema 和许可证。CLI、CI、开发工具、原始夹具和示例仅保留在完整源码仓库。
- `junit-delta-0.2.0-cli.zip`：编译好的 MoonBit JavaScript、Node 启动器、三个场景、文档及许可证。运行只需 Node.js 24，不需要 Python、MoonBit 或 Ajv。

`RELEASE.json` 记录源提交、工具版本、每个归档的字节数和 SHA-256；`SHA256SUMS` 方便外部核对。便携目录内的 `MANIFEST.json` 列出每个文件的摘要。验证脚本核对归档、CRC、路径、逐文件摘要，并只解压到一个尚不存在的新目录。摘要核对用于检测传输或构建差异，本身不是来源签名。

发布脚本拒绝未提交修改，从当前源重新构建 JS 和模块包；模块归档只允许 Git 已跟踪的文件，验证脚本拒绝 Python 优化模式以保留全部检查。ZIP 条目排序，时间固定为 1980-01-01，权限固定为普通文件，并使用 ZIP_STORED 避免压缩库版本引入字节差异。相同源提交和工具链可重复构建，两个输出目录中的三个 ZIP 和两个摘要文件应逐字节相同；不同编译器生成的 JS 不承诺字节相同。

`scripts/package-cli.mjs` 只清理固定的 `_build/release/junit-delta-0.2.0-cli` 生成目录；公开归档脚本不删除源码或任意目标目录。便携包不含 `moon.mod`，因此实际启动器不会调用 MoonBit。Windows 用 `python` 替代 `python3`；构建和库测试仍需上述开发工具。

官方模块包首次使用需要安装 `Milky2018/xml@0.6.1`。`scripts/verify-package.sh` 在仓库外解压新包，建立新消费者 workspace，四目标测试公开 API。公共脚本和 Ubuntu CI 使用系统 unzip。

Mooncakes 使用 `.moonignore` 中的文件白名单。发布前检查 `moon package` 的实际 ZIP 内容并运行 `moon publish --dry-run`，通过后执行 `moon publish`。发布检查会在新目录解包并安装依赖，因此不使用禁止安装依赖的 `--frozen`。发布后在仓库外的新项目运行 `moon add tc-adventureking/junit_delta@0.2.0`，验证注册表下载和四目标测试。安装 Mooncakes 库包无需下载完整 Git 仓库；CLI 的构建与使用仍需完整源码或便携包。

版本以 `moon.mod` 为准，`scripts/version.py` 检查编译常量，归档与便携校验从同一版本读取。公开发布将经审查的三个 ZIP、`RELEASE.json` 和 `SHA256SUMS` 附在对应 Git 标签的 Release；构建工具只准备本地产物，不自动发布。
