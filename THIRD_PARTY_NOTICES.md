# 第三方版权与许可证声明

本文件用于说明 `vulcan-codekit` skill 包及其 `codekit-ffi` 原生组件所依赖的第三方工具与 Rust 库许可证信息。

适用范围如下：

- `codekit-ast-detail`
- `codekit-ast-tree`
- `codekit-repo-map`
- `codekit-rg`
- `codekit-node-source`
- `codekit-patch`
- `codekit-markdown-menu`
- 以及由 `dependencies.yaml` 下载并放置到配套工具/FFI 目录中的相关二进制组件

说明如下：

- 本文件用于包内合规归档与分发说明，不替代上游项目的原始许可证文本。
- 实际分发、复制或随包提供二进制文件时，仍应同时保留上游项目要求附带的版权声明与许可证说明。
- 以下信息以对应上游仓库的官方许可证文件为准。
- Rust FFI 组件的传递依赖许可证清单由 `cargo-deny` 自动生成，并记录在 `THIRD_PARTY_LICENSES.md`。

## 1. ast-grep

- 组件名称：`ast-grep`
- 在本 skill 包中的用途：通过本仓库构建的 `codekit-ffi` 统一动态库，为 `codekit-ast-detail`、`codekit-ast-tree` 与 `codekit-patch` 提供 AST 结构扫描、结构匹配与补丁验证能力
- 上游仓库：<https://github.com/ast-grep/ast-grep>
- 官方许可证文件：<https://github.com/ast-grep/ast-grep/blob/main/LICENSE>
- 许可证类型：`MIT License`
- 版权声明：`Copyright (c) 2022 Herrington Darkholme`

合规说明：

- `ast-grep` 采用 MIT License 发布。
- 根据其官方许可证，分发软件副本或其实质部分时，应保留版权声明与许可声明。
- 在本 skill 包中如随包分发基于 `ast-grep` crate 构建的 FFI 动态库，应继续保留其上游许可证信息。

## 2. Tokei

- 组件名称：`tokei`
- 在本 skill 包中的用途：作为 `codekit-ffi` 的 Rust 库依赖，为 `codekit-repo-map` 提供全语言文件、代码、注释、空行与目录聚合统计
- 上游仓库：<https://github.com/XAMPPRocky/tokei>
- 官方许可证文件：<https://github.com/XAMPPRocky/tokei/blob/master/LICENCE-APACHE> 与 <https://github.com/XAMPPRocky/tokei/blob/master/LICENCE-MIT>
- 许可证类型：`Apache-2.0 OR MIT`
- 版权声明：以上游仓库许可证文件及各版本发布内容为准

合规说明：

- `tokei` 采用 Apache License 2.0 与 MIT License 双许可证发布，使用者可任选其一遵循。
- 本项目不调用外部 `tokei` 可执行文件，而是把 crate 编译进 `codekit-ffi` 动态库；发布该动态库时仍应保留对应许可证声明。
- `tokei` 引入的传递依赖由 `cargo-deny` 门禁和 `THIRD_PARTY_LICENSES.md` 自动报告共同覆盖。

## 3. ripgrep (rg)

- 组件名称：`ripgrep`
- 可执行文件名称：`rg` / `rg.exe`
- 在本 skill 包中的用途：为 `codekit-rg` 与 `codekit-markdown-menu` 提供快速文本检索与 Markdown 文件扫描能力
- 上游仓库：<https://github.com/BurntSushi/ripgrep>
- 官方许可证说明：<https://github.com/BurntSushi/ripgrep/blob/master/COPYING>
- MIT 许可证文本：<https://github.com/BurntSushi/ripgrep/blob/master/LICENSE-MIT>
- Unlicense 文本：<https://github.com/BurntSushi/ripgrep/blob/master/UNLICENSE>
- 许可证类型：`Unlicense OR MIT License`
- MIT 版权声明：`Copyright (c) 2015 Andrew Gallant`

合规说明：

- `ripgrep` 官方声明其项目采用 `Unlicense` 与 `MIT License` 双许可证发布，使用者可以任选其一遵循。
- 若按 MIT License 路径使用或分发，应保留对应版权声明与许可声明。
- 若随本 skill 包分发 `rg` 或 `rg.exe`，建议一并附带上游 `COPYING`、`LICENSE-MIT` 与 `UNLICENSE` 的原始说明文件或等效许可证归档材料。

## 4. 包内落地要求

为保持 `vulcan-codekit` skill 包的分发规范性，当前目录至少应保留本声明文件，用于记录：

- 第三方工具名称
- 上游来源
- 许可证类型
- 版权声明
- 随包分发时需要保留的许可证要求

若后续新增新的外部二进制工具、FFI 动态库或第三方运行时依赖，应继续在本文件中追加对应条目。

## 5. 自动生成的 Rust 依赖许可证报告

`codekit-ffi` 的 Rust 依赖图通过以下命令生成许可证报告：

```powershell
python .\scripts\generate_cargo_deny_notices.py
```

生成结果写入 `THIRD_PARTY_LICENSES.md`，该文件应与 skill 包、FFI release 包一起分发。CI 使用 `cargo-deny` 检查许可证策略，并校验生成报告是否与当前依赖图一致。
