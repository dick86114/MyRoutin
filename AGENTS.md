# AGENTS.md

MyToken 是一个 macOS 菜单栏用量监控工具，用于查看多个大模型供应商的用量、余额、剩余额度和重置时间。

## Setup commands

- Install deps: `brew install xcodegen`
- Generate project: `xcodegen generate`
- Build: `scripts/build-dmg.sh`
- Test: `scripts/test.sh`
- Lint: 暂未配置 SwiftLint 或其他 lint 工具

## Project layout

- `RoutinUsage/` — macOS 应用 Swift 源码，按 App、Models、Views、Providers 等领域组织
- `RoutinUsageTests/` — 单元测试
- `scripts/` — 测试、DMG 构建和 Xcode 版本校验脚本
- `docs/` — 首次运行说明及品牌资源
- `project.yml` — XcodeGen 工程配置
- `.github/workflows/` — CI 测试、打包和发布工作流

## Code style

- 使用 Swift 5 与 SwiftUI/AppKit，部署目标为 macOS 14.0。
- 遵循现有文件的命名和按功能分层方式；保持 UI、服务、模型和持久化职责分离。
- 工程由 `project.yml` 生成；修改工程结构时同步更新该文件，再运行 `xcodegen generate`。
- 不要在日志、测试夹具或提交内容中暴露 API Key、Cookie、Token 等凭证材料。

## Testing instructions

- 单元测试：`scripts/test.sh`；脚本会生成工程、禁用签名并在隔离用户目录运行 macOS 测试。
- 直接测试：`xcodegen generate && xcodebuild test -project RoutinUsage.xcodeproj -scheme RoutinUsage`
- 新增行为应在 `RoutinUsageTests/` 添加或更新对应测试；提交前确保 CI 使用的 Xcode 26.3 与 macOS 26 SDK 校验通过。

## PR & commit conventions

- 从 `master` 分支创建分支；不要直接推送到默认分支。
- 提交信息使用 Conventional Commits（如 `feat:`、`fix:`、`docs:`、`refactor:`）。
- Pull Request 应在 CI 测试和 DMG 构建通过后提交。

## Security

- 永远不要提交密钥、Token、Cookie 或本地用户配置；凭证只应保存在 macOS 用户本地存储中。
- 提交问题和诊断日志必须保持脱敏；不要记录网页登录内容或会话信息。
- 项目当前未声明开源许可证，未经维护者许可不要再发布代码或构建产物。
