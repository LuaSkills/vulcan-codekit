# 任务计划：同步 Vulcan CodeKit 并实现 ast-grep FFI

## 一、任务目标

将 `D:\projects\vulcan-mcp-client\runtime\skills\vulcan-codekit` 中的正式技能内容同步到当前独立仓库 `D:\projects\vulcan-luaskills-skills\luaskills-vulcan-codekit`，替换当前 skill demo 内容；在当前仓库内新增 `ast-grep-ffi` Rust 工程，实现对 `ast-grep` 能力的 FFI 封装；将 Lua 代码中原先通过原始 `ast-grep` CLI 的调用改造为调用本仓库产出的 FFI 动态库；同时更新依赖配置与 GitHub 工作流，使技能包与 FFI 组件可由本仓库 release 产出并被技能依赖引用。

## 二、工作边界

1. 允许读取与参考以下外部路径：
   - `D:\projects\vulcan-mcp-client\runtime\skills\vulcan-codekit`
   - `D:\projects\vulcan-luaskills`
   - `https://github.com/ast-grep/ast-grep`
2. 仅允许修改当前工作目录：
   - `D:\projects\vulcan-luaskills-skills\luaskills-vulcan-codekit`
3. 外部仓库只用于理解、复制与参考，不直接修改。

## 三、详细执行步骤

1. 仓库盘点
   - 检查当前仓库文件结构、Git 状态与已有 demo 内容。
   - 检查源技能目录的文件结构、Lua 模块、依赖配置与 CI 配置。
   - 检查 Lua 引擎仓库中依赖加载、动态库路径解析与 FFI 使用方式。

2. 内容同步
   - 将源技能目录内容复制到当前仓库。
   - 保留当前仓库自身的 `.git` 目录。
   - 清理或覆盖 demo 代码，使当前仓库内容与正式技能一致。
   - 保留并继续维护本计划文档目录。

3. Rust FFI 工程实现
   - 在 `ast-grep-ffi` 下创建 Rust 工程。
   - 选择 `cdylib` 输出类型，产出跨平台动态库。
   - 依赖 `ast-grep-core` 与必要的语言解析能力。
   - 提供 C ABI 接口，覆盖 CodeKit 当前使用 `ast-grep` CLI 的能力。
   - 设计稳定的输入输出结构，优先使用 JSON 字符串作为跨语言边界协议。
   - 提供统一的内存释放接口，避免 Lua 侧泄漏 FFI 返回字符串。

4. Lua 调用改造
   - 定位所有原始 `ast-grep` CLI 调用。
   - 新增或修改 Lua FFI 绑定模块，按 Lua 引擎约定解析动态库路径。
   - 将 CLI 调用替换为 FFI 调用。
   - 保持原有工具输出结构与错误语义尽量兼容。
   - 为动态库缺失、加载失败、解析失败提供清晰错误信息。

5. 依赖与发布调整
   - 更新 `dependencies.yaml`，将 ast-grep 依赖转向本仓库 release 产物。
   - 更新 `.github/workflows`，构建技能包与各平台 FFI 动态库。
   - 将 FFI 产物纳入 release artifact。
   - 确保依赖清单中的平台、归档结构与 Lua 侧加载路径一致。

6. 验证与修复
   - 运行 Rust 格式化、检查与测试。
   - 运行 Lua 侧可用的格式、语法或功能验证。
   - 执行 CodeKit 关键流程的最小验证，确保 AST 树、AST 详情、文本搜索到结构映射等能力可用。
   - 对照本计划验收标准逐项检查；发现偏差时继续修复。

7. 计划闭环
   - 在本文件末尾追加「执行变更总结」。
   - 记录核心修复、文件变更清单、关键代码调整、遗留问题。
   - 验证通过后将本文件迁移到 `docs/completed/20260426/01-SYNC_CODEKIT_AST_GREP_FFI.md`。

## 四、技术选型

1. Rust FFI
   - 使用 Rust 2021 或更新 edition。
   - crate 类型使用 `cdylib`。
   - C ABI 入口使用 `extern "C"` 和空指针防护。
   - 输入输出使用 UTF-8 JSON 字符串，降低 Lua 与 Rust 之间结构体 ABI 不稳定风险。
   - 返回字符串由 Rust 分配，由显式释放函数回收。

2. ast-grep 能力封装
   - 优先使用 `ast-grep-core` 暴露的库 API，而不是再调用外部 CLI。
   - 语言识别与解析逻辑与 CodeKit 现有扩展名、语言映射保持一致。
   - 输出 JSON 与现有 Lua 工具内部数据结构对齐。

3. Lua FFI
   - 参考 `D:\projects\vulcan-luaskills` 中动态依赖与 FFI 调用约定。
   - 使用技能包本地依赖路径或运行时依赖目录解析动态库。
   - Lua 层保留功能编排，Rust 层只负责高成本 AST 查询。

4. CI 与 Release
   - GitHub Actions 构建 Windows、Linux、macOS 动态库。
   - release 包含技能包归档与 FFI 组件归档。
   - 依赖配置引用本仓库 release 下载地址，方便后续版本化分发。

## 五、验收标准

