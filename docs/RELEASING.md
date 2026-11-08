# 构建与发布包

先运行 `bash scripts/verify.sh`。该脚本会生成并验证两类产物：

- `_build/publish/tc-adventureking-junit_delta-0.1.0.zip`：MoonBit 官方源码包。
- `_build/release/junit-delta-0.1.0-cli/`：包含编译 JavaScript、Node 启动器、示例、文档和许可证的便携目录。

源码包首次解压后需要解析并安装 `Milky2018/xml@0.6.1`。独立消费者验证使用源码包中的库和新 workspace，不依赖已经发布的本项目版本。本机 WSL 没有 POSIX unzip，因此本地验证使用独立于仓库的 Python zipfile 适配器执行同样的列目录、CRC 和解压操作；公共脚本要求系统 unzip，GitHub Actions 的 Ubuntu 环境提供它。

`scripts/package-cli.mjs` 从本次 JS 编译结果复制文件到固定的生成目录，运行真实启动器比较黄金示例，并生成逐文件 SHA-256 的 `MANIFEST.json`。它只清理该固定生成目录。便携 CLI 不含 `moon.mod`，因此不会触发源码编译。

可将便携目录压缩为 ZIP 后分发，同时附上归档 SHA-256。Node.js 24 由使用者安装，不包含在压缩包中。发布包不包含开发会话、私人 Python 差分工具或认证信息。

如果对外发布，应把真实仓库地址加入 `moon.mod`，保留本地 Git 的真实阶段记录，运行最新验证，再创建版本标签和 Release。当前项目只完成本地交付，没有执行公开发布、报名或提交。
