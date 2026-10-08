--[[
codekit-rg
Preserve ripgrep text matches and enrich indexed lines with codekit-ast-detail owner context.
保留 ripgrep 文本命中，并通过 codekit-ast-detail 为索引范围内的行补充归属上下文。
]]

-- 工具常量 / Tool constants for rg execution and response shaping.
local RG_TIMEOUT_MS = 30000
local MAX_MATCH_LINES_PER_SYMBOL = 12
-- Source-line preview budget, independent of the host's total-result paging budget.
-- 源码行预览预算，独立于宿主的结果总量分页预算。
local MAX_RG_LINE_PREVIEW_BYTES = 4096
-- Context retained on each side of every match in an oversized source line.
-- 超长源码行中每个命中两侧保留的上下文字节数。
local RG_MATCH_CONTEXT_BYTES = 128
-- Maximum size of one file admitted to synchronous AST enrichment.
-- 单个文件进入同步 AST 增强阶段时允许的最大字节数。
local MAX_AST_ENRICHMENT_FILE_BYTES = 2 * 1024 * 1024
-- Maximum aggregate size admitted to synchronous AST enrichment for one RG call.
-- 单次 RG 调用进入同步 AST 增强阶段时允许的文件总字节数上限。
local MAX_AST_ENRICHMENT_TOTAL_BYTES = 8 * 1024 * 1024
-- Maximum number of files admitted to synchronous AST enrichment for one RG call.
-- 单次 RG 调用进入同步 AST 增强阶段时允许的文件数量上限。
local MAX_AST_ENRICHMENT_FILES = 100
local LFS_MODULE = nil
local SHARED_LENGTH_HELPERS = nil

-- 缓存的 codekit-ast-detail 助手集合 / Cached codekit-ast-detail helper bundle extracted from the existing skill entry.
local AST_RUNTIME_HELPERS = nil

