# 参与贡献

简体中文 | [English](CONTRIBUTING.md)

感谢你帮助改进 PolyPals。我们欢迎范围明确、容易审查并且不破坏用户数据的贡献。

## 开始之前

- 架构、数据模型、隐私边界或用户体验的较大变更，请先创建 Issue 讨论。
- 小型 Bug 修复、测试和文档改进可以直接提交 Pull Request。
- 请勿在 Issue、PR、测试数据或截图中提交真实 API Key、聊天记录或个人信息。

## 开发环境

- Apple 芯片 Mac
- macOS 14 或更高版本
- Xcode 16
- Swift 6
- Git

克隆并创建独立分支：

```sh
git clone https://github.com/JacobTang-handsome/Polypals-language-pets-on-your-desktop.git
cd Polypals-language-pets-on-your-desktop
git switch -c feature/short-description
```

## 分支和 Commit

建议使用以下分支名前缀：

- `feature/...`：新功能
- `fix/...`：Bug 修复
- `docs/...`：文档改动
- `test/...`：测试改动
- `refactor/...`：不改变外部行为的重构

Commit 应尽量小而单一，并使用简短的命令式说明，例如：

```text
fix: preserve notification requests in presentation mode
docs: clarify asset licensing
```

## 必须通过的检查

提交 Pull Request 前请运行：

```sh
swift test
swift build -c release
Tools/validate-pack Examples/ContentPack/ExampleContent.polypals-pack
Tools/validate-pack Examples/PetPack/ExamplePet.polypals-pack
Scripts/check-string-catalog.sh
Scripts/check-repository-safety.sh
```

新增用户可见文字时，必须更新 `Sources/PolyPals/Resources/Localizable.xcstrings`，并运行字符串目录检查。

## 数据模型与迁移

修改 SwiftData Schema 时：

1. 添加新的版本化迁移，不要改写已经发布的旧模型。
2. 保留迁移前备份。
3. 增加旧数据、空数据和部分数据测试。
4. 迁移失败时绝不能删除用户数据库。

## 内容、美术与角色权利

- 文化和学习内容必须注明来源与许可。
- 贡献者必须拥有提交、修改和重新分发相关内容的权利。
- 不要提交来源不明、仅供参考或无再分发许可的美术作品。
- PolyPals 内置角色名称、角色设定、视觉形象、精灵图、动画帧、插图、Logo 方案和原始参考资料不授权，也不属于 Apache-2.0 源代码许可范围。
- 未经权利人单独书面许可，不得在 Fork、派生项目、宣传或发布包中使用这些内置角色和美术资源。

## Pull Request 要求

Pull Request 应当：

- 聚焦一个明确的问题，避免混入无关格式化或重构。
- 说明修改内容、修改原因和验证方式。
- 关联对应 Issue（如果存在）。
- 补充或更新相关测试与文档。
- 说明隐私、数据迁移、兼容性和授权影响；没有影响时也请明确填写“无”。
- 确认没有 API Key、用户数据库、日志、应用包、DMG、证书或公证凭据。

插件和声明式扩展贡献还应遵守 [插件开发指南](插件开发指南.md) 或 [PLUGIN_DEVELOPMENT.md](PLUGIN_DEVELOPMENT.md)，并使用对应的 Issue 模板。

参与项目即表示同意遵守 [行为规范](CODE_OF_CONDUCT.zh-CN.md)。安全漏洞请按照 [安全政策](SECURITY.zh-CN.md) 私下报告。
