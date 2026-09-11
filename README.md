# PolyPals

简体中文 | [English](README.en.md)

[![CI](https://github.com/JacobTang-handsome/Polypals-language-pets-on-your-desktop/actions/workflows/ci.yml/badge.svg)](https://github.com/JacobTang-handsome/Polypals-language-pets-on-your-desktop/actions/workflows/ci.yml)

PolyPals 是一款原生 macOS 桌面陪伴与语言学习应用。三只彼此独立的双语宠物会留在桌面上，以轻量聊天、短卡片、日程提醒和自然动作陪伴学习：

- **Sol**：西班牙语伙伴
- **Mousse**：法语伙伴
- **Ash**：英语伙伴

每只宠物都有自己的语言档案、聊天记录、已确认记忆、物品栏、计划、熟悉度、桌面位置和通知偏好。窗口不会主动抢占键盘焦点，学习内容也可以完全离线使用。

> **项目状态：** PolyPals 0.4 正在开发中。目前尚未提供经过 Developer ID 签名和 Apple 公证的公开安装包；开发者可以从源码运行，本地生成的 `-local.dmg` 仅用于测试。

## 为什么做 PolyPals

传统语言学习工具通常需要用户主动打开应用并完成一段完整课程。PolyPals 希望把学习拆成短小、低压力的日常接触：宠物可以在合适的时间带来一两张卡片、进行一段对话，或按计划提醒复习，同时尊重专注、演示、全屏和安静时间。

项目遵循以下原则：

- **本地优先**：聊天、记忆、进度和设置默认保存在本机。
- **不打扰**：宠物窗口不抢焦点，主动行为受到频率和场景限制。
- **可以离线**：内置 126 张经过审核的种子卡片，不配置 API Key 也能使用。
- **隐私边界清楚**：只向当前选择的模型服务发送完成请求所需的有限上下文。
- **扩展是声明式的**：内容包和宠物包只包含受校验的数据与资源，不执行第三方脚本。

## 界面预览

项目还缺少适合公开展示、且不包含私人桌面内容的正式截图或演示视频。建议至少补充：三只宠物在桌面上的效果、聊天面板、学习卡片、计划页面和设置页面。

截图准备好后可放入 `Design/Screenshots/`，并在这里使用相对路径展示，例如：

```md
![三只 PolyPals 宠物在 macOS 桌面上](Design/Screenshots/desktop-overview.png)
```

## 主要功能

### 桌面陪伴

- 三个独立、透明且不会抢占焦点的宠物窗口
- 拖动、边缘吸附、多显示器位置恢复、大小调整、隐藏和休眠
- 随时间变化的自然动作、角色动作和可选的窗口边缘停驻
- 专注模式、演示模式、安静时间、全屏抑制和主动邀请频率限制
- 菜单栏中的 25/50 分钟专注计时器

### 语言学习

- 每只宠物独立配置 CEFR A1–C2 理解与表达等级
- 固定难度或保守的自适应难度
- 七种有限时长卡片类型，每只宠物内置 42 张，共 126 张
- 喜欢、太简单、太难和减少相似内容等反馈
- 跨形式复现、主题偏好、质量检查和离线回退
- 系统语音朗读，以及可选的 AI 卡片补充

### 聊天、记忆与关系

- OpenAI 和 DeepSeek 自备 API Key，两家服务完全分开配置
- 流式聊天、停止生成、重试、编辑重发、收藏和本次不保存
- 只有用户确认的内容才会成为长期记忆
- 每只宠物拥有独立且不会衰减的七级熟悉度
- 本地物品栏、礼物、拾获物和“今天发生了什么”摘要

### 计划与扩展内容

- 使用自然语言创建每天或每周计划
- 系统通知或桌宠动作、执行历史、稍后一小时和今天跳过
- 声明式 `.polypals-pack` 内容包与宠物包
- JSON Schema、SHA-256 完整性检查、路径安全检查和原子安装
- 应用与命令行工具共用同一套包验证逻辑

更详细的操作说明见 [使用指南](使用指南.md)，实现状态见 [IMPLEMENTATION.md](IMPLEMENTATION.md)。

## 系统要求

### 使用应用

- Apple 芯片 Mac
- macOS 14 或更高版本

### 从源码开发

- Xcode 16
- Swift 6
- Git

项目没有第三方 Swift 软件包依赖。只有使用 OpenAI 或 DeepSeek 聊天和智能补充卡片时才需要联网。

## 从源码开始

### 1. 克隆仓库

```sh
git clone https://github.com/JacobTang-handsome/Polypals-language-pets-on-your-desktop.git
cd Polypals-language-pets-on-your-desktop
```

### 2. 构建并测试

```sh
swift build
swift test
```

也可以使用 Xcode 打开 `Package.swift`，选择 `PolyPals` Scheme 后运行。

### 3. 启动应用

```sh
swift run PolyPals
```

首次启动不需要 API Key。应用会直接使用内置离线内容。

## 构建本地应用

生成用于本机测试、经过临时签名的 arm64 应用包：

```sh
Scripts/build-app.sh
open Distribution/PolyPals.app
```

生成本地测试 DMG：

```sh
Scripts/build-local-dmg.sh
```

这些产物没有经过 Developer ID 签名和 Apple 公证，不应作为公开正式版本传播。正式发布流程需要发布负责人提供证书和公证配置：

```sh
POLYPALS_SIGNING_IDENTITY='Developer ID Application: …' \
POLYPALS_NOTARY_PROFILE='polypals-notary' \
Scripts/sign-and-notarize.sh
```

完整发布检查见 [RELEASE.md](RELEASE.md)。

## API Key 与隐私

在应用“设置”中选择 OpenAI 或 DeepSeek，填写对应服务商的 API Key，然后执行连接测试。

- 两家服务的密钥分别保存在 macOS 钥匙串中。
- 密钥不会写入 SwiftData、导出文件、日志、截图或 Git 仓库。
- 只有当前选择的服务商会收到请求。
- 请求只包含当前消息、有限的近期上下文和用户确认的记忆。
- Responses API 请求明确设置 `store: false`。
- 应用不读取屏幕内容、代码、剪贴板或麦克风。
- 跨应用窗口停驻可以使用用户主动授予的辅助功能权限；没有该权限时仍可使用屏幕边缘回退位置。

完整数据边界见 [PRIVACY.md](PRIVACY.md)。发现安全问题时，请按照 [中文安全政策](SECURITY.zh-CN.md) 通过 GitHub Security Advisories 私下报告，不要在公开 Issue 中提交 API Key、聊天记录或用户数据库。

## 内容包与宠物包

仓库提供两类声明式扩展：

- **内容包**：增加经过授权的语言学习卡片。
- **宠物包**：增加受校验的宠物资源和元数据。

验证仓库示例：

```sh
Tools/validate-pack Examples/ContentPack/ExampleContent.polypals-pack
Tools/validate-pack Examples/PetPack/ExamplePet.polypals-pack
```

开发扩展前请阅读 [插件开发指南](插件开发指南.md) 或 [PLUGIN_DEVELOPMENT.md](PLUGIN_DEVELOPMENT.md)。文化卡必须提供来源，所有文字和美术资源都必须具有明确的使用与再分发权利。

## 测试与质量检查

提交 Pull Request 前至少运行：

```sh
swift test
swift build -c release
Tools/validate-pack Examples/ContentPack/ExampleContent.polypals-pack
Tools/validate-pack Examples/PetPack/ExamplePet.polypals-pack
Scripts/check-string-catalog.sh
Scripts/check-repository-safety.sh
```

GitHub Actions 会在 Pull Request 和推送到 `main` 时重复执行这些检查。CI 配置位于 [`.github/workflows/ci.yml`](.github/workflows/ci.yml)。

## 参与贡献

欢迎修复 Bug、改善可访问性、完善测试和文档，或者提交具有明确授权的内容包与宠物包。

推荐流程：

1. 对较大的功能、架构或数据模型变更，先创建 Issue 讨论。
2. Fork 仓库并从 `main` 创建独立分支。
3. 完成范围明确的修改，并补充相应测试和文档。
4. 运行上面的测试与质量检查。
5. 创建 Pull Request，说明验证结果以及隐私、迁移和授权影响。

详细规则见 [中文贡献指南](CONTRIBUTING.zh-CN.md)。参与社区即表示同意遵守 [中文行为规范](CODE_OF_CONDUCT.zh-CN.md)。

## 项目结构

```text
Sources/PolyPals/              应用主体、持久化、模型客户端、日程、通知与界面
Sources/PolyPalsPluginKit/     声明式包格式与安全验证
Sources/ValidatePack/          validate-pack 命令行工具
Sources/PolyPals/Resources/    本地化、内置宠物与应用资源
Tests/                         领域逻辑、迁移、网络契约与界面状态测试
Examples/                      可导入的内容包和宠物包示例
Schemas/                       与示例对应的 JSON Schema
Scripts/                       构建、发布、本地化和仓库安全脚本
Design/                        设计输入、生成过程与质量检查材料
Distribution/                  应用打包配置和本地构建产物
```

架构和依赖方向见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 当前限制

- 只支持 Apple 芯片 Mac 和 macOS 14+。
- 尚未提供经过签名和公证的公开下载版本。
- 不支持云端账户或跨设备同步，聊天、记忆和进度保存在本机。
- 不加载动态链接库，不运行插件脚本，也不允许内容包执行任意代码。
- 不开放运行时模型服务商插件，目前只支持内置的 OpenAI 和 DeepSeek 配置。
- 宠物包不能替换内置且保持稳定的 Sol、Mousse 或 Ash 标识符。
- Developer ID 证书和 Apple 公证凭据必须由发布负责人自行配置，不会进入仓库。

后续方向见 [ROADMAP.md](ROADMAP.md)。

## 许可证与资源权利

- 源代码采用 [Apache License 2.0](LICENSE)。
- 示例内容采用 CC BY 4.0。
- 生成的空白宠物图集测试素材采用 CC0。
- **内置角色与美术资源不授权。** Sol、Mousse 和 Ash 的名称、角色设定、视觉形象、精灵图、动画帧、插图、Logo 方案与原始参考资料均排除在 Apache-2.0 许可范围之外，除非对应目录另有明确的书面授权。

源代码的 Apache-2.0 许可不授予使用、改编或重新分发上述角色与美术资源的权利。如需在 Fork、派生项目、宣传或发布包中使用这些资源，必须先获得权利人的单独书面许可。贡献新内容或美术时，必须声明来源和许可，并确保拥有提交与再分发权利。

## 获取帮助

- 使用问题和可复现 Bug：提交 [Issue](https://github.com/JacobTang-handsome/Polypals-language-pets-on-your-desktop/issues)
- 功能建议：使用仓库中的 Feature request 模板
- 安全漏洞：按照 [中文安全政策](SECURITY.zh-CN.md) 私下报告
- 插件开发：阅读 [PLUGIN_DEVELOPMENT.md](PLUGIN_DEVELOPMENT.md)