-- 基础字符串工具 / Basic string helpers shared by validation, parsing, and rendering.
local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function starts_with(text, prefix)
    return tostring(text or ""):sub(1, #prefix) == prefix
end

local function split_lines(content)
    local normalized = tostring(content or ""):gsub("\r\n", "\n")
    local lines = {}
    if normalized == "" then
        return lines
    end
    for line in (normalized .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end
    return lines
end

--[[
Emit one low-frequency runtime diagnostic at a stable CodeKit RG stage boundary.
在稳定的 CodeKit RG 阶段边界发送一条低频运行时诊断。

Parameters / 参数:
- stage(string): Stable stage identifier.
  稳定的阶段标识。
- status(string): Stage state such as started or completed.
  started 或 completed 等阶段状态。
- details(string|nil): Non-sensitive counts or reason fields.
  非敏感的计数或原因字段。

Returns / 返回:
- nil: Diagnostic failures never change tool semantics.
  诊断失败绝不改变工具语义。
]]
local function log_rg_stage(stage, status, details)
    -- Stable diagnostic payload that excludes search expressions and source text.
    -- 不包含搜索表达式和源码文本的稳定诊断载荷。
    local message = string.format(
        "tool=vulcan_codekit_rg stage=%s status=%s%s",
        tostring(stage),
        tostring(status),
        details and (" " .. tostring(details)) or ""
    )
    pcall(vulcan.runtime.log, "info", message)
end

--[[
浅拷贝数组，避免在树渲染或结果拼装时直接改写原始列表。
Create a shallow array copy so tree rendering and result assembly do not mutate the original list in place.

参数 / Parameters:
- items(table|nil): 待复制的数组 / Array to clone.

返回 / Returns:
- table: 浅拷贝后的新数组 / Shallow-copied array.
]]
local function clone_array(items)
    local copied = {}
    for _, item in ipairs(items or {}) do
        table.insert(copied, item)
    end
    return copied
end

--[[
统一格式化结构范围，输出 `Lx-y` 或 `Lx` 形式，便于结果直接定位到代码区间。
Format structural ranges into `Lx-y` or `Lx` so the output can be used as an immediate line anchor.

参数 / Parameters:
- start_line(number): 起始行号 / 1-based start line.
- end_line(number): 结束行号 / 1-based end line.

返回 / Returns:
- string: 规范化后的行号范围文本 / Normalized line-span text.
]]
local function format_line_span(start_line, end_line)
    local normalized_start = tonumber(start_line) or 0
    local normalized_end = tonumber(end_line) or normalized_start
    if normalized_end < normalized_start then
        normalized_end = normalized_start
    end
    if normalized_start <= 0 then
        return "L?"
    end
    if normalized_start == normalized_end then
        return string.format("L%d", normalized_start)
    end
    return string.format("L%d-%d", normalized_start, normalized_end)
end

--[[
获取宿主注入的当前 skill 目录。
Resolve the current skill directory injected by the host.

参数 / Parameters:
- 无 / None.

返回 / Returns:
- string: 当前 skill 目录 / Current skill directory.
]]
local function get_skill_dir()
    return tostring(vulcan.context.skill_dir or ".")
end

local function get_entry_dir()
    return tostring(vulcan.context.entry_dir or get_skill_dir())
end

local function get_entry_file()
    return tostring(vulcan.context.entry_file or vulcan.path.join(get_entry_dir(), "codekit-rg.lua"))
end

--[[
解析当前运行时可用的宿主进程执行函数，仅接受正式节点 `vulcan.process.exec`。
Resolve the host-side process execution function and accept only the formal node `vulcan.process.exec`.

返回 / Returns:
- function|nil: 可调用的宿主执行函数；若宿主未注入则返回 nil。
  Callable host execution function, or nil when the host did not inject one.
]]
local function get_host_exec_function()
    if type(vulcan) ~= "table" then
        return nil
    end
    if type(vulcan.process) == "table" and type(vulcan.process.exec) == "function" then
        return vulcan.process.exec
    end
    return nil
end

--[[
Return the normalized platform key used by LuaSkills dependency installation.
返回 LuaSkills 依赖安装使用的标准平台键。
]]
local function current_platform_key()
    local os_info = vulcan.os.info() or {}
    local architecture = trim((os_info.arch or os_info.architecture or "")):lower()
    local os_name = trim((os_info.os or "")):lower()

    if os_name == "windows" then
        if architecture == "arm64" or architecture == "aarch64" then
            return "windows-arm64"
        end
        return "windows-x64"
    end

    if os_name == "macos" or os_name == "darwin" or os_name == "osx" then
        if architecture == "arm64" or architecture == "aarch64" then
            return "macos-arm64"
        end
        return "macos-x64"
    end

    if architecture == "arm64" or architecture == "aarch64" then
        return "linux-arm64"
    end
    return "linux-x64"
end

--[[
Return the host-injected tool dependency root for the current skill.
返回宿主为当前 skill 注入的工具依赖根目录。
]]
local function get_tool_dependency_root()
    return trim(vulcan and vulcan.deps and vulcan.deps.tools_path or "")
end

--[[
Build one tool binary path from the injected dependency root, dependency name, version, and executable name.
基于注入的依赖根目录、依赖名、版本号与程序名构造工具二进制路径。
]]
local function build_tool_binary_path(dependency_name, version, executable_name)
    local tools_root = get_tool_dependency_root()
    if tools_root == "" then
        return ""
    end
    return vulcan.path.join(
        tools_root,
        tostring(dependency_name or ""),
        tostring(version or ""),
        current_platform_key(),
        "bin",
        tostring(executable_name or "")
    )
end

--[[
懒加载共享预算模块，让 rg/detail/tree 复用同一套 MCP 输出/读取预算映射。
Lazily load the shared budget module so rg/detail/tree reuse the same MCP output/read budget mapping.
]]
local function load_shared_length_helpers()
    if SHARED_LENGTH_HELPERS then
        return SHARED_LENGTH_HELPERS, nil
    end

    local helper_path = vulcan.path.join(get_entry_dir(), "shared_length.lua")
    local chunk, load_error = loadfile(helper_path)
    if not chunk then
        return nil, {
            error = "shared_length_load_failed",
            message = tostring(load_error),
            path = helper_path,
        }
    end

    local ok, helpers = pcall(chunk)
    if not ok or type(helpers) ~= "table" then
        return nil, {
            error = "shared_length_invalid",
            message = ok and "shared_length.lua did not return a table" or tostring(helpers),
            path = helper_path,
        }
    end

    SHARED_LENGTH_HELPERS = helpers
    return SHARED_LENGTH_HELPERS, nil
end

--[[
在单次工具调用开始时初始化当前客户端的 RG 预算。
Initialize the current RG budget at the start of each tool call.
]]
local function initialize_rg_client_budget()
    local helpers, helper_error = load_shared_length_helpers()
    if helper_error then
        return nil, helper_error
    end
    return helpers.initialize_client_budget(vulcan)
end

--[[
通过 `debug.getupvalue` 从现有 `codekit-ast-detail` 入口中提取内部助手函数，避免复制一整套 AST 解析实现。
Extract internal helper functions from the existing `codekit-ast-detail` entry with `debug.getupvalue` to avoid duplicating the full AST parsing pipeline.

参数 / Parameters:
- fn(function): 待检查 upvalue 的函数 / Function whose upvalues will be inspected.
- name(string): 目标 upvalue 名称 / Target upvalue name.

返回 / Returns:
- any|nil: 命中的 upvalue 值；未找到时返回 nil。
  Matched upvalue value, or nil when not found.
]]
local function extract_upvalue_by_name(fn, name)
    local index = 1
    while true do
        local upvalue_name, upvalue_value = debug.getupvalue(fn, index)
        if not upvalue_name then
            return nil
        end
        if upvalue_name == name then
            return upvalue_value
        end
        index = index + 1
    end
end

--[[
懒加载 `codekit-ast-detail` 内部助手，确保 `codekit-rg` 与现有 AST 规则、文件收集和结构归一化逻辑保持一致。
Lazily load internal `codekit-ast-detail` helpers so `codekit-rg` stays aligned with the existing AST rules, file collection logic, and symbol normalization flow.

参数 / Parameters:
- 无 / None.

返回 / Returns:
- table|nil: 提取成功后的助手函数集合 / Extracted helper bundle on success.
- table|nil: 加载失败时的结构化错误对象 / Structured error object on failure.
]]
local function load_ast_runtime_helpers()
    if AST_RUNTIME_HELPERS then
        return AST_RUNTIME_HELPERS, nil
    end

    local ast_entry_path = vulcan.path.join(get_entry_dir(), "codekit-ast-detail.lua")
    local chunk, load_error = loadfile(ast_entry_path)
    if not chunk then
        return nil, {
            error = "codekit_ast_entry_load_failed",
            message = tostring(load_error),
            path = ast_entry_path,
        }
    end

    local ok, ast_entry = pcall(chunk)
    if not ok or type(ast_entry) ~= "function" then
        return nil, {
            error = "codekit_ast_entry_invalid",
            message = ok and "codekit-ast-detail entry did not return a function" or tostring(ast_entry),
            path = ast_entry_path,
        }
    end

    local helpers = {
        -- Shared loader required by RG PWD resolution.
        -- RG 的 PWD 解析所需共享加载器。
        load_codekit_path_module = extract_upvalue_by_name(ast_entry, "load_codekit_path_module"),
        validate_extension_argument = extract_upvalue_by_name(ast_entry, "validate_extension_argument"),
        validate_noignore_argument = extract_upvalue_by_name(ast_entry, "validate_noignore_argument"),
        collect_files = extract_upvalue_by_name(ast_entry, "collect_files"),
        find_binary = extract_upvalue_by_name(ast_entry, "find_binary"),
        run_language_scan = extract_upvalue_by_name(ast_entry, "run_language_scan"),
        normalize_symbol = extract_upvalue_by_name(ast_entry, "normalize_symbol"),
        deduplicate_symbols = extract_upvalue_by_name(ast_entry, "deduplicate_symbols"),
        build_symbol_tree = extract_upvalue_by_name(ast_entry, "build_symbol_tree"),
    }

    for helper_name, helper_value in pairs(helpers) do
        if type(helper_value) ~= "function" then
            return nil, {
                error = "codekit_ast_helper_missing",
                message = "required helper missing from codekit-ast-detail runtime",
                helper = helper_name,
                path = ast_entry_path,
            }
        end
    end

    AST_RUNTIME_HELPERS = helpers
    return AST_RUNTIME_HELPERS, nil
end

--[[
校验目录参数，要求非空字符串且必须是已存在目录。
Validate the directory argument. It must be a non-empty string pointing to an existing directory.

参数 / Parameters:
- value(any): 用户传入的目录参数 / User-provided directory argument.
- path_helpers(table): 共享 PWD 路径解析契约 / Shared PWD path-resolution contract.
- pwd_root(string|nil): 已校验的项目根路径 / Validated project root.

返回 / Returns:
- string|nil: 规范化后的目录路径 / Normalized directory path.
- table|nil: 参数非法时返回结构化错误对象 / Structured error object when invalid.
]]
local function validate_directory_argument(value, path_helpers, pwd_root)
    if type(value) ~= "string" or trim(value) == "" then
        return nil, {
            error = "invalid_dir_argument",
            message = "dir must be a non-empty string",
            actual_type = type(value),
        }
    end

    -- Trimmed directory text before PWD-relative resolution.
    -- 执行 PWD 相对解析前裁剪后的目录文本。
    local normalized = trim(value)
    -- Absolute directory path resolved through the shared PWD convention.
    -- 通过共享 PWD 公约解析出的绝对目录路径。
    local resolved, resolve_error = path_helpers.resolve_input_path(normalized, "dir", pwd_root)
    if resolve_error then
        return nil, resolve_error
    end
    normalized = resolved
    if not vulcan.fs.exists(normalized) then
        return nil, {
            error = "dir_not_found",
            message = "dir does not exist",
            dir = normalized,
        }
    end
    if not vulcan.fs.is_dir(normalized) then
        return nil, {
            error = "dir_must_be_directory",
            message = "dir must point to an existing directory",
            dir = normalized,
        }
    end
    return normalized, nil
end

--[[
校验 ripgrep 正则参数，要求非空字符串。
Validate the ripgrep regex argument. It must be a non-empty string.

参数 / Parameters:
- value(any): 用户传入的 rg 正则 / User-provided rg regular expression.

返回 / Returns:
- string|nil: 规范化后的 rg 正则 / Normalized rg pattern.
- table|nil: 参数非法时返回结构化错误对象 / Structured error object when invalid.
]]
local function validate_rg_pattern_argument(value)
    if type(value) ~= "string" or trim(value) == "" then
        return nil, {
            error = "invalid_rg_pattern_argument",
            message = "rg_pattern must be a non-empty string",
            actual_type = type(value),
        }
    end
    return trim(value), nil
end

-- Validate the regex engine argument and keep Rust regex as the stable default.
-- 校验 regex_engine 参数，并保持 Rust regex 作为稳定默认值。
local function validate_regex_engine_argument(value)
    if value == nil then
        return "rust", nil
    end
    if type(value) ~= "string" then
        return nil, {
            error = "invalid_regex_engine_argument",
            message = "regex_engine must be either rust or pcre2",
            actual_type = type(value),
        }
    end
    local normalized = trim(value):lower()
    if normalized == "rust" or normalized == "pcre2" then
        return normalized, nil
    end
    return nil, {
        error = "invalid_regex_engine_argument",
        message = "regex_engine must be either rust or pcre2",
        regex_engine = tostring(value),
    }
end

--[[
显式拒绝 `export_md_path` 参数，避免调用方误以为 `codekit-rg` 仍支持导出到指定目录。
Explicitly reject the `export_md_path` argument so callers do not assume `codekit-rg` still supports exporting to a chosen path.
]]
local function validate_export_md_absence(value)
    if value ~= nil then
        return {
            error = "export_md_path_not_supported",
            message = "codekit-rg no longer supports the export_md_path argument",
        }
    end
    return nil
end

local function get_lfs_module()
    if LFS_MODULE ~= nil then
        return LFS_MODULE
    end
    local ok, module = pcall(require, "lfs")
    if ok then
        LFS_MODULE = module
    else
        LFS_MODULE = false
    end
    return LFS_MODULE
end

local function get_parent_directory(path)
    local normalized = tostring(path or ""):gsub("[\\/]+$", "")
    local parent = normalized:match("^(.*)[\\/][^\\/]+$")
    if not parent or parent == normalized then
        return nil
    end
    return parent
end

local function append_path_segment(current, segment)
    if current == "" then
        return segment
    end
    if current == "/" then
        return "/" .. segment
    end
    if current:sub(-1) == "/" then
        return current .. segment
    end
    return current .. "/" .. segment
end

--[[
在 LuaFileSystem 不可用时，回退到宿主 `vulcan.process.exec` 递归创建目录，保证大结果落盘与 Markdown 导出仍可执行。
Fall back to host-side `vulcan.process.exec` recursive directory creation when LuaFileSystem is unavailable so large-result spilling and Markdown export still work.
]]
local function ensure_directory_via_exec(directory_path)
    local host_exec = get_host_exec_function()
    if type(host_exec) ~= "function" then
        return false, {
            error = "directory_creation_failed",
            message = "neither LuaFileSystem nor host process exec is available for directory creation",
            path = directory_path,
        }
    end

    local os_info = vulcan.os.info()
    local request
    if os_info and os_info.os == "windows" then
        request = {
            program = "powershell.exe",
            args = {
                "-NoProfile",
                "-Command",
                string.format("New-Item -ItemType Directory -Force -Path '%s' | Out-Null", tostring(directory_path):gsub("'", "''")),
            },
            timeout_ms = 10000,
        }
    else
        request = {
            program = "mkdir",
            args = { "-p", directory_path },
            timeout_ms = 10000,
        }
    end

    local ok, result = pcall(host_exec, request)
    if not ok or type(result) ~= "table" then
        return false, {
            error = "directory_creation_failed",
            message = ok and "unexpected exec result" or tostring(result),
            path = directory_path,
        }
    end
    if result.error or result.timed_out or result.success == false then
        return false, {
            error = "directory_creation_failed",
            message = trim(result.error or result.stderr or "mkdir failed"),
            path = directory_path,
        }
    end
    if vulcan.fs.exists(directory_path) and vulcan.fs.is_dir(directory_path) then
        return true, nil
    end
    return false, {
        error = "directory_creation_failed",
        message = "directory was not created",
        path = directory_path,
    }
end

local function ensure_directory(directory_path)
    local normalized = trim(directory_path or "")
    if normalized == "" then
        return false, {
            error = "directory_creation_failed",
            message = "directory path is empty",
        }
    end
    if vulcan.fs.exists(normalized) then
        if vulcan.fs.is_dir(normalized) then
            return true, nil
        end
        return false, {
            error = "directory_creation_failed",
            message = "target path already exists as a file",
            path = normalized,
        }
    end

    local lfs = get_lfs_module()
    if not lfs then
        return ensure_directory_via_exec(normalized)
    end

    local path_text = tostring(normalized):gsub("\\", "/")
    local prefix = ""
    if path_text:match("^%a:/") then
        prefix = path_text:sub(1, 3)
        path_text = path_text:sub(4)
    elseif starts_with(path_text, "/") then
        prefix = "/"
        path_text = path_text:sub(2)
    end

    local current = prefix
    for segment in path_text:gmatch("[^/]+") do
        current = append_path_segment(current, segment)
        if not vulcan.fs.exists(current) then
            local ok, mkdir_error = lfs.mkdir(current)
            if not ok then
                return false, {
                    error = "directory_creation_failed",
                    message = tostring(mkdir_error or "mkdir failed"),
                    path = current,
                }
            end
        elseif not vulcan.fs.is_dir(current) then
            return false, {
                error = "directory_creation_failed",
                message = "path exists but is not a directory",
                path = current,
            }
        end
    end
    return true, nil
end

local function shallow_copy_object(source)
    local copied = {}
    for key, value in pairs(source or {}) do
        copied[key] = value
    end
    return copied
end

--[[
Locate the `rg` executable from the host-injected dependency root instead of guessing the host directory layout.
从宿主注入的依赖根目录定位 `rg` 可执行文件，而不是猜测宿主目录布局。

参数 / Parameters:
- 无 / None.

返回 / Returns:
- string|nil: `rg` 可执行文件完整路径 / Full `rg` executable path.
- table|nil: 未找到时返回结构化错误对象 / Structured error object when not found.
]]
local function find_rg_binary()
    local executable_name = vulcan.os.info().os == "windows" and "rg.exe" or "rg"
    local full_path = build_tool_binary_path("rg", "14.1.1", executable_name)
    if vulcan.fs.exists(full_path) then
        return full_path, nil
    end
    return nil, {
        error = "rg_binary_not_found",
        message = "ripgrep binary not found in the current skill dependency root",
        expected_path = full_path,
    }
end

-- rg 参数与输出解析 / Build rg commands and parse the newline-delimited JSON stream.
local function quote_argument(value)
    return '"' .. tostring(value or ""):gsub('"', '\\"') .. '"'
end

local function build_rg_arguments(target_directory, extension_filter, rg_pattern, ignore_enabled, regex_engine)
    local arguments = { "--json", "--line-number", "--color=never", "-e", rg_pattern, target_directory }
    if regex_engine == "pcre2" then
        table.insert(arguments, 1, "--pcre2")
    end
    if ignore_enabled == false then
        table.insert(arguments, "--hidden")
        table.insert(arguments, "--no-ignore")
    end
    local extensions = {}
    if type(extension_filter) == "table" then
        for extension_name in pairs(extension_filter) do
            table.insert(extensions, extension_name)
        end
    end
    table.sort(extensions)
    for _, extension_name in ipairs(extensions) do
        table.insert(arguments, 1, "*." .. extension_name)
        table.insert(arguments, 1, "--glob")
    end
    return arguments
end

local function build_rg_command(rg_binary_path, arguments)
    local quoted_arguments = { quote_argument(rg_binary_path) }
    for _, argument in ipairs(arguments or {}) do
        table.insert(quoted_arguments, quote_argument(argument))
    end
    return table.concat(quoted_arguments, " ") .. " 2>&1"
end

--[[
将路径归一化为稳定的命中表键，消除 Windows 分隔符与大小写差异。
Normalize a path into a stable hit-table key, removing Windows separator and case differences.

参数 / Parameters:
- path(string): `rg`、文件收集器或 AST 扫描器返回的路径 / Path returned by rg, the file collector, or the AST scanner.

返回 / Returns:
- string: 可安全用于命中表关联的规范路径键 / Canonical path key safe for hit-table correlation.
]]
local function normalize_path_key(path)
    local normalized = tostring(path or ""):gsub("\\", "/"):gsub("/+", "/")
    if vulcan.os.info().os == "windows" then
        normalized = normalized:lower()
    end
    return normalized
end

--[[
把 `rg` 返回的相对路径解析到 LuaSkills 当前工作目录，确保它能与 AST 的绝对文件路径关联。
Resolve an rg-relative path against the LuaSkills working directory so it correlates with absolute AST file paths.

参数 / Parameters:
- path(string): `rg --json` 返回的文件路径 / File path returned by rg --json.

返回 / Returns:
- string: 原本就是绝对路径时保持不变，否则返回基于运行时工作目录的绝对路径 / Original absolute path or an absolute path based on the runtime working directory.
]]
local function resolve_rg_hit_path(path)
    local normalized = tostring(path or "")
    if normalized == ""
        or normalized:match("^%a:[/\\]") ~= nil
        or starts_with(normalized, "\\\\")
        or starts_with(normalized, "/")
    then
        return normalized
    end

    local runtime_cwd = vulcan and vulcan.runtime and vulcan.runtime.cwd
    if type(runtime_cwd) ~= "function" then
        return normalized
    end
    local ok, current_directory = pcall(runtime_cwd)
    current_directory = ok and trim(current_directory) or ""
    if current_directory == "" then
        return normalized
    end
    return vulcan.path.join(current_directory, normalized)
end

--[[
调用 ripgrep，并优先使用宿主暴露的 `vulcan.process.exec`，缺失时回退到 `io.popen`。
Execute ripgrep, preferring the host-provided `vulcan.process.exec` and falling back to `io.popen` when unavailable.

参数 / Parameters:
- rg_binary_path(string): `rg` 可执行文件完整路径 / Full path to the `rg` executable.
- arguments(table): 传给 `rg` 的参数数组 / Argument array passed to `rg`.

返回 / Returns:
- string|nil: 标准输出文本 / Standard output text.
- string|nil: 标准错误文本 / Standard error text.
- table|nil: 执行失败时的结构化错误对象 / Structured error object on failure.
]]
local function run_rg_command(rg_binary_path, arguments)
    local host_exec = get_host_exec_function()
    if type(host_exec) == "function" then
        local ok, result = pcall(host_exec, {
            program = rg_binary_path,
            args = arguments,
            encoding = "utf-8",
            timeout_ms = RG_TIMEOUT_MS,
        })
        if ok and type(result) == "table" then
            -- ripgrep 退出码 1 表示“无匹配”，不是执行失败。这里显式转成空结果，避免上层把它误报成 rg_exec_failed。
            -- ripgrep exit code 1 means "no matches", not an execution failure. Convert it into an empty successful result here.
            if (not result.timed_out) and tonumber(result.code) == 1 then
                return tostring(result.stdout or ""), tostring(result.stderr or ""), nil
            end
            if result.error then
                return nil, nil, {
                    error = "rg_exec_failed",
                    message = tostring(result.error),
                    stderr = trim(result.stderr or ""),
                }
            end
            if result.timed_out then
                return nil, nil, {
                    error = "rg_timed_out",
                    message = "ripgrep execution timed out",
                }
            end
            return tostring(result.stdout or ""), tostring(result.stderr or ""), nil
        end
        if not ok then
            return nil, nil, {
                error = "rg_exec_failed",
                message = tostring(result),
            }
        end
    end

    local handle = io.popen(build_rg_command(rg_binary_path, arguments))
    if not handle then
        return nil, nil, {
            error = "rg_spawn_failed",
            message = "failed to spawn ripgrep process",
        }
    end
    local output = handle:read("*a")
    handle:close()
    return output, "", nil
end

--[[
解析 `rg --json` 的输出，只保留 `match` 事件，并按文件聚合命中行信息。
Parse `rg --json` output, keeping only `match` events and grouping line hits by file.

参数 / Parameters:
- output(string): `rg --json` 的 stdout 文本 / Stdout text from `rg --json`.
- stderr_text(string|nil): ripgrep 的 stderr 文本 / Stderr text from ripgrep.

返回 / Returns:
- table: 按文件聚合的命中结果 / Hits grouped by file.
- table: 诊断信息数组 / Diagnostic message array.
]]
local function parse_rg_json_output(output, stderr_text)
    local hits_by_file = {}
    local diagnostics = {}

    for line_index, raw_line in ipairs(split_lines(output or "")) do
        local current = trim(raw_line)
        if current ~= "" then
            local decode_ok, decoded_or_error = pcall(vulcan.json.decode, current)
            if not decode_ok then
                table.insert(
                    diagnostics,
                    string.format("rg_json_decode_error[L%d]: %s", line_index, tostring(decoded_or_error))
                )
            else
                local decoded = decoded_or_error
                if type(decoded) ~= "table" then
                    table.insert(
                        diagnostics,
                        string.format(
                            "rg_json_decode_error[L%d]: decoded value is %s instead of table",
                            line_index,
                            type(decoded)
                        )
                    )
                elseif decoded.type == "match" then
                    local data = decoded.data or {}
                    local file_path = trim(((data.path or {}).text) or "")
                    local line_number = tonumber(data.line_number) or 0
                    local line_text = tostring(((data.lines or {}).text) or ""):gsub("[\r\n]+$", "")
                    if file_path ~= "" and line_number > 0 then
                        hits_by_file[file_path] = hits_by_file[file_path] or {}
                        table.insert(hits_by_file[file_path], {
                            line = line_number,
                            text = line_text,
                            submatches = (data.submatches or {}),
                        })
                    end
                end
            end
        end
    end

    for _, diagnostic_line in ipairs(split_lines(stderr_text or "")) do
        local normalized = trim(diagnostic_line)
        if normalized ~= "" then
            table.insert(diagnostics, normalized)
        end
    end

    return hits_by_file, diagnostics
end

-- AST 命中归属分析 / Map ripgrep hit lines back to the most relevant AST structures.
local function attach_parent_links(symbols, parent_symbol)
    for _, symbol in ipairs(symbols or {}) do
        symbol.parent = parent_symbol
        attach_parent_links(symbol.children or {}, symbol)
    end
end

local function find_deepest_symbol_for_line(symbols, line_number)
    for _, symbol in ipairs(symbols or {}) do
        if symbol.start_line <= line_number and symbol.end_line >= line_number then
            local child_match = find_deepest_symbol_for_line(symbol.children or {}, line_number)
            return child_match or symbol
        end
    end
    return nil
end

local function is_function_like(symbol)
    return symbol and (symbol.kind == "function" or symbol.kind == "method")
end

--[[
根据命中行决定最终展示目标。
若命中的是声明起始行，则展示声明对应结构；否则优先回退到最近的函数/方法结构。
Decide the final display target from a matched line.
If the hit lands on a declaration start line, show that declaration’s structure; otherwise prefer the nearest enclosing function/method.

参数 / Parameters:
- matched_symbol(table|nil): 命中行所在的最深 AST 结构 / Deepest AST symbol containing the matched line.
- line_number(number): 当前命中行号 / Current matched line number.

返回 / Returns:
- table|nil: 最终应展示的结构节点 / Final structure node to display.
- string: 命中模式标记，取值如 `declaration` 或 `body`。
  Hit mode marker such as `declaration` or `body`.
]]
local function resolve_display_symbol(matched_symbol, line_number)
    local cursor = matched_symbol
    while cursor do
        if cursor.start_line == line_number then
            return cursor, "declaration"
        end
        cursor = cursor.parent
    end

    cursor = matched_symbol
    while cursor do
        if is_function_like(cursor) then
            return cursor, "body"
        end
        cursor = cursor.parent
    end

    return matched_symbol, "body"
end

local function mark_symbol_chain(symbol)
    local cursor = symbol
    while cursor do
        cursor.__vmcp_rg_include = true
        cursor = cursor.parent
    end
end

local function mark_symbol_subtree(symbol)
    if not symbol then
        return
    end
    symbol.__vmcp_rg_include = true
    for _, child in ipairs(symbol.children or {}) do
        mark_symbol_subtree(child)
    end
end

--[[
Attach one complete RG record to an owner, deduplicating repeated line records.
将完整 RG 记录附加到归属符号，并去除重复的行记录。
Parameters: symbol is the AST owner; match_item contains the line, text and submatch offsets.
参数：symbol 为 AST 归属；match_item 包含行号、文本和子命中字节偏移。
Returns nothing; updates only the owner's rendering annotations.
无返回值；仅更新归属符号的渲染标记。
]]
local function append_symbol_match_line(symbol, match_item)
    symbol.__vmcp_rg_line_matches = symbol.__vmcp_rg_line_matches or {}
    -- Keep the original RG record so byte offsets survive AST owner assignment.
    -- 保留原始 RG 记录，使字节偏移在分配 AST 归属后仍然存在。
    local dedupe_key = tostring(match_item.line) .. "::" .. tostring(match_item.text)
    symbol.__vmcp_rg_line_match_keys = symbol.__vmcp_rg_line_match_keys or {}
    if symbol.__vmcp_rg_line_match_keys[dedupe_key] then
        return
    end
    symbol.__vmcp_rg_line_match_keys[dedupe_key] = true
    table.insert(symbol.__vmcp_rg_line_matches, match_item)
end

local function clear_symbol_marks(symbols)
    for _, symbol in ipairs(symbols or {}) do
        symbol.__vmcp_rg_include = nil
        symbol.__vmcp_rg_line_matches = nil
        symbol.__vmcp_rg_line_match_keys = nil
        clear_symbol_marks(symbol.children or {})
    end
end

local function sort_symbol_match_lines(symbols)
    for _, symbol in ipairs(symbols or {}) do
        if symbol.__vmcp_rg_line_matches then
            table.sort(symbol.__vmcp_rg_line_matches, function(left, right)
                if left.line ~= right.line then
                    return left.line < right.line
                end
                return left.text < right.text
            end)
        end
        sort_symbol_match_lines(symbol.children or {})
    end
end

local function format_symbol_label(symbol)
    local signature = trim(symbol and symbol.signature or "")
    local display_text = signature ~= "" and signature or trim(string.format("%s %s", symbol and symbol.kind or "unknown", symbol and symbol.name or "unknown"))
    return string.format("%s [%s]", display_text, format_line_span(symbol and symbol.start_line, symbol and symbol.end_line))
end

--[[
把符号链格式化为单行扁平头部，使用 `@ 父结构 :: 子结构` 形式表达层级，便于模型快速感知命中上下文。
Format a symbol chain into a single flat header line using `@ parent :: child` so models can recognize the hit context without tree prefixes.

参数 / Parameters:
- symbol_chain(table): 从最外层结构到当前命中结构的符号链 / Symbol chain from the outermost structure to the current matched structure.

返回 / Returns:
- string: 扁平化后的结构头文本 / Flattened structural header text.
]]
local function format_symbol_chain_label(symbol_chain)
    local parts = {}
    for _, symbol in ipairs(symbol_chain or {}) do
        table.insert(parts, format_symbol_label(symbol))
    end
    return "@ " .. table.concat(parts, " :: ")
end

--[[
Expand a byte window to whole UTF-8 characters without scanning the full source line.
将字节窗口向外扩展到完整 UTF-8 字符，无需扫描整条源码行。
Parameters: text is RG UTF-8 text; first and last are zero-based, end-exclusive offsets.
参数：text 为 RG UTF-8 文本；first 和 last 为从零开始、右侧不包含的偏移。
Returns a clamped window with first and last offsets; each edge expands by at most three bytes.
返回夹定范围后的 first 和 last 窗口；每侧最多扩展三个字节。
]]
local function rg_utf8_window(text, first, last)
    first = math.max(0, math.min(#text, first))
    last = math.max(first, math.min(#text, last))
    while first > 0 and first < #text and text:byte(first + 1) >= 128 and text:byte(first + 1) < 192 do
        first = first - 1
    end
    while last < #text and text:byte(last + 1) >= 128 and text:byte(last + 1) < 192 do
        last = last + 1
    end
    return { first = first, last = last }
end

--[[
Append a bounded source excerpt with its original offsets and covered match indexes.
附加有界源码片段，并标记原始偏移和所覆盖的命中序号。
Parameters: lines receives output; text is the original line; window is a UTF-8-aligned range.
参数：lines 接收输出；text 为原始行；window 为按 UTF-8 对齐的范围。
Parameters: first_match and last_match identify the inclusive RG submatch index range.
参数：first_match 和 last_match 表示包含两端的 RG 子命中序号范围。
Returns nothing; ellipses mark source context omitted outside this excerpt.
无返回值；省略号标记片段之外未展示的源码上下文。
]]
local function append_rg_excerpt(lines, text, window, first_match, last_match)
    table.insert(lines, string.format(
        "  [matches %d-%d; bytes [%d,%d)]: %s%s%s",
        first_match, last_match, window.first, window.last,
        window.first > 0 and "..." or "",
        text:sub(window.first + 1, window.last),
        window.last < #text and "..." or ""
    ))
end

--[[
Render a matching line, bounding oversized previews while retaining every RG occurrence.
渲染命中行，限制超长预览，同时保留每个 RG 命中。
Parameters: match_item contains the source line number, UTF-8 text and RG submatch offsets.
参数：match_item 包含源码行号、UTF-8 文本和 RG 子命中字节偏移。
Returns Markdown with unchanged short lines or explicitly annotated long-line excerpts.
返回 Markdown；短行维持原样，超长行使用带明确说明的片段。
]]
local function format_match_label(match_item)
    -- Measure the original line before trimming so indentation cannot hide an oversized record.
    -- 在去除首尾空白前度量原始行，避免缩进掩盖超长记录。
    local text = match_item.text
    if #text <= MAX_RG_LINE_PREVIEW_BYTES then
        return string.format("L%d: %s", match_item.line, trim(text))
    end
    -- These offsets come from rg --json; never guess a match location from the search expression.
    -- 偏移来自 rg --json；绝不根据搜索表达式猜测命中位置。
    local submatches = match_item.submatches
    assert(type(submatches) == "table" and #submatches > 0, "long RG line requires submatch offsets")
    -- Each excerpt remains a short physical output line so the host can page large result sets.
    -- 每个片段保持为较短的物理输出行，使宿主能够为大量结果分页。
    local lines = { string.format(
        "L%d: [line preview truncated: %d bytes exceeds %d-byte preview limit; all %d matches retained; "
            .. "unshown source text omitted; byte ranges are zero-based UTF-8, end-exclusive]",
        match_item.line, #text, MAX_RG_LINE_PREVIEW_BYTES, #submatches
    ) }
    -- Pending overlapping context, merged only while it still fits one bounded excerpt.
    -- 待输出的重叠上下文，合并后仍满足单个有界片段大小时才继续合并。
    local pending, first_match, last_match
    --[[
    Flush the current excerpt once; takes no arguments and returns nothing.
    输出当前片段一次；无参数、无返回值。
    ]]
    local function flush()
        if pending then
            append_rg_excerpt(lines, text, pending, first_match, last_match)
            pending = nil
        end
    end
    for index, submatch in ipairs(submatches) do
        -- RG reports half-open byte offsets, including positions at line-ending boundaries.
        -- RG 报告左闭右开的字节偏移，包括位于行结束符边界的位置。
        local first, last = submatch.start, submatch["end"]
        assert(type(first) == "number" and type(last) == "number" and first >= 0 and last >= first,
            "invalid RG submatch byte range")
        -- Reserve two UTF-8 characters for outward alignment, in addition to both context margins.
        -- 除两侧上下文外，为向外对齐额外预留两个 UTF-8 字符的空间。
        if last - first > MAX_RG_LINE_PREVIEW_BYTES - 2 * RG_MATCH_CONTEXT_BYTES - 8 then
            flush()
            table.insert(lines, string.format(
                "  [match %d; bytes [%d,%d); match preview truncated: matched text plus context exceeds "
                    .. "%d-byte preview limit; middle omitted]",
                index, first, last, MAX_RG_LINE_PREVIEW_BYTES
            ))
            append_rg_excerpt(lines, text,
                rg_utf8_window(text, first - RG_MATCH_CONTEXT_BYTES, first + RG_MATCH_CONTEXT_BYTES),
                index, index)
            append_rg_excerpt(lines, text,
                rg_utf8_window(text, last - RG_MATCH_CONTEXT_BYTES, last + RG_MATCH_CONTEXT_BYTES),
                index, index)
        else
            if first == last then
                -- Record the exact position without breaking context merging for dense empty matches.
                -- 记录精确位置，同时保持密集空匹配的上下文合并。
                table.insert(lines, string.format("  [match %d; zero-width at byte %d]", index, first))
            end
            -- All non-abbreviated matches fit completely inside their windows, even at UTF-8 edges.
            -- 所有未缩略的命中均完整包含在窗口内，UTF-8 边界处也不例外。
            local window = rg_utf8_window(text, first - RG_MATCH_CONTEXT_BYTES, last + RG_MATCH_CONTEXT_BYTES)
            if pending and window.first <= pending.last
                and math.max(pending.last, window.last) - pending.first <= MAX_RG_LINE_PREVIEW_BYTES then
                pending.last = math.max(pending.last, window.last)
                last_match = index
            else
                flush()
                pending, first_match, last_match = window, index, index
            end
        end
    end
    flush()
    return table.concat(lines, "\n")
end

local function build_tree_prefix(branch_state, is_last)
    local parts = {}
    for _, has_more_siblings in ipairs(branch_state or {}) do
        table.insert(parts, has_more_siblings and "│  " or "   ")
    end
    table.insert(parts, is_last and "└ " or "├ ")
    return table.concat(parts, "")
end

local function append_tree_line(lines, branch_state, is_last, text)
    table.insert(lines, build_tree_prefix(branch_state, is_last) .. text)
end

local function collect_render_children(symbol)
    local render_children = {}

    local matches = symbol.__vmcp_rg_line_matches or {}
    local limit = math.min(#matches, MAX_MATCH_LINES_PER_SYMBOL)
    for index = 1, limit do
        table.insert(render_children, {
            type = "match",
            value = matches[index],
        })
    end
    if #matches > MAX_MATCH_LINES_PER_SYMBOL then
        table.insert(render_children, {
            type = "overflow",
            value = #matches - MAX_MATCH_LINES_PER_SYMBOL,
        })
    end

    for _, child in ipairs(symbol.children or {}) do
        if child.__vmcp_rg_include then
            table.insert(render_children, {
                type = "symbol",
                value = child,
            })
        end
    end
    return render_children
end

local function append_symbol_tree(lines, symbol, branch_state, is_last)
    append_tree_line(lines, branch_state, is_last, format_symbol_label(symbol))

    local child_branch_state = clone_array(branch_state or {})
    table.insert(child_branch_state, not is_last)

    local render_children = collect_render_children(symbol)
    for index, child_item in ipairs(render_children) do
        local child_is_last = index == #render_children
        if child_item.type == "symbol" then
            append_symbol_tree(lines, child_item.value, child_branch_state, child_is_last)
        elseif child_item.type == "match" then
            append_tree_line(lines, child_branch_state, child_is_last, format_match_label(child_item.value))
        else
            append_tree_line(lines, child_branch_state, child_is_last, string.format("... (%d more matched lines)", child_item.value))
        end
    end
end

--[[
Annotate indexed owners while retaining every hit outside their line ranges.
标注已索引归属，同时保留其行范围外的全部命中。
Parameters: symbol_roots is the file AST root list; rg_hits is its ordered ripgrep hit list.
参数：symbol_roots 为文件 AST 根列表；rg_hits 为其有序 ripgrep 命中列表。
Returns the ordered hits without an indexed owner; matching symbols are annotated in place.
返回没有索引归属的有序命中列表；具有命中的符号在原地完成标注。
]]
local function annotate_tree_with_rg_hits(symbol_roots, rg_hits)
    clear_symbol_marks(symbol_roots)
    attach_parent_links(symbol_roots, nil)

    -- Hits without a containing indexed symbol remain first-class text results.
    -- 没有包含它们的索引符号的命中仍是完整的文本检索结果。
    local unowned_hits = {}
    for _, hit in ipairs(rg_hits) do
        -- Resolve ownership only from the actual inclusive AST line ranges.
        -- 仅根据真实的 AST 闭区间行范围确定归属。
        local matched_symbol = find_deepest_symbol_for_line(symbol_roots, hit.line)
        if matched_symbol then
            -- A matched symbol always resolves to itself or an indexed ancestor.
            -- 命中符号始终解析到自身或已索引祖先。
            local display_symbol = resolve_display_symbol(matched_symbol, hit.line)
            mark_symbol_chain(display_symbol)
            append_symbol_match_line(display_symbol, hit)
        else
            -- Missing AST coverage must not discard a successful ripgrep match.
            -- 缺少 AST 覆盖不能丢弃已经成功检索到的 ripgrep 命中。
            table.insert(unowned_hits, hit)
        end
    end

    sort_symbol_match_lines(symbol_roots)
    return unowned_hits
end

--[[
Render direct file-level hits and the indexed owner chains that contain other hits.
渲染文件级直接命中，以及包含其余命中的索引归属链。
Parameters: symbol_roots contains annotated AST roots; unowned_hits contains unmatched-owner hits.
参数：symbol_roots 包含已标注的 AST 根节点；unowned_hits 包含无索引归属的命中。
Returns one file's text body, preserving every hit without expanding function bodies.
返回单个文件的文本正文，保留全部命中且不展开函数体。
]]
local function build_filtered_file_content(symbol_roots, unowned_hits)
    -- File-level direct hits and existing owner groups share the same line format.
    -- 文件级直接命中与现有归属分组使用相同的行格式。
    local lines = {}
    if #unowned_hits > 0 then
        table.insert(lines, "@ Unowned matches (no indexed AST owner)")
        for _, hit in ipairs(unowned_hits) do
            table.insert(lines, format_match_label(hit))
        end
    end

    --[[
    Emit owner headers only for symbols carrying matched lines, retaining ancestor context.
    仅为承载命中行的符号输出归属头部，同时保留祖先上下文。
    Parameters: symbols is the current symbol list; ancestor_chain is its enclosing owner chain.
    参数：symbols 为当前符号列表；ancestor_chain 为其外层归属链。
    Returns nothing; appends owner headers and matching lines to the file output.
    无返回值；向文件输出追加归属头部和命中行。
    ]]
    local function collect_flat_entries(symbols, ancestor_chain)
        for _, symbol in ipairs(symbols) do
            if symbol.__vmcp_rg_include then
                -- Copy the ancestor chain so sibling owners cannot contaminate each other.
                -- 复制祖先链，避免同级归属节点相互污染。
                local current_chain = clone_array(ancestor_chain)
                table.insert(current_chain, symbol)

                -- Ancestors may be marked only for context and carry no direct line matches.
                -- 祖先可能仅因上下文被标记，本身不承载直接命中行。
                if #(symbol.__vmcp_rg_line_matches or {}) > 0 then
                    table.insert(lines, format_symbol_chain_label(current_chain))
                    for _, match_item in ipairs(symbol.__vmcp_rg_line_matches) do
                        table.insert(lines, format_match_label(match_item))
                    end
                end

                collect_flat_entries(symbol.children, current_chain)
            end
        end
    end

    collect_flat_entries(symbol_roots, {})
    return table.concat(lines, "\n")
end

--[[
Partition exact RG-matched files into bounded AST-enrichment and direct-hit groups.
将 RG 精确命中的文件划分为有界 AST 增强组和直接命中回退组。

Parameters / 参数:
- files(table): Exact file descriptors returned by the shared collector.
  共享文件收集器返回的精确文件描述对象。

Returns / 返回:
- table: Files admitted to synchronous AST enrichment.
  允许进入同步 AST 增强阶段的文件。
- table: Files skipped from AST enrichment together with explicit reasons.
  跳过 AST 增强并携带明确原因的文件。
- table: User-visible diagnostics for every skipped file.
  每个被跳过文件对应的用户可见诊断。
- number: Aggregate bytes admitted to synchronous AST enrichment.
  允许进入同步 AST 增强阶段的累计字节数。
]]
local function partition_ast_enrichment_files(files)
    -- Files whose exact metadata stays within every enrichment boundary.
    -- 精确元数据同时满足全部增强边界的文件。
    local admitted_files = {}
    -- Files rendered from direct RG hits because AST enrichment is unsafe or too expensive.
    -- 因 AST 增强不安全或代价过高而直接渲染 RG 命中的文件。
    local skipped_files = {}
    -- Stable diagnostics explaining every degradation from AST enrichment to direct RG output.
    -- 解释每次从 AST 增强降级为直接 RG 输出的稳定诊断。
    local diagnostics = {}
    -- Aggregate byte size already admitted to the synchronous FFI boundary.
    -- 已进入同步 FFI 边界的累计文件字节数。
    local admitted_bytes = 0

    for _, file_info in ipairs(files or {}) do
        -- Exact filesystem metadata for the already-resolved file path.
        -- 已解析精确文件路径对应的文件系统元数据。
        local stat_ok, metadata_or_error = pcall(vulcan.fs.stat, file_info.path)
        -- Stable reason code used by both fallback rendering and diagnostics.
        -- 回退渲染和诊断共同使用的稳定原因码。
        local skip_reason = nil
        -- Exact file size retained for diagnostics when metadata is available.
        -- 元数据可用时为诊断保留的精确文件大小。
        local file_size = nil

        if not stat_ok then
            skip_reason = "file_stat_failed"
        elseif type(metadata_or_error) ~= "table" or metadata_or_error.is_file ~= true then
            skip_reason = "file_stat_unavailable"
        elseif type(metadata_or_error.size) ~= "number" then
            skip_reason = "file_size_unavailable"
        else
            file_size = metadata_or_error.size
            if file_size > MAX_AST_ENRICHMENT_FILE_BYTES then
                skip_reason = "file_size_limit_exceeded"
            elseif #admitted_files >= MAX_AST_ENRICHMENT_FILES then
                skip_reason = "file_count_limit_exceeded"
            elseif admitted_bytes + file_size > MAX_AST_ENRICHMENT_TOTAL_BYTES then
                skip_reason = "total_size_limit_exceeded"
            end
        end

        if skip_reason then
            table.insert(skipped_files, {
                file_info = file_info,
                reason = skip_reason,
                size = file_size,
            })
            table.insert(
                diagnostics,
                string.format(
                    "%s: path=%s size=%s per_file_limit=%d total_limit=%d file_limit=%d",
                    skip_reason,
                    tostring(file_info.display_file or file_info.path),
                    file_size and tostring(file_size) or "unknown",
                    MAX_AST_ENRICHMENT_FILE_BYTES,
                    MAX_AST_ENRICHMENT_TOTAL_BYTES,
                    MAX_AST_ENRICHMENT_FILES
                )
            )
        else
            table.insert(admitted_files, file_info)
            admitted_bytes = admitted_bytes + file_size
        end
    end

    return admitted_files, skipped_files, diagnostics, admitted_bytes
end

--[[
Render direct RG hits for files deliberately excluded from AST enrichment.
为主动排除在 AST 增强之外的文件渲染直接 RG 命中。

Parameters / 参数:
- skipped_files(table): Skipped file descriptors and their explicit reason codes.
  被跳过的文件描述对象及其明确原因码。
- hits_by_canonical_file(table): RG hits keyed by canonical exact file path.
  以规范化精确文件路径为键的 RG 命中。

Returns / 返回:
- table: File results preserving useful RG output without invoking the AST FFI.
  不调用 AST FFI 但仍保留有效 RG 输出的文件结果。
]]
local function build_direct_rg_file_results(skipped_files, hits_by_canonical_file)
    -- Direct-hit file results merged with regular AST-enriched results later.
    -- 稍后与常规 AST 增强结果合并的直接命中文件结果。
    local file_results = {}

    for _, skipped in ipairs(skipped_files or {}) do
        -- Exact file descriptor captured before the enrichment boundary decision.
        -- 在增强边界判定前捕获的精确文件描述对象。
        local file_info = skipped.file_info
        -- Ordered RG hits retained for this exact canonical file.
        -- 为该精确规范文件保留的有序 RG 命中。
        local file_hits = hits_by_canonical_file[normalize_path_key(file_info.path)] or {}
        -- Direct output lines headed by an explicit degradation marker.
        -- 以明确降级标记开头的直接输出行。
        local content_lines = {
            string.format("@ AST enrichment skipped: %s", tostring(skipped.reason)),
        }
        for _, hit in ipairs(file_hits) do
            table.insert(content_lines, format_match_label(hit))
        end
        table.insert(file_results, {
            file = file_info.display_file or file_info.path,
            content = table.concat(content_lines, "\n"),
        })
    end

    return file_results
end

--[[
Build file results from all RG hits, supplementing them with indexed owner context when present.
根据全部 RG 命中构建文件结果，并在存在索引归属时补充上下文。
Parameters: render_contexts contains per-file hits, symbols, and metadata; helper_bundle supplies AST helpers.
参数：render_contexts 包含逐文件命中、符号和元数据；helper_bundle 提供 AST 辅助函数。
Returns file results sorted by path; files without text hits produce no result.
返回按路径排序的文件结果；没有文本命中的文件不产生结果。
]]
local function build_rg_file_results(render_contexts, helper_bundle)
    -- Every file with RG hits is rendered, including files with an empty symbol index.
    -- 每个存在 RG 命中的文件都会被渲染，包括符号索引为空的文件。
    local file_results = {}

    for _, render_context in ipairs(render_contexts) do
        if #render_context.file_hits > 0 then
            -- The shared builder accepts an empty symbol list and returns an empty tree.
            -- 共享建树方法接受空符号列表并返回空树。
            local tree = helper_bundle.build_symbol_tree(render_context.symbols)
            -- Preserve hits outside indexed ranges separately from annotated symbol owners.
            -- 在已标注符号归属之外，单独保留索引范围外的命中。
            local unowned_hits = annotate_tree_with_rg_hits(tree, render_context.file_hits)
            table.insert(file_results, {
                -- Display paths are optional in the existing AST file descriptor contract.
                -- 现有 AST 文件描述契约中的显示路径为可选字段。
                file = render_context.file_info.display_file or render_context.file_info.path,
                content = build_filtered_file_content(tree, unowned_hits),
            })
        end
    end

    -- Compare rendered file paths; left and right are file results, returning ascending order.
    -- 比较渲染文件路径；left 和 right 为文件结果，返回升序判断值。
    table.sort(file_results, function(left, right)
        return left.file < right.file
    end)

    return file_results
end

local function render_error_lines(errors)
    local lines = {}
    for _, item in ipairs(errors or {}) do
        if type(item) == "string" then
            table.insert(lines, "- " .. item)
        elseif type(item) == "table" then
            if item.group then
                table.insert(lines, "- Group: " .. tostring(item.group))
            end
            for _, diagnostic in ipairs(item.diagnostics or {}) do
                table.insert(lines, "  - " .. tostring(diagnostic))
            end
        end
    end
    return lines
end

--[[
把 `codekit-rg` 结果渲染为 Markdown 纯文本，便于模型直接阅读并继续下一步分析。
Render the `codekit-rg` result as plain Markdown text so the model can read it directly and continue analysis.
]]

local function build_rg_markdown(result)
    local lines = {
        "# RG RESULTS",
    }

    local error_lines = render_error_lines(result.errors)
    if #error_lines > 0 then
        table.insert(lines, "")
        table.insert(lines, "## ERRORS")
        table.insert(lines, "")
        for _, line in ipairs(error_lines) do
            table.insert(lines, line)
        end
    end

    for index, file_result in ipairs(result.files or {}) do
        if index > 1 or #error_lines > 0 then
            table.insert(lines, "")
        end
        table.insert(lines, string.format("[%s]", tostring(file_result.file or "unknown")))
        if trim(file_result.content or "") ~= "" then
            table.insert(lines, tostring(file_result.content))
        end
    end

    return table.concat(lines, "\n")
end

--[[
统一收尾 rg 结果；正常情况下直接返回 Markdown，超出预算时走共享 overflow 协议。
Finalize the rg result uniformly; return inline Markdown when safe, otherwise use the shared overflow protocol.

 参数 / Parameters:
 - full_result(table): 已完成文件结果与诊断拼装的最终结果对象 / Final result object with rendered files and diagnostics assembled.

返回 / Returns:
- string: 完整 Markdown 正文，后续是否原样返回、截断还是分页由宿主统一决定。
  Full Markdown body; the host later decides whether it stays inline, gets truncated, or turns into a paging index.
]]
local function finalize_rg_result(full_result)
    local markdown_text = build_rg_markdown(full_result)
    return tostring(markdown_text or ""), vulcan.runtime.overflow_type.page
end

--[[
Escape a diagnostic value as Markdown text while preserving line breaks and list indentation.
将诊断值转义为 Markdown 文本，同时保留换行与列表缩进。
Parameters: value is a scalar error field; indent is its enclosing list indentation.
参数：value 为错误标量字段；indent 为所在列表的缩进。
Returns escaped text; paths, regexes and external error text cannot create Markdown blocks.
返回转义文本；路径、正则及外部错误文本不会生成 Markdown 块。
]]
local function escape_error_markdown(value, indent)
    return (tostring(value):gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("(%p)", "\\%1")
        :gsub("\n", "  \n" .. indent .. "  "))
end

--[[
Append error maps and diagnostic arrays as nested Markdown lists, preserving every field.
将错误对象和诊断数组附加为嵌套 Markdown 列表，保留全部字段。
Parameters: lines receives output; fields is a JSON-shaped table; indent controls nesting.
参数：lines 接收输出；fields 为 JSON 形状的表；indent 控制嵌套。
Returns nothing; error identifiers and messages precede other fields, and arrays retain order.
无返回值；错误标识和原因位于其他字段之前，数组保留顺序。
]]
local function append_codekit_error_fields(lines, fields, indent)
    -- Sort keys without serializing the table back into JSON.
    -- 对键排序，不将表重新序列化为 JSON。
    local keys = {}
    for key in pairs(fields) do
        table.insert(keys, key)
    end
    -- Fixed field priority for the existing error/message contract.
    -- 既有 error/message 契约的固定字段优先级。
    local priority = { error = 1, message = 2 }
    -- Compare two keys; numeric array indexes sort numerically, object keys by priority then name.
    -- 比较两个键；数组数字索引按数值排序，对象键先按优先级再按名称排序。
    table.sort(keys, function(left, right)
        if type(left) == "number" and type(right) == "number" then
            return left < right
        end
        if (priority[left] or 3) ~= (priority[right] or 3) then
            return (priority[left] or 3) < (priority[right] or 3)
        end
        return tostring(left) < tostring(right)
    end)
    for _, key in ipairs(keys) do
        -- A table is a nested diagnostic object or array; scalars remain readable text.
        -- 表表示嵌套诊断对象或数组；标量保持为可读文本。
        local value = fields[key]
        -- Escaped field label, with indentation derived solely from the diagnostic structure.
        -- 转义后的字段标签，缩进仅由诊断结构派生。
        local label = indent .. "- **" .. escape_error_markdown(key, "") .. "**:"
        if type(value) == "table" then
            table.insert(lines, label)
            append_codekit_error_fields(lines, value, indent .. "  ")
        else
            table.insert(lines, label .. " " .. escape_error_markdown(value, indent))
        end
    end
end

--[[
Render RG failures directly as Markdown rather than embedding a serialized error object.
将 RG 失败直接渲染为 Markdown，不再嵌入序列化错误对象。
Parameters: tool_title names the tool; error_payload is a structured error or plain diagnostic.
参数：tool_title 为工具名称；error_payload 为结构化错误或纯文本诊断。
Returns a Markdown string preserving the failure state, cause and all diagnostic details.
返回 Markdown 字符串，保留失败状态、原因与全部诊断细节。
]]
local function render_codekit_error_markdown(tool_title, error_payload)
    -- Failure metadata is visible directly in the rendered Markdown.
    -- 失败元数据直接显示在渲染后的 Markdown 中。
    local lines = {
        "# " .. escape_error_markdown(tool_title, ""),
        "",
        "Status: **FAILED**",
        "",
    }
    if type(error_payload) == "table" then
        append_codekit_error_fields(lines, error_payload, "")
    else
        table.insert(lines, escape_error_markdown(error_payload, ""))
    end
    return table.concat(lines, "\n")
end

-- 工具入口 / Tool entry point invoked by the MCP runtime.
return function(args)
    log_rg_stage("invocation", "started", nil)
    local _, client_limit_error = initialize_rg_client_budget()
    if client_limit_error then
        return render_codekit_error_markdown("CodeKit RG Error", client_limit_error)
    end

    local helper_bundle, helper_error = load_ast_runtime_helpers()
    if helper_error then
        return render_codekit_error_markdown("CodeKit RG Error", helper_error)
    end

    -- Shared path contract exported by AST Detail for host-managed PWD resolution.
    -- AST Detail 为宿主管理 PWD 解析导出的共享路径契约。
    local path_helpers, path_helpers_error = helper_bundle.load_codekit_path_module()
    if path_helpers_error then
        return render_codekit_error_markdown("CodeKit RG Error", path_helpers_error)
    end
    -- Validated project root injected by VulcanCode when available.
    -- VulcanCode 在可用时注入并完成校验的项目根路径。
    local pwd_root, pwd_error = path_helpers.resolve_pwd_root(args and args.PWD)
    if pwd_error then
        return render_codekit_error_markdown("CodeKit RG Error", pwd_error)
    end

    local target_directory, dir_error = validate_directory_argument(args and args.dir, path_helpers, pwd_root)
    if dir_error then
        return render_codekit_error_markdown("CodeKit RG Error", dir_error)
    end

    local rg_pattern, pattern_error = validate_rg_pattern_argument(args and args.rg_pattern)
    if pattern_error then
        return render_codekit_error_markdown("CodeKit RG Error", pattern_error)
    end

    local regex_engine, regex_engine_error = validate_regex_engine_argument(args and args.regex_engine)
    if regex_engine_error then
        return render_codekit_error_markdown("CodeKit RG Error", regex_engine_error)
    end

    local extension_filter, extension_error = helper_bundle.validate_extension_argument(args and args.extensions)
    if extension_error then
        return render_codekit_error_markdown("CodeKit RG Error", extension_error)
    end

    local ignore_enabled, ignore_error = helper_bundle.validate_noignore_argument(args and args.noignore)
    if ignore_error then
        return render_codekit_error_markdown("CodeKit RG Error", ignore_error)
    end

    local export_md_error = validate_export_md_absence(args and args.export_md_path)
    if export_md_error then
        return render_codekit_error_markdown("CodeKit RG Error", export_md_error)
    end

    local rg_binary_path, rg_binary_error = find_rg_binary()
    if rg_binary_error then
        return render_codekit_error_markdown("CodeKit RG Error", rg_binary_error)
    end

    local rg_arguments = build_rg_arguments(target_directory, extension_filter, rg_pattern, ignore_enabled, regex_engine)
    log_rg_stage("rg_process", "started", nil)
    local rg_stdout, rg_stderr, rg_error = run_rg_command(rg_binary_path, rg_arguments)
    if rg_error then
        log_rg_stage("rg_process", "failed", "reason=" .. tostring(rg_error.error or "unknown"))
        return render_codekit_error_markdown("CodeKit RG Error", rg_error)
    end
    log_rg_stage("rg_process", "completed", "stdout_bytes=" .. tostring(#rg_stdout))

    local hits_by_file, diagnostics = parse_rg_json_output(rg_stdout, rg_stderr)
    local matched_file_paths = {}
    local hits_by_canonical_file = {}
    for file_path in pairs(hits_by_file) do
        table.insert(matched_file_paths, file_path)
        local canonical_key = normalize_path_key(resolve_rg_hit_path(file_path))
        hits_by_canonical_file[canonical_key] = hits_by_canonical_file[canonical_key] or {}
        for _, hit in ipairs(hits_by_file[file_path] or {}) do
            table.insert(hits_by_canonical_file[canonical_key], hit)
        end
    end
    table.sort(matched_file_paths)
    log_rg_stage("rg_parse", "completed", "matched_files=" .. tostring(#matched_file_paths))

    if #matched_file_paths == 0 then
        return finalize_rg_result({
            files = {},
            errors = diagnostics,
        })
    end

    local files, _, collection_errors, collection_error = helper_bundle.collect_files(matched_file_paths, false, nil, ignore_enabled)
    if collection_error then
        return render_codekit_error_markdown("CodeKit RG Error", collection_error)
    end

    local scanner_client, _, _, scanner_error = helper_bundle.find_binary()
    if not scanner_client then
        return render_codekit_error_markdown("CodeKit RG Error", {
            error = "ast_grep_ffi_not_found",
            message = "ast-grep FFI library not found in the current skill dependency root",
            details = scanner_error,
        })
    end

    local enrichment_files, skipped_enrichment_files, enrichment_diagnostics, enrichment_bytes =
        partition_ast_enrichment_files(files)
    log_rg_stage(
        "ast_plan",
        "completed",
        string.format(
            "admitted_files=%d skipped_files=%d admitted_bytes=%d",
            #enrichment_files,
            #skipped_enrichment_files,
            enrichment_bytes
        )
    )
    local grouped_files = {}
    local aggregated_errors = clone_array(collection_errors or {})
    if #enrichment_diagnostics > 0 then
        table.insert(aggregated_errors, {
            group = "ast_enrichment_skipped",
            diagnostics = enrichment_diagnostics,
        })
    end
    for _, file_info in ipairs(enrichment_files) do
        grouped_files[file_info.language] = grouped_files[file_info.language] or {}
        table.insert(grouped_files[file_info.language], file_info.path)
    end

    local normalized_by_file = {}
    for language_key, file_paths in pairs(grouped_files) do
        log_rg_stage(
            "ast_scan",
            "started",
            string.format("language=%s files=%d", tostring(language_key), #file_paths)
        )
        local matches, match_diagnostics = helper_bundle.run_language_scan(scanner_client, nil, language_key, file_paths)
        log_rg_stage(
            "ast_scan",
            "completed",
            string.format(
                "language=%s files=%d matches=%d diagnostics=%d",
                tostring(language_key),
                #file_paths,
                #(matches or {}),
                #(match_diagnostics or {})
            )
        )
        if match_diagnostics and #match_diagnostics > 0 then
            table.insert(aggregated_errors, { group = language_key, diagnostics = match_diagnostics })
        end
        for _, match in ipairs(matches or {}) do
            local symbol = helper_bundle.normalize_symbol(match, language_key)
            if symbol then
                normalized_by_file[symbol.file] = normalized_by_file[symbol.file] or {}
                table.insert(normalized_by_file[symbol.file], symbol)
            end
        end
    end

    local render_contexts = {}
    for _, file_info in ipairs(enrichment_files) do
        local file_hits = hits_by_canonical_file[normalize_path_key(file_info.path)] or {}
        local symbols = helper_bundle.deduplicate_symbols(normalized_by_file[file_info.path] or {})
        table.insert(render_contexts, {
            file_info = file_info,
            file_hits = file_hits,
            symbols = symbols,
        })
    end

    local file_results = build_rg_file_results(render_contexts, helper_bundle)
    for _, direct_result in ipairs(build_direct_rg_file_results(skipped_enrichment_files, hits_by_canonical_file)) do
        table.insert(file_results, direct_result)
    end
    table.sort(file_results, function(left, right)
        return left.file < right.file
    end)
    log_rg_stage(
        "render",
        "completed",
        string.format("result_files=%d diagnostics=%d", #file_results, #aggregated_errors)
    )

    return finalize_rg_result({
        files = file_results,
        errors = aggregated_errors,
    })
end
