--[[
Shared host-managed PWD path resolution for Vulcan CodeKit tools.
Vulcan CodeKit 工具共享的宿主管理 PWD 路径解析。
]]

-- Trim leading and trailing whitespace from one value.
-- 移除一个值的首尾空白。
--
-- Parameters / 参数:
-- - value(any): Value converted to text before trimming. / 在裁剪前转换为文本的值。
--
-- Returns / 返回值:
-- - string: Trimmed text. / 裁剪后的文本。
local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Return whether one text value starts with a prefix.
-- 返回一个文本值是否以指定前缀开头。
--
-- Parameters / 参数:
-- - text(any): Text value to inspect. / 需要检查的文本值。
-- - prefix(string): Required prefix. / 必须匹配的前缀。
--
-- Returns / 返回值:
-- - boolean: Whether the prefix matches. / 前缀是否匹配。
local function starts_with(text, prefix)
    return tostring(text or ""):sub(1, #prefix) == prefix
end

-- Translate supported Windows device paths into ordinary drive or UNC paths.
-- 将受支持的 Windows 设备路径转换为普通盘符或 UNC 路径。
--
-- Parameters / 参数:
-- - path(any): Raw path text. / 原始路径文本。
--
-- Returns / 返回值:
-- - string: Translated path text. / 转换后的路径文本。
local function translate_windows_device_path(path)
    -- Raw path text inspected for supported device prefixes.
    -- 用于检查受支持设备前缀的原始路径文本。
    local text = tostring(path or "")
    -- UNC suffix captured from a translated or native device path.
    -- 从转换形式或原生设备路径中捕获的 UNC 后缀。
    local unc_remainder = text:match("^[\\/][\\/]%?[\\/][Uu][Nn][Cc][\\/](.+)$")
    if unc_remainder then
        return "//" .. unc_remainder
    end
    -- Drive suffix captured from the normal device-prefix spelling.
    -- 从标准设备前缀写法中捕获的盘符后缀。
    local drive_remainder = text:match("^[\\/][\\/]%?[\\/]([A-Za-z]:.*)$")
    if drive_remainder then
        return drive_remainder
    end
    -- Drive suffix captured from the slash-normalized shorthand spelling.
    -- 从斜杠规范化简写形式中捕获的盘符后缀。
    local shorthand_drive_remainder = text:match("^[\\/][\\/]%?([A-Za-z]:.*)$")
    if shorthand_drive_remainder then
        return shorthand_drive_remainder
    end
    return text
end

-- Normalize one path before absolute checks and filesystem access.
-- 在绝对路径检查和文件系统访问前规范化一个路径。
--
-- Parameters / 参数:
-- - path(any): Raw path value. / 原始路径值。
--
-- Returns / 返回值:
-- - string: Trimmed and translated path text. / 裁剪并转换后的路径文本。
local function normalize_path_text(path)
    return translate_windows_device_path(trim(path))
end

-- Return whether one normalized path is absolute on Windows or POSIX.
-- 返回一个规范化路径在 Windows 或 POSIX 上是否为绝对路径。
--
-- Parameters / 参数:
-- - path(any): Path value to inspect. / 需要检查的路径值。
--
-- Returns / 返回值:
-- - boolean: Whether the path is absolute. / 路径是否为绝对路径。
local function is_absolute_path(path)
    -- Normalized path used for platform-independent identity checks.
    -- 用于跨平台身份检查的规范化路径。
    local text = normalize_path_text(path)
    return text:match("^[A-Za-z]:[\\/]") ~= nil
        or text:match("^[\\/][\\/]") ~= nil
        or starts_with(text, "/")
end

-- Return whether one path is a Windows drive or UNC root.
-- 返回一个路径是否为 Windows 盘符根或 UNC 根。
--
-- Parameters / 参数:
-- - path(any): Path value to inspect. / 需要检查的路径值。
--
-- Returns / 返回值:
-- - boolean: Whether the path must retain its trailing separator. / 路径是否必须保留尾部分隔符。
local function is_windows_root_path(path)
    -- Slash-normalized path used to recognize UNC share roots.
    -- 用于识别 UNC 共享根的斜杠规范化路径。
    local normalized = normalize_path_text(path):gsub("\\", "/")
    -- Root path without optional trailing separators.
    -- 移除可选尾部分隔符后的根路径。
    local without_trailing = normalized:gsub("/+$", "")
    return normalized:match("^[A-Za-z]:/$") ~= nil
        or normalized:match("^[A-Za-z]:$") ~= nil
        or without_trailing:match("^//[^/]+/[^/]+$") ~= nil
end

-- Remove redundant trailing separators while preserving filesystem roots.
-- 移除冗余尾部分隔符，同时保留文件系统根路径。
--
-- Parameters / 参数:
-- - path(any): Path value to normalize. / 需要规范化的路径值。
--
-- Returns / 返回值:
-- - string: Path without redundant trailing separators. / 不含冗余尾部分隔符的路径。
local function trim_trailing_path_separators(path)
    -- Normalized path before root-sensitive trimming.
    -- 执行根路径敏感裁剪前的规范化路径。
    local normalized = normalize_path_text(path)
    if normalized == "/" or normalized == "\\" or is_windows_root_path(normalized) then
        return normalized
    end
    -- Path after removing trailing separators.
    -- 移除尾部分隔符后的路径。
    local trimmed = normalized:gsub("[\\/]+$", "")
    return trimmed ~= "" and trimmed or normalized
end

-- Resolve one optional PWD value into a validated absolute directory root.
-- 将一个可选 PWD 值解析为经过校验的绝对目录根路径。
--
-- Parameters / 参数:
-- - value(any): Host-injected or caller-provided PWD value. / 宿主注入或调用方提供的 PWD 值。
--
-- Returns / 返回值:
-- - string|nil: Valid absolute directory root when available. / 可用时返回有效绝对目录根路径。
-- - table|nil: Structured validation error. / 结构化校验错误。
local function resolve_pwd_root(value)
    if value == nil then
        return nil, nil
    end
    if type(value) ~= "string" then
        return nil, {
            error = "invalid_pwd_argument",
            message = "PWD must be a string when provided",
            field = "PWD",
            actual_type = type(value),
        }
    end
    -- Normalized optional project root.
    -- 规范化后的可选项目根路径。
    local normalized = trim_trailing_path_separators(value)
    if normalized == "" then
        return nil, nil
    end
    if not is_absolute_path(normalized) then
        return nil, {
            error = "invalid_pwd_argument",
            message = "PWD must be an absolute directory path when provided",
            field = "PWD",
            pwd = normalized,
        }
    end
    if not vulcan.fs.exists(normalized) or not vulcan.fs.is_dir(normalized) then
        return nil, nil
    end
    return normalized, nil
end

-- Resolve one target path with the optional host-managed PWD root.
-- 使用可选的宿主管理 PWD 根路径解析一个目标路径。
--
-- Parameters / 参数:
-- - value(any): Target path value. / 目标路径值。
-- - field_name(string): Public field name used in errors. / 错误中使用的公开字段名。
-- - pwd_root(string|nil): Validated absolute PWD root. / 已校验的绝对 PWD 根路径。
--
-- Returns / 返回值:
-- - string|nil: Resolved absolute path. / 解析后的绝对路径。
-- - table|nil: Structured path error. / 结构化路径错误。
local function resolve_input_path(value, field_name, pwd_root)
    if type(value) ~= "string" then
        return nil, {
            error = "invalid_path_argument",
            message = "path must be a non-empty string",
            field = tostring(field_name or "path"),
            actual_type = type(value),
        }
    end
    -- Normalized target path used for absolute or PWD-relative resolution.
    -- 用于绝对路径或 PWD 相对解析的规范化目标路径。
    local normalized = normalize_path_text(value)
    if normalized == "" then
        return nil, {
            error = "invalid_path_argument",
            message = "path must be a non-empty string",
            field = tostring(field_name or "path"),
        }
    end
    if is_absolute_path(normalized) then
        return normalized, nil
    end
    if type(pwd_root) == "string" and pwd_root ~= "" then
        return vulcan.path.join(pwd_root, normalized), nil
    end
    return nil, {
        error = "relative_path_requires_pwd",
        message = "relative paths require a valid PWD; otherwise pass an absolute path",
        field = tostring(field_name or "path"),
        path = normalized,
    }
end

-- Resolve an ordered path list through one shared PWD root.
-- 通过同一个 PWD 根路径解析一个有序路径列表。
--
-- Parameters / 参数:
-- - values(table): Ordered raw path values. / 有序原始路径值。
-- - field_name(string): Root public field name. / 根级公开字段名。
-- - pwd_root(string|nil): Validated absolute PWD root. / 已校验的绝对 PWD 根路径。
--
-- Returns / 返回值:
-- - table|nil: Ordered resolved paths. / 有序解析路径。
-- - table|nil: First structured path error. / 首个结构化路径错误。
local function resolve_input_paths(values, field_name, pwd_root)
    if type(values) ~= "table" then
        return nil, {
            error = "invalid_path_list",
            message = "path list must be an array",
            field = tostring(field_name or "path"),
            actual_type = type(values),
        }
    end
    -- Ordered resolved paths returned to the calling tool.
    -- 返回给调用工具的有序解析路径。
    local resolved = {}
    for index, value in ipairs(values) do
        -- Indexed field identity used for precise batch errors.
        -- 用于精确批量错误的索引字段标识。
        local indexed_field = string.format("%s[%d]", tostring(field_name or "path"), index)
        -- Resolved absolute path for the current list element.
        -- 当前列表元素解析得到的绝对路径。
        local resolved_path, path_error = resolve_input_path(value, indexed_field, pwd_root)
        if path_error then
            return nil, path_error
        end
        table.insert(resolved, resolved_path)
    end
    return resolved, nil
end

return {
    resolve_pwd_root = resolve_pwd_root,
    resolve_input_path = resolve_input_path,
    resolve_input_paths = resolve_input_paths,
}
