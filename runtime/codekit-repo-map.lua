--[[
Repository-first directory and code-statistics map for Vulcan CodeKit.
Vulcan CodeKit 面向仓库初始理解的目录与代码统计地图。
]]

-- Default and maximum model-visible directory depths.
-- 默认与最大模型可见目录深度。
local DEFAULT_MAX_DEPTH = 3
local MAX_MAX_DEPTH = 8
-- Fixed Rust response-node budget kept out of the ordinary public tool surface.
-- 不暴露给普通工具调用方的固定 Rust 响应节点预算。
local MAX_RENDERED_DIRECTORIES = 2000
-- Process-local cache of the shared CodeKit FFI Lua module.
-- 共享 CodeKit FFI Lua 模块的进程内缓存。
local CODEKIT_FFI_MODULE = nil
-- Process-local cache of the shared host-managed PWD path module.
-- 宿主管理 PWD 共享路径模块的进程内缓存。
local CODEKIT_PATH_MODULE = nil

--[[
Trim leading and trailing whitespace from one value.
移除一个值的首尾空白。

Parameters / 参数:
- value(any): Value converted to text before trimming. / 在裁剪前转换为文本的值。

Returns / 返回值:
- string: Trimmed text. / 裁剪后的文本。
]]
local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

--[[
Render arbitrary path or diagnostic text as one safe Markdown code span.
将任意路径或诊断文本渲染为安全的单行 Markdown 代码片段。

Parameters / 参数:
- value(any): Value to normalize and render. / 需要规范化并渲染的值。

Returns / 返回值:
- string: Markdown code span whose delimiter cannot collide with the content. / 分隔符不会与内容冲突的 Markdown 代码片段。
]]
local function markdown_code_span(value)
    -- Escape line-breaking controls so one filesystem name cannot inject new Markdown rows.
    -- 转义换行控制字符，避免单个文件系统名称注入新的 Markdown 行。
    local text = tostring(value or ""):gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("\t", "\\t")
    -- Find the longest existing backtick run before choosing a safe delimiter.
    -- 在选择安全分隔符前查找内容中最长的反引号连续段。
    local longest_run = 0
    for run in text:gmatch("`+") do
        longest_run = math.max(longest_run, #run)
    end
    -- CommonMark code spans require at least one backtick and may use a longer delimiter.
    -- CommonMark 代码片段至少需要一个反引号，也允许使用更长分隔符。
    local delimiter = string.rep("`", longest_run + 1)
    if text:match("^[%s`]") or text:match("[%s`]$") then
        return delimiter .. " " .. text .. " " .. delimiter
    end
    return delimiter .. text .. delimiter
end

--[[
Return the runtime directory that contains the current Lua entry.
返回包含当前 Lua 入口的运行时目录。

Returns / 返回值:
- string: Runtime entry directory. / 运行时入口目录。
]]
local function get_entry_dir()
    return tostring(vulcan.context.entry_dir or vulcan.context.skill_dir or ".")
end

--[[
Load and cache the shared CodeKit PWD path module.
加载并缓存 CodeKit PWD 共享路径模块。

Returns / 返回值:
- table|nil: Shared PWD path contract. / 共享 PWD 路径契约。
- table|nil: Structured loading failure. / 结构化加载失败。
]]
local function load_codekit_path_module()
    if CODEKIT_PATH_MODULE then
        return CODEKIT_PATH_MODULE, nil
    end
    -- Exact sibling module path owned by the current skill runtime.
    -- 当前技能运行时拥有的精确同级模块路径。
    local module_path = vulcan.path.join(get_entry_dir(), "codekit-path.lua")
    -- Compiled shared module chunk loaded without mutating package.path.
    -- 在不修改 package.path 的情况下加载的共享模块代码块。
    local chunk, load_error = loadfile(module_path)
    if not chunk then
        return nil, {
            error = "codekit_path_module_load_failed",
            message = tostring(load_error),
            path = module_path,
        }
    end
    -- Executed module result validated as the exact helper table contract.
    -- 经过精确辅助表契约校验的模块执行结果。
    local loaded, module_or_error = pcall(chunk)
    if not loaded or type(module_or_error) ~= "table" then
        return nil, {
            error = "codekit_path_module_invalid",
            message = loaded and "codekit-path.lua did not return a table" or tostring(module_or_error),
            path = module_path,
        }
    end
    CODEKIT_PATH_MODULE = module_or_error
    return CODEKIT_PATH_MODULE, nil
end

--[[
Load and cache the shared CodeKit FFI Lua module.
加载并缓存共享 CodeKit FFI Lua 模块。

Returns / 返回值:
- table|nil: Shared FFI module contract. / 共享 FFI 模块契约。
- table|nil: Structured loading failure. / 结构化加载失败。
]]
local function load_codekit_ffi_module()
    if CODEKIT_FFI_MODULE then
        return CODEKIT_FFI_MODULE, nil
    end
    -- Resolve the single shared module beside this entry.
    -- 解析当前入口旁唯一的共享模块。
    local module_path = vulcan.path.join(get_entry_dir(), "codekit-ffi.lua")
    -- Load without mutating package.path or guessing another module location.
    -- 在不修改 package.path 或猜测其他位置的情况下加载。
    local chunk, load_error = loadfile(module_path)
    if not chunk then
        return nil, {
            error = "codekit_ffi_module_load_failed",
            message = tostring(load_error),
            path = module_path,
        }
    end
    -- Execute and validate the exact shared module contract.
    -- 执行并校验精确的共享模块契约。
    local loaded, module_or_error = pcall(chunk)
    if not loaded or type(module_or_error) ~= "table" then
        return nil, {
            error = "codekit_ffi_module_invalid",
            message = loaded and "codekit-ffi.lua did not return a table" or tostring(module_or_error),
            path = module_path,
        }
    end
    CODEKIT_FFI_MODULE = module_or_error
    return CODEKIT_FFI_MODULE, nil
end

--[[
Validate the required repository directory argument.
校验必需的仓库目录参数。

Parameters / 参数:
- value(any): User-provided directory value. / 用户提供的目录值。
- path_helpers(table): Shared PWD path-resolution contract. / 共享 PWD 路径解析契约。
- pwd_root(string|nil): Validated project root. / 已校验的项目根路径。

Returns / 返回值:
- string|nil: Validated directory path. / 已校验目录路径。
- table|nil: Structured validation failure. / 结构化校验失败。
]]
local function validate_directory(value, path_helpers, pwd_root)
    if type(value) ~= "string" or trim(value) == "" then
        return nil, {
            error = "invalid_dir_argument",
            message = "dir must be a non-empty string",
            actual_type = type(value),
        }
    end
    -- Trimmed directory text before PWD-relative resolution.
    -- 执行 PWD 相对解析前裁剪后的目录文本。
    local directory = trim(value)
    -- Absolute directory path resolved through the shared PWD convention.
    -- 通过共享 PWD 公约解析出的绝对目录路径。
    local resolved, resolve_error = path_helpers.resolve_input_path(directory, "dir", pwd_root)
    if resolve_error then
        return nil, resolve_error
    end
    directory = resolved
    if not vulcan.fs.exists(directory) then
        return nil, {
            error = "dir_not_found",
            message = "dir does not exist",
            dir = directory,
        }
    end
    if not vulcan.fs.is_dir(directory) then
        return nil, {
            error = "dir_must_be_directory",
            message = "dir must point to an existing directory",
            dir = directory,
        }
    end
    return directory, nil
end

--[[
Validate the optional model-visible directory depth.
校验可选的模型可见目录深度。

Parameters / 参数:
- value(any): Optional depth value. / 可选深度值。

Returns / 返回值:
- number|nil: Validated integer depth. / 已校验整数深度。
- table|nil: Structured validation failure. / 结构化校验失败。
]]
local function validate_max_depth(value)
    if value == nil then
        return DEFAULT_MAX_DEPTH, nil
    end
    if type(value) ~= "number" or value % 1 ~= 0 then
        return nil, {
            error = "invalid_max_depth",
            message = "max_depth must be an integer",
            actual_type = type(value),
        }
    end
    if value < 1 or value > MAX_MAX_DEPTH then
        return nil, {
            error = "invalid_max_depth",
            message = string.format("max_depth must be between 1 and %d", MAX_MAX_DEPTH),
            actual_value = value,
        }
    end
    return value, nil
end

--[[
Validate the optional ignore-disable flag.
校验可选的禁用忽略规则标志。

Parameters / 参数:
- value(any): Optional boolean flag. / 可选布尔标志。

Returns / 返回值:
- boolean|nil: Validated boolean. / 已校验布尔值。
- table|nil: Structured validation failure. / 结构化校验失败。
]]
local function validate_noignore(value)
    if value == nil then
        return false, nil
    end
    if type(value) ~= "boolean" then
        return nil, {
            error = "invalid_noignore_argument",
            message = "noignore must be a boolean when provided",
            actual_type = type(value),
        }
    end
    return value, nil
end

--[[
Encode one structured error object into stable readable Markdown.
将一个结构化错误对象编码为稳定可读的 Markdown。

Parameters / 参数:
- error_payload(table|string): Error details to render. / 需要渲染的错误详情。

Returns / 返回值:
- string: Plain Markdown error response. / 纯 Markdown 错误响应。
]]
local function render_error(error_payload)
    -- Prefer stable JSON so nested expected paths and diagnostics remain visible.
    -- 优先使用稳定 JSON，使嵌套候选路径与诊断保持可见。
    local encoded_ok, encoded = pcall(vulcan.json.encode, error_payload)
    if not encoded_ok or type(encoded) ~= "string" then
        encoded = tostring(error_payload)
    end
    return table.concat({
        "# CodeKit Repo Map Error",
        "",
        markdown_code_span(encoded),
    }, "\n")
end

--[[
Format one language record as a compact stable metric string.
将一个语言记录格式化为紧凑稳定的指标文本。

Parameters / 参数:
- language(table): Public repository language record. / 公共仓库语言记录。

Returns / 返回值:
- string: Compact language metrics. / 紧凑语言指标。
]]
local function format_language(language)
    -- Mark Tokei inaccuracy explicitly next to the affected language.
    -- 在受影响语言旁显式标记 Tokei 不准确状态。
    local inaccurate = language.inaccurate == true and "|inaccurate" or ""
    return string.format(
        "%s [f:%s|l:%s|code:%s|comment:%s|blank:%s%s]",
        tostring(language.name or "unknown"),
        tostring(language.files or 0),
        tostring(language.lines or 0),
        tostring(language.code or 0),
        tostring(language.comments or 0),
        tostring(language.blanks or 0),
        inaccurate
    )
end

--[[
Format a compact per-directory language distribution.
格式化紧凑的目录级语言分布。

Parameters / 参数:
- languages(table): Sorted public language records. / 已排序公共语言记录。

Returns / 返回值:
- string: At most five `name=code` entries plus an omission marker. / 最多五个 `name=code` 条目与省略标记。
]]
local function format_directory_languages(languages)
    -- Keep directory rows bounded even in polyglot monorepositories.
    -- 即使在多语言 monorepo 中也保持目录行有界。
    local parts = {}
    for index, language in ipairs(languages or {}) do
        if index > 5 then
            break
        end
        table.insert(parts, string.format("%s=%s", tostring(language.name or "unknown"), tostring(language.code or 0)))
    end
    if #(languages or {}) > 5 then
        table.insert(parts, string.format("+%d", #languages - 5))
    end
    return table.concat(parts, ",")
end

--[[
Format one directory record without exposing file names.
在不暴露文件名的情况下格式化一个目录记录。

Parameters / 参数:
- directory(table): Public directory record. / 公共目录记录。

Returns / 返回值:
- string: Compact directory statistics. / 紧凑目录统计。
]]
local function format_directory(directory)
    -- Render the recursive language mix only when Tokei recognized code in the subtree.
    -- 仅在 Tokei 识别出子树代码时渲染递归语言构成。
    local language_text = format_directory_languages(directory.languages or {})
    -- Collect explicit folding and accuracy markers.
    -- 收集显式折叠与准确性标记。
    local markers = {}
    if tonumber(directory.collapsedDescendants or 0) > 0 then
        table.insert(markers, string.format("folded:%s", tostring(directory.collapsedDescendants)))
    end
    if directory.inaccurate == true then
        table.insert(markers, "inaccurate")
    end
    -- Join optional metrics without introducing empty separators.
    -- 在不产生空分隔符的情况下拼接可选指标。
    local optional = ""
    if language_text ~= "" then
        optional = optional .. "|lang:" .. language_text
    end
    if #markers > 0 then
        optional = optional .. "|" .. table.concat(markers, "|")
    end
    return string.format(
        "%s [dirs:%s/%s|files:%s/%s|known:%s|unknown:%s|bytes:%s|l:%s|code:%s|comment:%s|blank:%s%s]",
        markdown_code_span(directory.path or "."),
        tostring(directory.directDirectories or 0),
        tostring(directory.totalDirectories or 0),
        tostring(directory.directFiles or 0),
        tostring(directory.totalFiles or 0),
        tostring(directory.recognizedFiles or 0),
        tostring(directory.unrecognizedFiles or 0),
        tostring(directory.bytes or 0),
        tostring(directory.lines or 0),
        tostring(directory.code or 0),
        tostring(directory.comments or 0),
        tostring(directory.blanks or 0),
        optional
    )
end

--[[
Build a parent-indexed directory tree from the flat Rust response.
根据 Rust 扁平响应构建以父级索引的目录树。

Parameters / 参数:
- directories(table): Stable flat directory record array. / 稳定扁平目录记录数组。

Returns / 返回值:
- table: Path-keyed directory records with child arrays. / 以路径索引并包含子数组的目录记录。
- table|nil: Root directory record. / 根目录记录。
]]
local function build_directory_tree(directories)
    -- Preserve path identity exactly as returned by Rust.
    -- 精确保留 Rust 返回的路径身份。
    local by_path = {}
    for _, directory in ipairs(directories or {}) do
        directory.children = {}
        by_path[tostring(directory.path or "")] = directory
    end
    for _, directory in ipairs(directories or {}) do
        if directory.parentPath then
            -- Attach only to the exact declared parent path.
            -- 仅挂载到精确声明的父路径。
            local parent = by_path[tostring(directory.parentPath)]
            if parent then
                table.insert(parent.children, directory)
            end
        end
    end
    return by_path, by_path["."]
end

--[[
Append one directory subtree to Markdown lines.
将一个目录子树追加到 Markdown 行数组。

Parameters / 参数:
- lines(table): Mutable Markdown line array. / 可变 Markdown 行数组。
- directory(table): Current directory record. / 当前目录记录。
- depth(number): Current visible indentation depth. / 当前可见缩进深度。
]]
local function append_directory_tree(lines, directory, depth)
    -- Render tree indentation without introducing file nodes.
    -- 渲染树缩进且不引入文件节点。
    local prefix = string.rep("  ", depth) .. "- "
    table.insert(lines, prefix .. format_directory(directory))
    for _, child in ipairs(directory.children or {}) do
        append_directory_tree(lines, child, depth + 1)
    end
end

--[[
Render one successful repository-statistics response as Markdown.
将一个成功的仓库统计响应渲染为 Markdown。

Parameters / 参数:
- result(table): Successful public repository-statistics response. / 成功的公共仓库统计响应。

Returns / 返回值:
- string: Complete Repo Map Markdown. / 完整 Repo Map Markdown。
]]
local function render_repo_map(result)
    -- Read the complete repository totals once for stable formatting.
    -- 读取一次完整仓库总量以便稳定格式化。
    local totals = result.totals or {}
    -- Build the fixed overview before any potentially large directory section.
    -- 在可能较大的目录章节前构建固定概览。
    local lines = {
        "# REPO MAP",
        "",
        string.format("Root: %s", markdown_code_span(result.root or "")),
        "",
        "## OVERVIEW",
        "",
        string.format("- Directories: %s", tostring(totals.directories or 0)),
        string.format("- Files: %s", tostring(totals.files or 0)),
        string.format("- Recognized files: %s", tostring(totals.recognizedFiles or 0)),
        string.format("- Unrecognized files: %s", tostring(totals.unrecognizedFiles or 0)),
        string.format("- Bytes: %s", tostring(totals.bytes or 0)),
        string.format("- Lines: %s", tostring(totals.lines or 0)),
        string.format("- Code: %s", tostring(totals.code or 0)),
        string.format("- Comments: %s", tostring(totals.comments or 0)),
        string.format("- Blanks: %s", tostring(totals.blanks or 0)),
        string.format("- Engine: CodeKit FFI %s / Tokei %s / protocol %s", tostring(result.engine and result.engine.codekitFfi or "unknown"), tostring(result.engine and result.engine.tokei or "unknown"), tostring(result.engine and result.engine.protocol or "unknown")),
        string.format("- Scope: hidden=%s, respect-ignore=%s, follow-symlinks=%s", tostring(result.scope and result.scope.includeHidden == true), tostring(result.scope and result.scope.respectIgnore == true), tostring(result.scope and result.scope.followSymlinks == true)),
        string.format("- Rendered directories: %s/%s, max-depth=%s, truncated=%s", tostring(result.renderLimit and result.renderLimit.returnedDirectories or 0), tostring(result.renderLimit and result.renderLimit.totalDirectories or 0), tostring(result.renderLimit and result.renderLimit.maxDepth or 0), tostring(result.renderLimit and result.renderLimit.truncated == true)),
    }

    table.insert(lines, "")
    table.insert(lines, "## LANGUAGES")
    table.insert(lines, "")
    if #(result.languages or {}) == 0 then
        table.insert(lines, "- No Tokei-recognized source files.")
    else
        for _, language in ipairs(result.languages or {}) do
            table.insert(lines, "- " .. format_language(language))
        end
    end

    table.insert(lines, "")
    table.insert(lines, "## DIRECTORY TREE")
    table.insert(lines, "")
    -- Reconstruct only the returned directory records; omitted nodes remain explicit counters.
    -- 仅重建已返回目录记录；省略节点继续由显式计数表示。
    local _, root = build_directory_tree(result.directories or {})
    if root then
        append_directory_tree(lines, root, 0)
    else
        table.insert(lines, "- Root directory record is unavailable.")
    end

    if #(result.diagnostics or {}) > 0 then
        table.insert(lines, "")
        table.insert(lines, "## DIAGNOSTICS")
        table.insert(lines, "")
        for _, diagnostic in ipairs(result.diagnostics or {}) do
            table.insert(lines, "- " .. markdown_code_span(diagnostic))
        end
    end
    return table.concat(lines, "\n")
end

--[[
Emit one low-frequency Repo Map stage diagnostic without source content.
发出一条不包含源码内容的低频 Repo Map 阶段诊断。

Parameters / 参数:
- stage(string): Stable stage identifier. / 稳定阶段标识。
- status(string): Stable stage status. / 稳定阶段状态。
- details(string): Count- or state-only details. / 仅包含计数或状态的详情。
]]
local function log_stage(stage, status, details)
    if vulcan and vulcan.runtime and type(vulcan.runtime.log) == "function" then
        -- Keep logs independent from source text and language file names.
        -- 保持日志不包含源码文本与语言文件名。
        local message = string.format("codekit_repo_map stage=%s status=%s %s", tostring(stage), tostring(status), tostring(details or ""))
        pcall(vulcan.runtime.log, "info", message)
    end
end

-- Skill entry point invoked by the MCP host runtime.
-- 由 MCP 宿主运行时调用的技能入口。
return function(args)
    -- Shared path contract used to consume the host-managed PWD argument.
    -- 用于消费宿主管理 PWD 参数的共享路径契约。
    local path_helpers, path_helpers_error = load_codekit_path_module()
    if path_helpers_error then
        return render_error(path_helpers_error)
    end
    -- Validated project root injected by VulcanCode when one is available.
    -- VulcanCode 在项目根可用时注入并完成校验的项目根路径。
    local pwd_root, pwd_error = path_helpers.resolve_pwd_root(args and args.PWD)
    if pwd_error then
        return render_error(pwd_error)
    end
    -- Validate the exact single-directory input.
    -- 校验精确的单目录输入。
    local directory, directory_error = validate_directory(args and args.dir, path_helpers, pwd_root)
    if directory_error then
        return render_error(directory_error)
    end
    -- Validate the display-depth contract.
    -- 校验展示深度契约。
    local max_depth, depth_error = validate_max_depth(args and args.max_depth)
    if depth_error then
        return render_error(depth_error)
    end
    -- Validate the ignore-policy contract.
    -- 校验忽略策略契约。
    local noignore, noignore_error = validate_noignore(args and args.noignore)
    if noignore_error then
        return render_error(noignore_error)
    end

    log_stage("load", "started", "")
    -- Load the shared Lua module and unified native client.
    -- 加载共享 Lua 模块与统一原生客户端。
    local ffi_module, module_error = load_codekit_ffi_module()
    if not ffi_module then
        return render_error(module_error)
    end
    -- Resolve and validate the single native library instance.
    -- 解析并校验唯一原生动态库实例。
    local client, client_error = ffi_module.load_client()
    if not client then
        return render_error(client_error)
    end

    log_stage("scan", "started", string.format("max_depth=%d respect_ignore=%s", max_depth, tostring(not noignore)))
    -- Execute one complete repository-statistics request without language filters.
    -- 执行一次不包含语言过滤的完整仓库统计请求。
    local result, result_error = ffi_module.call_repo_stats(client, {
        root = directory,
        maxDepth = max_depth,
        includeHidden = true,
        respectIgnore = not noignore,
        maxRenderedDirectories = MAX_RENDERED_DIRECTORIES,
    })
    if not result then
        log_stage("scan", "failed", tostring(result_error and result_error.error))
        return render_error(result_error)
    end

    log_stage(
        "scan",
        "completed",
        string.format(
            "directories=%s files=%s recognized=%s unknown=%s",
            tostring(result.totals and result.totals.directories or 0),
            tostring(result.totals and result.totals.files or 0),
            tostring(result.totals and result.totals.recognizedFiles or 0),
            tostring(result.totals and result.totals.unrecognizedFiles or 0)
        )
    )
    return render_repo_map(result), vulcan.runtime.overflow_type.page
end
