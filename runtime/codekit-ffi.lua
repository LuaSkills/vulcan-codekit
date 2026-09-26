--[[
Unified LuaJIT FFI loader for Vulcan CodeKit native capabilities.
Vulcan CodeKit 原生能力的统一 LuaJIT FFI 加载器。
]]

-- Expected dependency identity and semantic version.
-- 预期的依赖身份与语义化版本。
local CODEKIT_FFI_DEPENDENCY_NAME = "codekit-ffi"
-- Expected native version, synchronized with the skill and Cargo release manifests.
-- 预期原生版本，与技能及 Cargo 发布清单同步。
local CODEKIT_FFI_VERSION = "0.2.2"
-- Process-local module state for idempotent cdef and dynamic-library loading.
-- 进程内模块状态，用于幂等注册 cdef 与加载动态库。
local CODEKIT_FFI_CDEF_REGISTERED = false
local CODEKIT_FFI_CLIENT = nil

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
Return the current skill root injected by the LuaSkills host.
返回 LuaSkills 宿主注入的当前技能根目录。

Returns / 返回值:
- string: Current skill root path. / 当前技能根路径。
]]
local function get_skill_dir()
    return tostring(vulcan.context.skill_dir or ".")
end

--[[
Return the normalized LuaSkills platform key.
返回规范化的 LuaSkills 平台键。

Returns / 返回值:
- string: One supported dependency platform key. / 一个受支持的依赖平台键。
]]
local function current_platform_key()
    -- Read the exact host operating-system descriptor.
    -- 读取精确的宿主操作系统描述。
    local os_info = vulcan.os.info() or {}
    -- Normalize the architecture for deterministic comparison.
    -- 规范化架构名称以进行确定性比较。
    local architecture = trim(os_info.arch or os_info.architecture):lower()
    -- Normalize the operating-system name for deterministic comparison.
    -- 规范化操作系统名称以进行确定性比较。
    local os_name = trim(os_info.os):lower()

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
Return the platform-specific unified dynamic-library filename.
返回当前平台对应的统一动态库文件名。

Returns / 返回值:
- string: Platform-specific library filename. / 平台相关动态库文件名。
]]
local function get_library_name()
    -- Read the exact host operating-system descriptor.
    -- 读取精确的宿主操作系统描述。
    local os_info = vulcan.os.info() or {}
    -- Normalize host casing so dependency and filename resolution use the same platform identity.
    -- 规范化宿主大小写，使依赖与文件名解析使用同一平台身份。
    local os_name = trim(os_info.os):lower()
    if os_name == "windows" then
        return "vulcan_codekit_ffi.dll"
    end
    if os_name == "macos" or os_name == "darwin" or os_name == "osx" then
        return "libvulcan_codekit_ffi.dylib"
    end
    return "libvulcan_codekit_ffi.so"
end

--[[
Build exact dependency and local-development library candidates.
构造精确的依赖安装与本地开发动态库候选路径。

Parameters / 参数:
- library_name(string): Platform-specific library filename. / 平台相关动态库文件名。

Returns / 返回值:
- table: Ordered absolute candidate paths. / 有序绝对候选路径。
]]
local function build_library_candidates(library_name)
    -- Preserve deterministic candidate order for diagnostics.
    -- 保持确定性的候选顺序以便诊断。
    local candidates = {}
    -- Read only the documented host-injected FFI dependency root.
    -- 仅读取文档约定的宿主注入 FFI 依赖根目录。
    local ffi_root = trim(vulcan and vulcan.deps and vulcan.deps.ffi_path)
    if ffi_root ~= "" then
        -- Resolve the exact dependency installation directory.
        -- 解析精确的依赖安装目录。
        local dependency_base = vulcan.path.join(
            ffi_root,
            CODEKIT_FFI_DEPENDENCY_NAME,
            CODEKIT_FFI_VERSION,
            current_platform_key()
        )
        table.insert(candidates, vulcan.path.join(vulcan.path.join(dependency_base, "lib"), library_name))
        table.insert(candidates, vulcan.path.join(vulcan.path.join(dependency_base, "bin"), library_name))
        table.insert(candidates, vulcan.path.join(dependency_base, library_name))
    end

    -- Resolve the single documented local crate directory.
    -- 解析唯一文档约定的本地 crate 目录。
    local local_base = vulcan.path.join(get_skill_dir(), "codekit-ffi")
    table.insert(candidates, vulcan.path.join(vulcan.path.join(vulcan.path.join(local_base, "target"), "release"), library_name))
    table.insert(candidates, vulcan.path.join(vulcan.path.join(vulcan.path.join(local_base, "target"), "debug"), library_name))
    return candidates
