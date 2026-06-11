# EasyNote

EasyNote 是一个 SwiftUI iOS 笔记原型，聚合日记、待办、语音转写和 AI 辅助写作能力。当前仓库目标是保留可运行的产品雏形，并逐步补齐工程化验证。

## 功能

- 日记：创建、编辑、检索、筛选、排序、收藏、标签、心情、Markdown 预览和语音转写。
- 待办：优先级、截止时间、循环任务、分类视图和推荐活动转待办。
- AI：DeepSeek 聊天补全接口用于日记摘要、文本润色、扩写、总结和笔记探索。
- 数据：SwiftData 本地持久化，CloudKit 服务代码保留但 Debug 默认模拟。
- 设置：主题模式、主题色和本机 API key 配置。

## 技术栈

- SwiftUI
- SwiftData
- Combine
- Speech / AVFoundation
- CloudKit
- Xcode 项目结构

## 本地运行

1. 使用 Xcode 打开 `EasyNote.xcodeproj`。
2. 选择 `EasyNote` scheme 和 iOS Simulator。
3. 在应用的“设置”页填写 DeepSeek API 密钥后再使用 AI 功能；未配置时 AI 调用会在本地失败并提示配置密钥。

语音转写不会自动覆盖日记正文。录音完成或 AI 润色后，转写结果会先显示在编辑器中，用户需要选择“插入正文”或“替换正文”后才会写入当前日记；取消新建日记会丢弃未保存的本地录音文件。

仓库不包含默认 API 密钥。此前本地原型中出现过硬编码密钥，该密钥应视为已泄露并轮换。

## 当前限制

- CloudKit 在 Debug 下默认使用模拟模式，首次收口不启用真实 iCloud 同步。
- 命令行构建依赖本机 Xcode/Simulator 插件状态；如遇 `IDESimulatorFoundation` 加载失败，需要先修复 Xcode 安装。
- ViewModel 与服务层仍保留原型期结构，后续应继续拆分可测试协议和依赖注入。

## 项目协作

- `main` 是稳定分支，`dev` 是集成分支。
- 日常功能、修复、文档和重构工作从 `dev` 创建 topic branch，并优先合入 `dev`。
- 当前工程文档入口见 [doc/README.md](doc/README.md)，其中 `doc/` 记录当前事实，`doc/src/` 镜像关键源码边界。
- 当前实施计划入口见 [plan/README.md](plan/README.md)。
- Coding agent 约定见 [AGENTS.md](AGENTS.md)。

## 验证命令

```bash
xcodebuild -list -project EasyNote.xcodeproj
xcodebuild -showdestinations -project EasyNote.xcodeproj -scheme EasyNote
xcodebuild test -project EasyNote.xcodeproj -scheme EasyNote -destination 'platform=iOS Simulator,name=<available simulator>'
```
