# 新·留香音乐盒（LxMusic-NG）

LxMusic-NG 是旧版 Auto.js“楚留香音乐盒”的 Dart / Flutter 重写。项目把乐谱解析、转换、目标规划和后端动作编译沉到共享 core，并由 CLI 与 Flutter App 复用。

当前已经可以完成“导入乐谱 → 分析与转换 → 生成语义计划 / MIDI / executable plan → App 内瀑布流与合成音预览”，并支持 Android 键位校准、无障碍自动演奏和连接真实曲库的游戏内悬浮播放器。点击演奏、可视化跟弹与 MIDI 串流模式仍在规划中。

## Workspace

| 路径 | 作用 |
|---|---|
| `packages/lxmusic_core` | Domain model、5 类输入解析、18 个 transform、分析、planner、backend compiler、YAML repository |
| `packages/lxmusic_assets` | 内嵌的 game profile、layout 与 sample calibration |
| `apps/lxmusic_cli` | `analyze` / `convert` 及 profile、format、pass 检查命令 |
| `apps/lxmusic_app` | 曲库、目标与逐曲配置、布局预览、瀑布流、本地合成音预览、键位校准与游戏内悬浮播放器 |
| `examples` | 各输入格式和 pipeline 示例；其中 pipeline 示例仍在迁移 TODO 中 |
| `tools` / `scripts` | 资产生成、旧 profile 迁移、验证与 CI 脚本 |

## 处理链路

```text
源文件
  -> ParserRegistry / ScoreParser
  -> Score
  -> TransformPipeline
  -> ScoreAnalysis / PerformancePlanner
  -> SemanticPlan
  -> BackendCompiler
  -> ExecutablePlan
  -> Android Accessibility PlaybackExecutor / PlayerOverlay
```

## 验证

仓库级检查：

```bash
bash scripts/ci/check.sh
```

包含资产重新生成和 CLI profile 校验的完整检查：

```bash
bash tools/verify.sh
```

如果本机设置了 HTTP 代理且 Flutter 测试无法连接 `flutter_tester` 的 localhost WebSocket，可为测试进程设置 `NO_PROXY=localhost,127.0.0.1`。