end

--[[
Register the complete CodeKit C ABI exactly once for this module instance.
为当前模块实例仅注册一次完整 CodeKit C ABI。

Parameters / 参数:
- ffi(table): LuaJIT ffi module. / LuaJIT ffi 模块。

Returns / 返回值:
- boolean: Whether registration succeeded. / 注册是否成功。
- table|nil: Structured failure details. / 结构化失败详情。
]]
local function register_cdef(ffi)
    if CODEKIT_FFI_CDEF_REGISTERED then
        return true, nil
    end
    -- Register old AST symbols and new unified symbols in one declaration block.
    -- 在一个声明块中同时注册旧 AST 符号与新统一符号。
    local registered, register_error = pcall(ffi.cdef, [[
        const char* vulcan_codekit_ast_grep_version(void);
        char* vulcan_codekit_ast_grep_scan_json(const char* request_json);
        void vulcan_codekit_ast_grep_free_string(char* value);
        const char* vulcan_codekit_ffi_version(void);
        char* vulcan_codekit_ffi_capabilities_json(void);
        char* vulcan_codekit_repo_stats_json(const char* request_json);
        void vulcan_codekit_free_string(char* value);
    ]])
    if not registered then
        return false, {
            error = "codekit_ffi_cdef_failed",
            message = tostring(register_error),
        }
    end
    CODEKIT_FFI_CDEF_REGISTERED = true
    return true, nil
end

--[[
Read and free one owned JSON pointer returned by the unified library.
读取并释放统一动态库返回的一个自有 JSON 指针。

Parameters / 参数:
- client(table): Loaded CodeKit FFI client. / 已加载的 CodeKit FFI 客户端。
- response_pointer(cdata): Owned C string pointer. / 自有 C 字符串指针。

Returns / 返回值:
- table|nil: Decoded JSON object. / 解码后的 JSON 对象。
- table|nil: Structured failure details. / 结构化失败详情。
]]
local function decode_owned_json(client, response_pointer)
    if response_pointer == nil then
        return nil, {
            error = "codekit_ffi_response_null",
            message = "CodeKit FFI returned a null response pointer",
        }
    end
    -- Copy the C string before releasing its Rust allocation.
    -- 在释放 Rust 分配前复制 C 字符串。
    local read_ok, response_text = pcall(client.ffi.string, response_pointer)
    pcall(client.library.vulcan_codekit_free_string, response_pointer)
    if not read_ok then
        return nil, {
            error = "codekit_ffi_response_read_failed",
            message = tostring(response_text),
        }
    end
    -- Decode only after the Rust allocation has been safely released.
    -- 仅在安全释放 Rust 分配后解码。
    local decode_ok, decoded, decode_error = pcall(vulcan.json.decode, response_text)
    if not decode_ok or type(decoded) ~= "table" then
        return nil, {
            error = "codekit_ffi_response_decode_failed",
            message = decode_ok and tostring(decode_error) or tostring(decoded),
        }
    end
    return decoded, nil
end

--[[
Return whether a capability list contains one exact protocol contract.
判断能力列表是否包含一个精确协议契约。

Parameters / 参数:
- capabilities(table): Decoded capability records. / 已解码的能力记录。
- name(string): Required stable capability name. / 必需的稳定能力名称。
- protocol(string): Required protocol version. / 必需的协议版本。

Returns / 返回值:
- boolean: Whether the exact capability is present. / 是否存在精确能力。
]]
local function has_capability(capabilities, name, protocol)
    if type(capabilities) ~= "table" then
        return false
    end
    for _, capability in ipairs(capabilities) do
        if type(capability) == "table"
            and tostring(capability.name or "") == name
            and tostring(capability.protocol or "") == protocol then
            return true
        end
    end
    return false
end