1. 当前仓库内容已替换为正式 `vulcan-codekit` 技能内容，并保留计划文档。
2. `ast-grep-ffi` 是可独立构建的 Rust 工程，能产出动态库。
3. Lua 代码不再依赖原始 `ast-grep` CLI 完成核心 AST 查询。
4. Lua 侧可以通过 FFI 加载动态库，并能获取与原工具兼容的结构化结果。
5. `dependencies.yaml` 指向本仓库 release 中的 FFI 产物。
6. GitHub workflow 能构建技能包与 FFI 动态库 release artifact。
7. Rust 检查、Lua 语法检查与可执行的关键功能验证通过。
8. 计划文件包含完整执行变更总结，并最终迁移到 `docs/completed/20260426/01-SYNC_CODEKIT_AST_GREP_FFI.md`。

## 六、执行变更总结

### 1. 核心修复与调整概述

本次已将当前仓库从 demo 技能内容替换为正式 Vulcan CodeKit 技能内容，并在仓库内新增 `ast-grep-ffi` Rust 动态库工程。Lua 侧原本依赖原始 `ast-grep` CLI 的 AST 扫描链路已切换为通过 FFI 调用本仓库产出的动态库，保留原有匹配结果、范围信息、元变量、metadata 与诊断信息的结构兼容性。依赖配置已改为引用本仓库 release 中的 FFI 组件，GitHub Actions 已调整为同时构建技能包与各平台 FFI 归档。

### 2. 📂文件变更清单（新增/修改/删除）

新增：
- `ast-grep-ffi/`：Rust FFI 工程，包含 `Cargo.toml`、`Cargo.lock`、`src/lib.rs`。
- `THIRD_PARTY_NOTICES.md`：更新后的第三方声明文件。
- `runtime/codekit-*.lua`、`runtime/shared_length.lua`：正式 CodeKit runtime 入口与共享逻辑。
- `help/`、`overflow_templates/`、`rules/`、`skills/`、`sgconfig.yml`：正式 CodeKit 技能文档、规则与技能元数据。
- `scripts/package_ffi.py`：FFI 动态库 release 归档脚本。

修改：
- `.github/workflows/release.yml`：新增技能包与 FFI 多平台 release 构建发布流程。
- `.github/workflows/validate.yml`：新增 Rust FFI 测试验证。
- `.gitignore`：忽略 Rust target 构建产物，并允许正式 `skills/` 目录入库。
- `dependencies.yaml`：移除 `ast-grep` CLI 依赖，新增 `ast-grep-ffi` FFI 依赖，并补齐 macOS Intel 包。
- `scripts/package_skill.py`、`scripts/validate_skill.py`：更新正式 CodeKit 包结构与依赖校验。
- `scripts/tag_release.ps1`、`scripts/tag_release.sh`、`README.md`、`skill.yaml`：替换 demo 说明与元数据为正式 CodeKit 内容。

删除：
- demo runtime：`runtime/demo_status.lua`、`runtime/overflow_demo.lua`、`runtime/rg_check.lua`。
- demo help 与模板：`help/demo-status.md`、`help/help.md`、`help/overflow-demo.md`、`help/rg-dependency.md`、`overflow_templates/demo-page.md`、`resources/guide.md`。
- 旧 demo 第三方声明路径：`licenses/THIRD_PARTY_NOTICES.md`。

### 3. 💻关键代码调整详情（方法变动、核心逻辑更替）

- Rust FFI 提供 `vulcan_codekit_ast_grep_version`、`vulcan_codekit_ast_grep_scan_json`、`vulcan_codekit_ast_grep_free_string` 三个 C ABI 入口；扫描输入输出采用 UTF-8 JSON，降低 Lua/Rust 结构体 ABI 耦合风险。
- Rust 侧使用 `ast-grep-config`、`ast-grep-core`、`ast-grep-language` 解析 rule YAML 与源文件，输出与原 Lua CLI 解析层兼容的 `matches`、`range`、`metaVariables`、`metadata`、`diagnostics`。
- `runtime/codekit-ast-detail.lua` 新增 FFI 动态库加载、平台库名解析、本地开发 fallback、JSON 请求封装与返回字符串释放逻辑。
- `runtime/codekit-ast-tree.lua`、`runtime/codekit-patch.lua`、`runtime/codekit-rg.lua` 已切换为复用 FFI scanner；`codekit-rg` 仍保留 `rg` CLI 作为文本搜索依赖，仅 AST 结构扫描部分改为 FFI。
- Release 工作流新增 Windows x64、Linux x64、Linux ARM64、macOS ARM64、macOS x64 FFI 构建矩阵，并通过 `scripts/package_ffi.py` 输出平台 zip 与 sha256。

### 4. ⚠️遗留问题与注意事项

- Windows ARM64 未纳入依赖矩阵，因为 `ripgrep 14.1.1` 当前没有对应 Windows ARM64 发布资产；若未来上游补齐资产，可同步扩展 `dependencies.yaml` 与 release matrix。
- 本仓库当前尚未实际发布 release，因此 `ast-grep-ffi` 依赖引用的 release 资产需要在打 tag 后由 GitHub Actions 首次生成。
- WorkMem 依赖按用户要求跳过，未接入本次执行。
- 已完成验证：`cargo fmt --check`、`cargo check`、`cargo test`、`cargo build --release`、`python scripts\validate_skill.py`、YAML 解析、`git diff --check`、技能包打包、FFI 打包、Lua runtime 加载、AST detail/tree/rg/patch smoke。
