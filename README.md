# junit-delta

MoonBit 实现的 JUnit XML 报告比较库与 CLI：识别新增失败、修复、消失用例、显式重试和耗时候选回归。项目正在实现，当前状态见 [project.md](project.md)。

核心复用 `Milky2018/xml@0.6.1`；以明确的测试身份与门禁语义为基础，不把历史 flaky 当作自动放行理由。
