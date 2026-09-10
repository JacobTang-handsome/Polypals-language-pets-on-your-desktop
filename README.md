# PolyPals

简体中文 | [English](README.en.md)

PolyPals 0.4 是一款原生 macOS 14+ 桌面陪伴应用，包含三只彼此独立的双语宠物：西班牙语伙伴 Sol、法语伙伴 Mousse 和英语伙伴 Ash。每只宠物都拥有独立且不会抢占焦点的桌面窗口，以及各自的语言档案、日常安排、聊天记录、已确认记忆、物品栏、计划、亲密度、桌面位置和通知偏好。

PolyPals 坚持本地优先。应用不会请求屏幕录制、辅助功能或麦克风权限。聊天功能支持用户自行提供 OpenAI 或 DeepSeek API Key，两家服务的密钥分别保存在 macOS 本地钥匙串中。所有 OpenAI Responses API 请求均明确设置 `store: false`，请求地址固定为各服务商的官方 API。

## 系统要求

- Apple 芯片 Mac
- macOS 14 或更高版本
- Xcode 16 / Swift 6

## 开发与运行

使用 Xcode 打开 `Package.swift`，或者在终端中运行：

```sh
swift build
swift test
swift run PolyPals
```

项目运行时不依赖第三方软件包。只有使用可选的 AI 聊天与卡片变体功能时才需要联网；应用内置 126 张经过审核、可离线使用的种子卡片。每只宠物拥有 42 张卡片，涵盖七种卡片类型，每类六张，并支持根据反馈轮换内容、跨模态互动，以及可选的 AI 内容补充。

## 截图

用于发布的截图应放在 `Design/Screenshots/`。请勿提交本地测试截图或包含私人桌面内容的图片。

## v0.4 主要功能

- 支持 OpenAI 和 DeepSeek 自备 API Key，两者使用独立的钥匙串存储项，并提供连接测试
- 每只宠物拥有七级、不会衰减的亲密度系统，每日获得的亲密度点数设有上限
- 根据时间变化的环境动作，以及小巧、符合角色特点的聊天面板
- 卡片反馈、主题偏好、AI 内容质量检查、本地缓存清理和 JSON 内容包导入
- 每只宠物独立设置 CEFR A1–C2 语言等级，可分别配置理解能力和表达能力，并支持固定模式或保守的自适应模式
- 声明式内容包和宠物包，支持离线校验、SHA-256 完整性检查、原子安装、示例、JSON Schema 和统一命令行验证工具
- 自然语言日程、执行历史、稍后提醒与跳过操作、全局邀请次数限制，以及菜单栏中的 25/50 分钟专注计时器
- SwiftData V1 → V4 数据迁移和迁移前备份；旧版模型哈希保持冻结，语言设置通过增量附属记录保存

## API Key 与隐私

在“设置”中选择 OpenAI 或 DeepSeek，然后填入对应服务商的 API Key。密钥会分别保存在 macOS 钥匙串中，不会进入 SwiftData、导出文件、日志、快照或 Git 仓库。只有当前选中的服务商会收到经过范围限制的请求，未经用户确认的记忆不会上传。

完整的数据边界说明请参阅 [隐私说明](PRIVACY.md)。

## 构建本地应用

运行：

```sh
Scripts/build-app.sh
open Distribution/PolyPals.app
```

`Scripts/build-app.sh` 会创建一个用于本地测试、经过临时签名的 arm64 应用包。正式发布所需的签名与公证凭据不会保存在仓库中。

如需明确仅供本地使用、经过临时签名的磁盘映像：

```sh
Scripts/build-local-dmg.sh
```

请勿将生成的 `-local.dmg` 当作正式版本传播。公开发布版本需要完成 Developer ID 签名与 Apple 公证：

```sh
POLYPALS_SIGNING_IDENTITY='Developer ID Application: …' \
POLYPALS_NOTARY_PROFILE='polypals-notary' \
Scripts/sign-and-notarize.sh
```

## 项目结构

- `Sources/PolyPals`：应用主体、持久化、模型客户端、日程系统、通知和界面
- `Sources/PolyPalsPluginKit`：稳定的公开清单格式与插件包校验边界
- `Sources/ValidatePack`：供社区使用的验证命令
- `Examples` 和 `Schemas`：可导入的内容包、宠物包示例及对应 JSON Schema
- `Tests`：可重复的领域逻辑、持久化、网络契约和界面状态测试
- `Design/References`：仅作为设计输入保留的原始参考资料
- `Design/PetRuns`：可复现的宠物生成过程和质量检查产物
- `Sources/PolyPals/Resources/Pets`：应用内置的 v2 精灵图集与清单

数据边界请参阅 [PRIVACY.md](PRIVACY.md)，发布步骤请参阅 [RELEASE.md](RELEASE.md)，中文安装与日常使用方法请参阅 [使用指南.md](使用指南.md)。

## 插件开发与参与贡献

开发插件前，请阅读 [插件开发指南](插件开发指南.md) 或 [PLUGIN_DEVELOPMENT.md](PLUGIN_DEVELOPMENT.md)，并使用 `Tools/validate-pack` 验证两个示例包。

参与项目请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。如需报告安全问题，请按照 [SECURITY.md](SECURITY.md) 的说明，通过 GitHub Security Advisories 私下提交。

## 当前限制

PolyPals 不会加载动态链接库、运行插件脚本、开放运行时模型服务商插件、将记忆同步到云端账户，也不会配置 Developer ID 或 Apple 公证凭据。宠物包只包含声明式资源和元数据，不能替换内置且保持稳定的 Sol、Mousse 或 Ash 标识符。

## 许可证

源代码采用 Apache-2.0 许可证。示例内容采用 CC BY 4.0，生成的空白宠物图集测试素材采用 CC0。

内置角色设计、原始参考资料和美术资源不会因代码许可证而自动获得重新授权；除非获得明确的资源授权，否则请勿重新分发这些内容。