--[[
Load, validate, and cache the unified CodeKit dynamic library.
加载、校验并缓存统一 CodeKit 动态库。

Returns / 返回值:
- table|nil: Validated CodeKit FFI client. / 已校验的 CodeKit FFI 客户端。
- table|nil: Structured loading failure. / 结构化加载失败。
]]
local function load_client()
    if CODEKIT_FFI_CLIENT then
        return CODEKIT_FFI_CLIENT, nil
    end
    -- Load the required LuaJIT ffi module.
    -- 加载必需的 LuaJIT ffi 模块。
    local ffi_ok, ffi = pcall(require, "ffi")
    if not ffi_ok or type(ffi) ~= "table" then
        return nil, {
            error = "luajit_ffi_unavailable",
            message = "LuaJIT ffi module is required to load CodeKit FFI",
            details = tostring(ffi),
        }
    end
    -- Register the exact unified ABI before loading any candidate.
    -- 在加载任何候选前注册精确的统一 ABI。
    local cdef_ok, cdef_error = register_cdef(ffi)
    if not cdef_ok then
        return nil, cdef_error
    end
    -- Resolve the platform library and exact candidate paths.
    -- 解析平台动态库与精确候选路径。
    local library_name = get_library_name()
    local candidates = build_library_candidates(library_name)
    -- Retain load failures for explicit diagnostics.
    -- 保留加载失败以便显式诊断。
    local load_errors = {}
    for _, library_path in ipairs(candidates) do
        if vulcan.fs.exists(library_path) then
            -- Attempt to load only a path that actually exists.
            -- 仅尝试加载实际存在的路径。
            local loaded, library_or_error = pcall(ffi.load, library_path)
            if loaded then
                -- Read the unified version symbol before accepting the library.
                -- 在接受动态库前读取统一版本符号。
                local version_ok, version_pointer = pcall(library_or_error.vulcan_codekit_ffi_version)
                if not version_ok or version_pointer == nil then
                    table.insert(load_errors, "codekit_ffi_version_unavailable:" .. tostring(version_pointer))
                else
                    -- Copy the process-lifetime static version string.
                    -- 复制进程生命周期内有效的静态版本字符串。
                    local version_read_ok, version = pcall(ffi.string, version_pointer)
                    if not version_read_ok then
                        table.insert(load_errors, "codekit_ffi_version_read_failed:" .. tostring(version))
                    elseif version ~= CODEKIT_FFI_VERSION then
                        table.insert(load_errors, string.format(
                            "codekit_ffi_version_mismatch:%s:expected=%s:actual=%s",
                            library_path,
                            CODEKIT_FFI_VERSION,
                            version
                        ))
                    else
                        -- Construct the validated client before capability probing.
                        -- 在能力探测前构造已校验客户端。
                        local client = {
                            kind = "codekit_ffi",
                            ffi = ffi,
                            library = library_or_error,
                            library_name = library_name,
                            library_path = library_path,
                            version = version,
                        }
                        -- Request the CodeKit-owned capability contract.
                        -- 请求 CodeKit 自有能力契约。
                        local capability_ok, capability_pointer = pcall(library_or_error.vulcan_codekit_ffi_capabilities_json)
                        if capability_ok then
                            -- Decode and release the owned capability response.
                            -- 解码并释放自有能力响应。
                            local capabilities, capability_error = decode_owned_json(client, capability_pointer)
                            local capability_list = capabilities and capabilities.capabilities
                            local has_ast_grep = has_capability(capability_list, "ast-grep", "1")
                            local has_repo_stats = has_capability(capability_list, "repo-stats", "1")
                            if capabilities and capabilities.ok == true and has_ast_grep and has_repo_stats then
                                client.capabilities = capability_list
                                CODEKIT_FFI_CLIENT = client
                                return CODEKIT_FFI_CLIENT, nil
                            end
                            table.insert(load_errors, string.format(
                                "codekit_ffi_capabilities_invalid:ast_grep=%s:repo_stats=%s:%s",
                                tostring(has_ast_grep),
                                tostring(has_repo_stats),
                                tostring(capability_error and capability_error.message)
                            ))
                        else
                            table.insert(load_errors, "codekit_ffi_capabilities_failed:" .. tostring(capability_pointer))
                        end
                    end
                end
            else
                table.insert(load_errors, tostring(library_or_error))
            end
        end
    end
    return nil, {
        error = "codekit_ffi_library_not_found",
        message = "CodeKit FFI library was not found or did not satisfy the expected capability contract",
        expected_paths = candidates,
        load_errors = load_errors,
    }
end

