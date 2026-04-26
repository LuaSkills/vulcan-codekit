# 任务目标

将当前仓库的发布流程调整为可手动执行的双通道发布：

1. LuaSkill 技能包作为独立发布产物构建并上传。
2. ast-grep FFI 原生组件作为独立发布产物构建并上传。
3. 两类产物最终都指向同一个 GitHub Release tag。
4. FFI 依赖通过 `dependencies.yaml` 中的 GitHub Release 地址安装，地址必须与当前仓库远端一致。

# 详细执行步骤

1. 对比当前 `.github/workflows/release.yml` 与 `D:\projects\vulcan-luaskills` 中手动发布流程，确认需要迁移的触发方式、runner 选择方式与 Release 上传方式。
2. 修改 release workflow：
   - 增加 `workflow_dispatch` 手动运行入口。
   - 增加 Release tag 输入。
   - 拆分 LuaSkill 技能包构建与 FFI 原生组件构建。
   - 支持分别关闭 LuaSkill 构建或指定平台 FFI 构建。
   - 两条构建链路均上传到同一个 `tag_name`。
3. 保留五个平台的 FFI 编译范围：
   - `macos-arm64`
   - `macos-x64`
   - `linux-arm64`
   - `linux-x64`
   - `windows-x64`
4. 校验 `dependencies.yaml` 中 FFI GitHub Release 仓库地址是否与当前 `origin` 匹配，并在必要时修正。
5. 更新 README 中发布流程说明，明确技能包与 FFI 组件的发布关系。
6. 运行本地校验：
   - YAML 解析校验。
   - 现有技能布局校验。
   - 打包脚本语法或烟测校验。
   - Git diff 基础格式校验。

# 技术选型

1. 继续使用 GitHub Actions 与 `softprops/action-gh-release@v2` 上传 Release 产物。
2. 参考 `vulcan-luaskills` 的 `workflow_dispatch` + runner choice + `tag_name` 方式，实现可手动、可分平台的发布。
3. FFI 构建继续使用 Rust `cargo build --release --target --target-dir target`，避免产物路径偏移。
4. LuaSkill 包继续使用仓库内 `scripts/package_skill.py`，保证技能包规则与当前脚本一致。

# 验收标准

1. GitHub Actions 页面可以通过 Run workflow 手动触发 release。
2. LuaSkill 技能包与 FFI 组件可以分离构建。
3. 同一次手动发布中启用的所有产物都会上传到同一个 Release tag。
4. FFI 组件仅覆盖五个平台，不引入 Windows ARM64。
5. `dependencies.yaml` 中 FFI 依赖指向当前仓库 GitHub Release。
6. 本地校验命令通过，无明显 YAML 或脚本错误。

# 执行变更总结

## 1. 核心修复与调整概述

已将 `Release Vulcan CodeKit LuaSkill` 工作流改为支持手动运行，并参考 `vulcan-luaskills` 的发布方式加入版本输入、runner 选择与同 Release tag 上传。LuaSkill 技能包与 ast-grep FFI 原生组件现在是两条独立构建链路，可以分别关闭或按平台选择执行。技能包仍保持 LuaSkills 管理安装规则，FFI 组件继续通过 `dependencies.yaml` 中的 GitHub Release 依赖从 `OpenVulcan/luaskills-vulcan-codekit` 安装。

## 2. 📂文件变更清单

新增：

- `docs/completed/20260426/02-RELEASE_WORKFLOW_SPLIT.md`：本次执行计划与闭环记录。

修改：

- `.github/workflows/release.yml`：新增 `workflow_dispatch`，拆分 LuaSkill 与 FFI 构建上传链路。
- `scripts/package_skill.py`：允许手动 workflow 在分支 ref 下使用 `--version` 打包，只在 tag ref 下强制校验 `GITHUB_REF_NAME`。
- `scripts/validate_skill.py`：增加 ast-grep FFI GitHub Release 仓库地址校验。
- `README.md`：补充独立仓库、发布产物、手动 release 与 FFI GitHub 依赖说明。

删除：

- 无。

## 3. 💻关键代码调整详情

- Release workflow 新增 `prepare-release`，统一计算 `version`、`version_no_v`、LuaSkill 构建开关与 FFI 平台矩阵。
- LuaSkill 构建 job 使用 `scripts/package_skill.py --version` 生成 `luaskills-vulcan-codekit-v{version}-skill.zip` 与 checksum，并直接上传到同一个 `tag_name`。
- FFI 构建 job 继续使用 `cargo build --manifest-path ast-grep-ffi/Cargo.toml --release --target --target-dir target`，保证打包路径稳定。
- FFI 矩阵仅保留 `macos-arm64`、`macos-x64`、`linux-arm64`、`linux-x64`、`windows-x64` 五个平台。
- `validate_skill.py` 固化校验 `ast-grep-ffi` 的 `github.repo` 为 `OpenVulcan/luaskills-vulcan-codekit`，避免技能包内依赖地址漂移。

## 4. ⚠️遗留问题与注意事项

- GitHub Actions 的 Run workflow 按钮需要本次 workflow 文件进入默认分支后才会在远端界面出现。
- 手动只发布 LuaSkill 包而不发布 FFI 时，目标 Release 可能暂时缺少运行时 FFI 资产；后续可用同一个 `version` 只启用 FFI 平台补齐。
- 本次未新增 Windows ARM64 支持，仍按用户要求只发布五个平台。
- `git diff --check` 仅输出当前仓库既有 CRLF 提示，没有空白错误。
