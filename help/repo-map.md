# `vulcan-codekit-repo-map`

在陌生仓库中开始分析时，先使用 Repo Map 获取仓库规模、目录分布和全部 Tokei 可识别语言的代码统计，再决定 `ast-tree` 或 `rg` 的精确目录范围。

## 何时使用

- 第一次进入一个不了解规模与结构的仓库。
- 尚不知道 `ast-tree.dir` 应该指向哪个源码目录。
- 尚不知道 `rg.dir` 应该缩小到哪个子树。
- 需要识别 monorepo、生成目录、配置密集目录或代码热点。
- 需要区分“仓库中没有文件”和“Tokei 不识别这些文件”。

## 输入

- `PWD`：可选的绝对项目或工作区根路径。VulcanCode 在存在当前项目时会隐藏并自动注入此参数；`dir` 可以相对此根路径。其他宿主可显式传入；没有可用 `PWD` 时，`dir` 必须是绝对路径。
- `dir`：必填。恰好一个已经存在的仓库或目录路径；不接受文件、多路径和换行列表。
- `max_depth`：可选，默认 `3`，范围 `1..8`。仅控制模型可见目录树深度；底层始终先完成整个目录的递归扫描与聚合。
- `noignore`：可选，默认 `false`。设为 `true` 时禁用普通 `.gitignore`、`.ignore` 和 `.tokeignore`；`.git`、`target`、`node_modules`、`dist` 等 CodeKit 强制排除目录仍不会进入扫描。

Repo Map 故意不提供 `extensions`、`languages` 或 Tokei `types` 参数。它的职责是提供完整的仓库级初始地图，而不是提前猜测应该关注哪些语言。

## 输出

输出为纯 Markdown，固定包含：

1. `OVERVIEW`
   - 完整目录数量。
   - 全部普通文件数量。
   - Tokei 已识别文件数量。
   - Tokei 未识别文件数量。
   - 文件总字节数。
   - 代码、注释、空行和总行数。
   - 实际 ignore、隐藏文件、符号链接和折叠范围。
2. `LANGUAGES`
   - Tokei 检测到的全部主语言。
   - 每种语言的文件数、代码、注释、空行和总行数。
   - Tokei 的不准确标记。
3. `DIRECTORY TREE`
   - 只包含目录节点，不包含文件节点。
   - 每个目录同时显示直接子目录数、递归后代目录数、直接文件数与递归文件数。
   - 每个目录显示递归已识别/未识别文件、字节、代码行和主要语言分布。
   - 超出深度或节点上限时显示 `folded:N`，但父目录与仓库总量仍包含被折叠子树。
4. `DIAGNOSTICS`
   - 仅在存在遍历错误、元数据读取失败或其他不完整状态时出现。

## 统计口径

- `Files` 是应用 ignore 与强制排除策略后的全部普通文件，不等于源码文件数。
- `Recognized files` 是 Tokei 实际产生报告的唯一文件数。
- `Unrecognized files` 是完整文件普查与 Tokei 报告集合的差值。
- `Lines` 等于 Tokei 的 `code + comments + blanks`；未知文件不贡献代码行，但仍贡献文件数和字节数。
- 内嵌语言代码块会通过 Tokei `CodeStats::summarise` 纳入所属主文件统计，既不会遗漏，也不会重复计数。
- 目录的 `files:A/B` 表示“直接文件数/递归文件数”。
- 目录的 `dirs:A/B` 表示“直接子目录数/递归后代目录数”，后者不包含目录自身。
- 根目录使用 `.`，路径统一使用 `/`，避免平台分隔符进入稳定输出协议。

## 默认安全边界

- 包含 `.github` 等隐藏正式目录。
- 默认遵循 `.gitignore`、`.ignore`、`.tokeignore` 及父级 ignore。
- 始终不跟随符号链接。
- 始终排除 `.git`、`target`、`node_modules`、`dist`、`build`、`vendor`、`output`、`.idea`、`.vscode` 与 `__pycache__`。
- 同一宿主进程中的全仓库扫描串行执行，避免多个 Repo Map 同时争抢磁盘与 CPU。
- Rust 在完整聚合后才进行展示裁剪，禁止用“只扫描前三层”伪装完整仓库统计。

## 推荐工作流

1. `vulcan-codekit-repo-map`
   - 先理解仓库总规模、目录分布、语言分布和代码热点。
2. `vulcan-codekit-ast-tree`
   - 对 Repo Map 选中的一个源码目录建立逐文件 AST 摘要。
3. `vulcan-codekit-ast-detail`
   - 展开已经明确的文件结构。
4. `vulcan-codekit-rg`
   - 在已经缩小的目录中把文本锚点映射到函数、方法或类型 owner。
5. `vulcan-codekit-node-source`
   - 获取明确函数或方法的完整当前源码。
6. `vulcan-codekit-patch`
   - 对确认后的完整函数或方法执行结构化替换。

## 不应使用的方式

- 不要把 Repo Map 当成文件检索工具；它不会返回文件名。
- 不要为了寻找一个已知符号反复提高 `max_depth`；已知文本锚点应使用 `rg`。
- 不要把未识别文件数解释为不存在文件；它只表示 Tokei 没有为这些文件生成代码统计。
- 不要把 `noignore=true` 作为常规默认值；它适合有明确理由检查被忽略目录时使用。
- 不要在 Repo Map 已经指出具体源码子树后，继续对仓库根目录执行大范围 `ast-tree`。