--[[
Call the legacy-compatible ast-grep scan through the unified library.
通过统一动态库调用兼容旧协议的 ast-grep 扫描。

Parameters / 参数:
- client(table): Loaded CodeKit FFI client. / 已加载的 CodeKit FFI 客户端。
- request(table): Existing ast-grep JSON request. / 现有 ast-grep JSON 请求。

Returns / 返回值:
- table|nil: Match array on success. / 成功时的命中数组。
- table: Diagnostic string array. / 诊断字符串数组。
]]
local function call_ast_grep(client, request)
    if type(client) ~= "table" or client.kind ~= "codekit_ffi" then
        return nil, { "codekit_ffi_client_missing" }
    end
    -- Encode the existing AST request without changing its JSON fields.
    -- 在不改变 JSON 字段的情况下编码现有 AST 请求。
    local encoded_ok, encoded_request = pcall(vulcan.json.encode, request)
    if not encoded_ok or type(encoded_request) ~= "string" then
        return nil, { "ast_grep_ffi_request_encode_failed: " .. tostring(encoded_request) }
    end
    -- Invoke the preserved legacy-compatible AST symbol.
    -- 调用保留的旧版兼容 AST 符号。
    local call_ok, response_pointer = pcall(client.library.vulcan_codekit_ast_grep_scan_json, encoded_request)
    if not call_ok then
        return nil, { "ast_grep_ffi_scan_failed: " .. tostring(response_pointer) }
    end
    -- Decode and release the owned response through the unified free function.
    -- 通过统一释放函数解码并释放自有响应。
    local decoded, response_error = decode_owned_json(client, response_pointer)
    if not decoded then
        return nil, { tostring(response_error and response_error.error) .. ": " .. tostring(response_error and response_error.message) }
    end
    -- Normalize diagnostic values to strings for existing Lua callers.
    -- 将诊断值规范化为字符串以兼容现有 Lua 调用方。
    local diagnostics = {}
    for _, diagnostic in ipairs(decoded.diagnostics or {}) do
        table.insert(diagnostics, tostring(diagnostic))
    end
    if decoded.ok ~= true then
        -- Preserve the legacy error-plus-message diagnostic shape.
        -- 保持旧版错误码加说明的诊断结构。
        local message = tostring(decoded.error or "ast_grep_ffi_error")
        if decoded.message and tostring(decoded.message) ~= "" then
            message = message .. ": " .. tostring(decoded.message)
        end
        table.insert(diagnostics, message)
        return nil, diagnostics
    end
    return decoded.matches or {}, diagnostics
end

--[[
Call the CodeKit repository-statistics protocol through the unified library.
通过统一动态库调用 CodeKit 仓库统计协议。

Parameters / 参数:
- client(table): Loaded CodeKit FFI client. / 已加载的 CodeKit FFI 客户端。
- request(table): CodeKit repository-statistics request. / CodeKit 仓库统计请求。

Returns / 返回值:
- table|nil: Complete decoded statistics response on success. / 成功时的完整解码统计响应。
- table|nil: Structured failure details. / 结构化失败详情。
]]
local function call_repo_stats(client, request)
    if type(client) ~= "table" or client.kind ~= "codekit_ffi" then
        return nil, {
            error = "codekit_ffi_client_missing",
            message = "CodeKit FFI client is required for repository statistics",
        }
    end
    -- Encode the exact CodeKit-owned repository request.
    -- 编码精确的 CodeKit 自有仓库请求。
    local encoded_ok, encoded_request = pcall(vulcan.json.encode, request)
    if not encoded_ok or type(encoded_request) ~= "string" then
        return nil, {
            error = "repo_stats_request_encode_failed",
            message = tostring(encoded_request),
        }
    end
    -- Invoke the repository-statistics ABI.
    -- 调用仓库统计 ABI。
    local call_ok, response_pointer = pcall(client.library.vulcan_codekit_repo_stats_json, encoded_request)
    if not call_ok then
        return nil, {
            error = "repo_stats_call_failed",
            message = tostring(response_pointer),
        }
    end
    -- Decode and release the complete repository response.
    -- 解码并释放完整仓库响应。
    local decoded, response_error = decode_owned_json(client, response_pointer)
    if not decoded then
        return nil, response_error
    end
    if decoded.ok ~= true then
        return nil, {
            error = tostring(decoded.error or "repo_stats_failed"),
            message = tostring(decoded.message or "repository statistics request failed"),
            response = decoded,
        }
    end
    return decoded, nil
end

-- Public module contract shared by AST and Repo Map entries.
-- 由 AST 与 Repo Map 入口共享的公共模块契约。
return {
    dependency_name = CODEKIT_FFI_DEPENDENCY_NAME,
    version = CODEKIT_FFI_VERSION,
    get_library_name = get_library_name,
    build_library_candidates = build_library_candidates,
    load_client = load_client,
    call_ast_grep = call_ast_grep,
    call_repo_stats = call_repo_stats,
}
