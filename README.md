# EasyNote

EasyNote 是一个 SwiftUI iOS 笔记原型，聚合日记、待办、语音转写和 AI 辅助写作能力。当前仓库是公开的本地优先 MVP，目标是保留可运行的产品雏形，并逐步补齐工程化验证。

## 功能

- 日记：创建、编辑、检索、筛选、排序、收藏、标签、心情、Markdown 预览、本地回顾和语音转写。
- 待办：优先级、截止时间、循环任务、分类视图、推荐活动转待办、本地通知和系统“提醒事项”agent 写入。
- AI：DeepSeek 聊天补全接口用于日记摘要、文本润色、扩写、总结和笔记探索；生成结果先进入当前会话历史，用户确认后才应用到日记或转写内容。笔记探索请求固定绑定发起时的会话；服务失败时只返回可由当前日记验证的本地结果，无匹配事实时显示可重试错误。聊天消息只有保存成功后才会请求服务；保存失败会恢复已持久化的会话并保留重试入口。
- 数据：SwiftData 本地持久化和版本化 schema，本地备份/恢复，CloudKit 服务代码保留但 Debug 默认模拟，并在设置中展示真实同步预检状态。
- 设置：主题模式、主题色、钥匙串 API key 配置、可撤回的 AI 内容授权、本地数据备份和待办提醒方式。

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
3. 在应用的“设置”页填写并保存 DeepSeek API 密钥，再阅读隐私提示并明确允许发送所选文本及生成推荐所需的近期日记。未配置密钥或未授权时，AI 调用都会在本地失败，不会发起网络请求。

语音转写不会自动覆盖日记正文。录音完成后，转写结果先进入编辑草稿，用户选择“插入正文”或“替换正文”也不会立即持久化；只有点击“完成”才会一次保存正文、心情、标签和录音，“取消”会丢弃这些草稿变更并删除未保存的本地录音。

AI 生成的日记摘要、转写润色、扩写和总结同样不会自动覆盖现有内容。结果会先显示为“应用 / 复制 / 丢弃”的待确认项，并保留在当前编辑或探索会话的最近结果中。

DeepSeek API 密钥存储在本机钥匙串中，使用 `WhenUnlockedThisDeviceOnly` 可访问级别，不会同步到其他设备。AI 内容授权默认关闭，保存或迁移已有密钥不会自动授权；授权后，用户选择处理的日记或语音转写文本会发送给 DeepSeek，生成个性化推荐时还会发送近期日记的标题、正文、心情和标签。录音音频文件不会发送，API 密钥仅通过 HTTP Authorization 请求头用于 DeepSeek 鉴权，不会写入提示正文。用户可以随时在设置中撤回授权，撤回后后续 AI 请求会在联网前被阻止。

新建待办会先保留为未持久化草稿，只有点击“保存”才写入 SwiftData；点击“取消”不会创建占位待办。新建、编辑或删除保存失败时，当前界面和输入会保留并显示错误，用户可以修正后重试。重复待办必须设置截止日期，移除截止日期会同时关闭重复设置。

现有未版本化 SwiftData 数据库会用字段布局相同的 V1 schema 原位接管，不会自动重建。如果数据库无法打开，EasyNote 会停留在恢复界面，不会自动清空数据。可以先重试；选择重建时必须再次确认，应用会先把 `EasyNote.store` 及现有 WAL/SHM 文件复制到 `Documents/EasyNoteRecovery/<timestamp>`，再创建新数据库。

本地备份继续使用 `.easynotebackup` V1 JSON 文件。导入会在写入前检查文件、记录数量和录音大小；超限或无效文件不会修改本地数据。恢复录音使用稳定的资产 ID 文件名，重复导入不会产生额外副本；成功导入后只清理 Documents 中不再被任何日记引用的 EasyNote 录音文件。

待办提醒有三种模式：关闭、EasyNote 通知、系统提醒事项。EasyNote 通知使用 iOS 本地通知，只有未完成且有未来截止时间的待办会安排提醒；关闭该模式会取消 EasyNote 创建的本地通知，但不会修改待办数据。系统提醒事项模式会关闭 EasyNote 本地通知，由确定性的 agent 根据待办标题、备注、优先级和截止时间决定预留时间，并把待办写入 Apple“提醒事项”App；写入的提醒备注中包含 `EasyNoteTodoID:<uuid>` 标记，便于后续编辑、完成或删除时更新同一条系统提醒。切到系统提醒事项且权限允许时会同步当前待办；如果权限状态刷新稍后返回允许，Settings 会补同步当前待办。切到 EasyNote 通知时，EasyNote 只在可能存在已写入系统提醒时清理当前待办对应的系统提醒事项，避免首次启用本地通知时报无关的提醒事项权限错误，也避免同一个待办由两套提醒同时触发。

仓库不包含默认 API 密钥。旧版本保存在 `UserDefaults["openai_api_key"]` 的密钥会在钥匙串写入并读回校验成功后迁移，失败时旧值会保留并在设置中显示错误。此前本地原型中出现过硬编码密钥，该密钥应视为已泄露并轮换。

## 当前限制

- CloudKit 在 Debug 下默认使用模拟模式，当前只提供同步预检，不启用真实 iCloud 同步。
- 命令行构建依赖本机 Xcode/Simulator 插件状态；如遇 `IDESimulatorFoundation` 加载失败，需要先修复 Xcode 安装。
- ViewModel 与服务层仍保留原型期结构，后续应继续拆分可测试协议和依赖注入。

## 项目协作

- `main` 是稳定分支，`dev` 是集成分支。
- 日常功能、修复、文档和重构工作从 `dev` 创建 topic branch，并优先合入 `dev`。
- 当前工程文档入口见 [doc/README.md](doc/README.md)，其中 `doc/` 记录当前事实，`doc/src/` 镜像关键源码边界。
- 开发、验证、Codex review loop 和 promotion 流程见 [doc/mvp-runbook.md](doc/mvp-runbook.md)。
- 当前实施计划入口见 [plan/README.md](plan/README.md)。
- Coding agent 约定见 [AGENTS.md](AGENTS.md)。

## 验证命令

```bash
xcodebuild -list -project EasyNote.xcodeproj
xcodebuild -showdestinations -project EasyNote.xcodeproj -scheme EasyNote
xcodebuild test -project EasyNote.xcodeproj -scheme EasyNote -destination 'platform=iOS Simulator,name=<available simulator>'
```
