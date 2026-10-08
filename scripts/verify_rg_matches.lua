--[[
Verify that RG rendering preserves hits both inside and outside indexed AST ranges.
验证 RG 渲染完整保留索引 AST 范围内外的命中。
Run with Lua 5.1+ from the repository root; an optional first argument overrides that root.
从仓库根目录使用 Lua 5.1+ 执行；可通过首个可选参数覆盖根目录。
Returns the number of passed cases; any missing, duplicate, or unrelated hit raises an error.
返回通过用例数；任何缺失、重复或无关命中均抛出错误。
]]

-- Explicit repository location, defaulting to the documented working directory.
-- 显式仓库位置，默认使用约定的工作目录。
local repository_root = ... or "."

--[[
Read an exact named upvalue without exposing test-only production APIs.
读取精确命名的上值，避免在生产代码中暴露测试专用接口。
Parameters: owner is the enclosing function; name is its required upvalue name.
参数：owner 为持有上值的函数；name 为必需的上值名称。
Returns the upvalue, or raises an error if the runtime contract has changed.
返回上值；运行时契约发生变动时抛出错误。
]]
local function required_upvalue(owner, name)
    -- Current position in the enclosing function's captured values.
    -- 当前函数捕获值的遍历位置。
    local index = 1
    while true do
        -- Exact name and value reported by the Lua debug API.
        -- Lua 调试接口报告的精确名称和值。
        local current_name, value = debug.getupvalue(owner, index)
        assert(current_name ~= nil, "missing upvalue: " .. name)
        if current_name == name then
            return value
        end
        index = index + 1
    end
end

-- Real runtime closures; loading them does not start a host invocation or FFI scan.
-- 真实运行时闭包；加载时不会启动宿主调用或 FFI 扫描。
local rg_entry = assert(loadfile(repository_root .. "/runtime/codekit-rg.lua"))()
-- AST entry owning the same tree builder used by the RG tool.
-- 持有 RG 工具所用同一建树方法的 AST 入口。
local ast_entry = assert(loadfile(repository_root .. "/runtime/codekit-ast-detail.lua"))()
-- Production file renderer exercised by every case below.
-- 下方各用例实际执行的生产文件渲染器。
local build_results = required_upvalue(rg_entry, "build_rg_file_results")
-- Exact production helper required by the file renderer.
-- 文件渲染器所需的精确生产辅助函数。
local helpers = { build_symbol_tree = required_upvalue(ast_entry, "build_symbol_tree") }

--[[
Build a normalized symbol fixture using the fields read by the production tree and renderer.
使用生产建树和渲染逻辑实际读取的字段构造归一化符号测试数据。
Parameters: kind and signature identify the symbol; first and last are inclusive lines.
参数：kind 和 signature 标识符号；first 和 last 为包含端点的行范围。
Returns a fresh symbol so mutable tree links cannot leak across cases.
返回新符号，防止可变树链接在用例之间泄漏。
]]
local function symbol(kind, signature, first, last)
    return {
        kind = kind,
        name = signature,
        signature = signature,
        start_line = first,
        end_line = last,
        container = kind == "impl",
        children = {},
    }
end

--[[
Reproduce the three indexed functions in the reported 15-line Rust sample.
复现用户所报十五行 Rust 样例中被索引的三个函数。
Parameters: none. Returns fresh normalized symbols; constants and modules are not Rust rules.
参数：无。返回新的归一化符号；Rust 规则不索引常量和模块声明。
]]
local function sample_symbols()
    return {
        symbol("function", "pub fn greet()", 3, 5),
        symbol("function", "pub fn add()", 7, 9),
        symbol("function", "pub fn nested()", 12, 14),
    }
end

-- Count successful behavioral assertions rather than source-text checks.
-- 统计成功的行为验证用例，而非源码字符串检查。
local passed = 0

--[[
Render one file and compare every emitted hit with the complete expected set.
渲染一个文件，并将全部输出命中与完整期望集合对比。
Parameters: label names the case; symbols are normalized AST nodes; hits are RG line records.
参数：label 为用例名；symbols 为归一化 AST 节点；hits 为 RG 行记录。
Parameters: markers are required literal headers; unowned indicates a file-level hit group.
参数：markers 为必需的字面量头部；unowned 表示应存在文件级命中组。
Returns nothing; asserts exact hit coverage, uniqueness, file identity, and group presence.
无返回值；断言命中覆盖、唯一性、文件归属和分组存在性。
]]
local function verify_case(label, symbols, hits, markers, unowned)
    -- File identity is fixed so the new group cannot lose its source path.
    -- 固定文件标识，确保新增分组不会丢失来源路径。
    local results = build_results({ {
        file_info = { path = "sample.rs", display_file = "sample.rs" },
        symbols = symbols,
        file_hits = hits,
    } }, helpers)
    if #hits == 0 then
        assert(#results == 0, label .. ": empty search emitted a file")
    else
        assert(#results == 1 and results[1].file == "sample.rs", label .. ": file lost")
        -- Expected unique line contents, as supplied by ripgrep's per-line records.
        -- 根据 ripgrep 逐行记录构造的唯一行内容期望。
        local expected = {}
        for _, hit in ipairs(hits) do
            expected[string.format("L%d: %s", hit.line, hit.text:match("^%s*(.-)%s*$"))] = true
        end
        -- Entire file body returned by the production rendering path.
        -- 生产渲染路径返回的完整文件正文。
        local content = results[1].content
        for line in content:gmatch("[^\n]+") do
            if line:match("^L%d+:") then
                assert(expected[line], label .. ": duplicate or unrelated hit: " .. line)
                expected[line] = nil
            end
        end
        assert(next(expected) == nil, label .. ": missing hit: " .. tostring(next(expected)))
        for _, marker in ipairs(markers) do
            assert(content:find(marker, 1, true), label .. ": missing owner: " .. marker)
        end
        assert((content:find("@ Unowned matches (no indexed AST owner)", 1, true) ~= nil) == unowned,
            label .. ": incorrect unowned group")
        assert(not content:find("AST enrichment skipped", 1, true), label .. ": false degradation")
    end
    passed = passed + 1
end

-- User-reported declaration hits include lines outside every Rust AST rule.
-- 用户所报声明命中包含所有 Rust AST 规则范围外的行。
local public_hits = {
    { line = 1, text = 'pub const SAMPLE_TOOL_ID: &str = "sample-tool";' },
    { line = 3, text = "pub fn greet() {" },
    { line = 7, text = "pub fn add() {" },
    { line = 11, text = "pub mod inner {" },
    { line = 12, text = "    pub fn nested() {" },
}
verify_case("all pub declarations", sample_symbols(), public_hits,
    { "pub fn greet()", "pub fn add()", "pub fn nested()" }, true)
for _, pattern in ipairs({ "SAMPLE_TOOL_ID", "^pub const", "sample-tool" }) do
    verify_case(pattern, sample_symbols(), { public_hits[1] }, {}, true)
end
verify_case("pub mod", sample_symbols(), { public_hits[4] }, {}, true)
verify_case("hello", sample_symbols(), { { line = 4, text = '    println!("hello");' } },
    { "pub fn greet()" }, false)
verify_case("7", sample_symbols(), { { line = 13, text = "        7" } },
    { "pub fn nested()" }, false)
verify_case("no indexed symbols", {}, { public_hits[1] }, {}, true)
verify_case("empty search", sample_symbols(), {}, {}, false)
verify_case("empty file", {}, {}, {}, false)
verify_case("imports comments and trailing content", sample_symbols(), {
    { line = 2, text = "use std::fmt;" },
    { line = 6, text = "// a comment between functions" },
    { line = 16, text = 'pub const TRAILING: &str = "中文";' },
}, {}, true)
verify_case("container field and method", {
    symbol("impl", "impl Sample", 2, 10),
    symbol("function", "fn run()", 6, 9),
}, {
    { line = 1, text = "// outside impl" },
    { line = 4, text = "    const ID: u32 = 7;" },
    { line = 7, text = "        execute();" },
    { line = 11, text = "// after impl" },
}, { "impl Sample [L2-10]", "fn run() [L6-9]" }, true)

-- More than the legacy symbol display cap must remain searchable in either group.
-- 两类分组中超过旧符号显示上限的命中仍须完整可检索。
local many_hits = {}
for line = 1, 30 do
    table.insert(many_hits, { line = line, text = "match " .. line })
end
verify_case("many mixed hits", { symbol("function", "fn many()", 8, 25) }, many_hits,
    { "fn many() [L8-25]" }, true)
verify_case("many unowned hits", {}, many_hits, {}, true)

-- The same formatter serves indexed, unowned and AST-skipped RG hits.
-- 同一个格式器服务于已索引、无归属和跳过 AST 的 RG 命中。
local format_match = required_upvalue(required_upvalue(build_results, "build_filtered_file_content"), "format_match_label")
-- Read the production presentation boundary rather than defining a second limit.
-- 读取生产展示边界，避免定义第二份上限。
local preview_bytes = required_upvalue(format_match, "MAX_RG_LINE_PREVIEW_BYTES")
-- Direct rendering used when AST enrichment exceeds its admission budget.
-- AST 增强超过准入预算时使用的直接渲染方法。
local build_direct = required_upvalue(rg_entry, "build_direct_rg_file_results")

--[[
Verify complete occurrence coverage and bounded UTF-8 excerpts through every ownership path.
通过每种归属路径验证全部命中覆盖，以及有界 UTF-8 片段。
Parameters: label identifies the case; text and submatches are one actual RG record's fields.
参数：label 标识用例；text 和 submatches 为单条 RG 记录的字段。
Returns nothing; fails if any occurrence disappears or an excerpt corrupts its source bytes.
无返回值；任一命中消失或片段损坏原始字节时失败。
]]
local function verify_long_case(label, text, submatches)
    -- One source record shared across all output paths without modifying the input.
    -- 在各输出路径共享的一条源码记录，不修改输入。
    local hit = { line = 2, text = text, submatches = submatches }
    -- Each case must exercise both AST ownership and direct-search degradation.
    -- 各用例必须同时覆盖 AST 归属与直接搜索降级。
    local paths = {
        build_results({ { file_info = { path = "sample.rs" }, symbols = {
            symbol("function", "fn sample()", 1, 3),
        }, file_hits = { hit } } }, helpers),
        build_results({ { file_info = { path = "sample.rs" }, symbols = {}, file_hits = { hit } } }, helpers),
        build_direct({ { file_info = { path = "sample.rs" }, reason = "file budget" } }, { ["sample.rs"] = { hit } }),
    }
    for _, results in ipairs(paths) do
        assert(#results == 1 and results[1].file == "sample.rs", label .. ": source file lost")
        -- Output intervals, occurrence coverage, abbreviated spans and exact zero-width positions.
        -- 输出区间、命中覆盖、缩略范围及精确空匹配位置。
        local windows, covered, abbreviated, zero_positions = {}, {}, {}, {}
        for line in results[1].content:gmatch("[^\n]+") do
            assert(#line <= preview_bytes + 512, label .. ": oversized output line")
            -- The range prefix is a location format, independent of diagnostic wording.
            -- 范围前缀属于定位格式，与诊断措辞无关。
            local first_index, last_index, first, last, excerpt =
                line:match("^  %[matches (%d+)%-(%d+); bytes %[(%d+),(%d+)%)%]: (.*)$")
            if first then
                first_index, last_index, first, last =
                    tonumber(first_index), tonumber(last_index), tonumber(first), tonumber(last)
                assert(last - first <= preview_bytes, label .. ": unbounded source excerpt")
                assert(first >= 0 and last <= #text, label .. ": excerpt outside source")
                assert(first == #text or text:byte(first + 1) < 128 or text:byte(first + 1) >= 192,
                    label .. ": split UTF-8 leading character")
                assert(last == #text or text:byte(last + 1) < 128 or text:byte(last + 1) >= 192,
                    label .. ": split UTF-8 trailing character")
                assert(excerpt == (first > 0 and "..." or "") .. text:sub(first + 1, last)
                    .. (last < #text and "..." or ""), label .. ": excerpt differs from source")
                table.insert(windows, { first = first, last = last })
                for index = first_index, last_index do
                    assert(submatches[index], label .. ": fabricated occurrence")
                    covered[index] = true
                end
            end
            -- Full spans of abbreviated matches must survive even when their middle text is omitted.
            -- 即使命中正文中间被省略，缩略命中的完整范围仍须保留。
            local index, span_first, span_last = line:match("^  %[match (%d+); bytes %[(%d+),(%d+)%);")
            if index then
                index = tonumber(index)
                assert(tonumber(span_first) == submatches[index].start
                    and tonumber(span_last) == submatches[index]["end"], label .. ": abbreviated range changed")
                abbreviated[index] = true
            end
            -- Empty matches need a position because source excerpts alone cannot identify them.
            -- 空匹配需要明确位置，仅凭源码片段无法定位。
            local zero_index, position = line:match("^  %[match (%d+); zero%-width at byte (%d+)%]$")
            if zero_index then
                zero_positions[tonumber(zero_index)] = tonumber(position)
            end
        end
        assert(#windows > 0, label .. ": missing source excerpts")
        for index, submatch in ipairs(submatches) do
            assert(covered[index], label .. ": omitted occurrence " .. index)
            -- Every normal match is complete; large matches must retain both original boundaries.
            -- 普通命中必须完整；大命中必须保留原始两端边界。
            local complete, has_start, has_end = false, false, false
            for _, window in ipairs(windows) do
                complete = complete or (window.first <= submatch.start and window.last >= submatch["end"])
                has_start = has_start or (window.first <= submatch.start and window.last > submatch.start)
                has_end = has_end or (window.first < submatch["end"] and window.last >= submatch["end"])
            end
            assert(complete or (abbreviated[index] and has_start and has_end),
                label .. ": match content missing without an explicit abbreviation")
            if submatch.start == submatch["end"] then
                assert(zero_positions[index] == submatch.start, label .. ": zero-width position lost")
            end
        end
        passed = passed + 1
    end
end

-- Boundary-sized ordinary lines preserve the established line output format.
-- 位于边界的普通行保留既有行输出格式。
verify_case("preview boundary", {}, { { line = 1, text = string.rep("x", preview_bytes) } }, {}, true)
-- The reported generated-file failure has a match far beyond the start of the line.
-- 用户报告的生成文件故障，其命中位置远离行首。
verify_long_case("generated line", string.rep("x", 850709) .. "notebook" .. string.rep("y", 1000000),
    { { start = 850709, ["end"] = 850717 } })
verify_long_case("just over boundary", string.rep("x", preview_bytes + 1),
    { { start = 0, ["end"] = 1 }, { start = preview_bytes, ["end"] = preview_bytes + 1 } })
-- Separated, adjacent and merged windows must retain every occurrence exactly in the source.
-- 分离、相邻与合并的窗口必须保留源码中的每个命中。
verify_long_case("separated and adjacent matches", string.rep("a", preview_bytes * 3), {
    { start = 0, ["end"] = 1 }, { start = 500, ["end"] = 503 }, { start = 504, ["end"] = 506 },
    { start = preview_bytes * 3 - 1, ["end"] = preview_bytes * 3 },
})
verify_long_case("oversized match plus later hit", string.rep("z", preview_bytes * 3), {
    { start = 0, ["end"] = preview_bytes * 2 },
    { start = preview_bytes * 3 - 1, ["end"] = preview_bytes * 3 },
})
verify_long_case("zero-width boundaries", string.rep("a", preview_bytes + 1), {
    { start = 0, ["end"] = 0 }, { start = preview_bytes + 1, ["end"] = preview_bytes + 1 },
})
-- Four-byte characters exercise outward alignment on either edge without invalid UTF-8.
-- 四字节字符覆盖两侧向外对齐，避免产生无效 UTF-8。
verify_long_case("unicode windows", string.rep("🙂", preview_bytes), {
    { start = 4, ["end"] = 8 }, { start = preview_bytes + 1, ["end"] = preview_bytes + 2 },
    { start = preview_bytes * 4 - 4, ["end"] = preview_bytes * 4 },
})
-- Dense matches must merge context instead of repeating a full window for every occurrence.
-- 密集命中必须合并上下文，避免为每次命中重复完整窗口。
local dense_matches = {}
for offset = 0, preview_bytes * 2 - 1 do
    table.insert(dense_matches, { start = offset, ["end"] = offset + 1 })
end
verify_long_case("dense matches", string.rep("a", preview_bytes * 2), dense_matches)
assert(#format_match({ line = 1, text = string.rep("a", preview_bytes * 2), submatches = dense_matches })
    < preview_bytes * 4, "dense output grew disproportionately")
-- Empty-match regexes also merge preview context while retaining each zero-width position.
-- 空匹配正则同样合并预览上下文，同时保留每个空匹配位置。
local empty_matches = {}
for offset = 0, preview_bytes + 1 do
    table.insert(empty_matches, { start = offset, ["end"] = offset })
end
verify_long_case("dense empty matches", string.rep("a", preview_bytes + 1), empty_matches)
assert(#format_match({ line = 1, text = string.rep("a", preview_bytes + 1), submatches = empty_matches })
    < preview_bytes * 64, "empty-match context was repeated for every occurrence")

-- Production error rendering must work without a JSON encoder, including nested diagnostics.
-- 生产错误渲染必须无需 JSON 编码器即可工作，包括嵌套诊断。
local render_error = required_upvalue(rg_entry, "render_codekit_error_markdown")
-- The reported failure is still a directory validation error, displayed directly as Markdown.
-- 用户报告的问题仍为目录校验错误，只是直接以 Markdown 展示。
local directory_error = {
    error = "dir_must_be_directory", message = "directory required",
    dir = "D:\\source\\session-fork.ts",
}
-- Rendered fields are compared with fixture values, without pinning production message wording.
-- 将渲染字段与夹具值对比，不锁定生产提示文案。
local directory_markdown = render_error("CodeKit RG Error", directory_error)
assert(not directory_markdown:find("```", 1, true), "error must not embed a fenced JSON object")
for key, value in pairs(directory_error) do
    assert(directory_markdown:gsub("\\(%p)", "%1"):find("- **" .. key .. "**: " .. value, 1, true),
        "error field missing: " .. key)
end
passed = passed + 1

-- Nested diagnostics retain scalar types and numeric array order.
-- 嵌套诊断保留标量值与数组数字顺序。
local nested_error = { details = { code = 0, retryable = false, diagnostics = {} } }
for index = 1, 12 do nested_error.details.diagnostics[index] = "item " .. index end
-- The output must include nested list indentation, not serialized object/array syntax.
-- 输出必须包含嵌套列表缩进，而非对象或数组序列化语法。
local nested_markdown = render_error("CodeKit RG Error", nested_error)
assert(nested_markdown:find("  - **code**: 0", 1, true), "numeric detail lost")
assert(nested_markdown:find("  - **retryable**: false", 1, true), "false detail lost")
-- Last located offset verifies the array is rendered in numeric order.
-- 上一次定位偏移用于验证数组按数字顺序渲染。
local previous = 0
for index, value in ipairs(nested_error.details.diagnostics) do
    -- Exact fixture field location in the Markdown list.
    -- Markdown 列表中夹具字段的精确位置。
    local position = nested_markdown:find("    - **" .. index .. "**: " .. value, previous + 1, true)
    assert(position, "diagnostic array order or field lost")
    previous = position
end
passed = passed + 1

-- Paths and multiline external errors must remain literal text instead of creating Markdown or HTML.
-- 路径与多行外部错误必须保持为字面文本，不生成 Markdown 或 HTML。
local unusual_error = "D:\\[project]\\file`name.ts\n# heading\n```json\n<script>"
-- Plain diagnostics use the same escaping and retain visible line breaks.
-- 纯文本诊断使用相同转义，并保留可见换行。
local unusual_markdown = render_error("CodeKit RG Error", unusual_error)
assert(not unusual_markdown:find("\n# heading", 1, true), "diagnostic injected a heading")
assert(not unusual_markdown:find("```", 1, true), "diagnostic injected a code fence")
assert(not unusual_markdown:find("<script>", 1, true), "diagnostic injected HTML")
assert(unusual_markdown:find("  \n  ", 1, true), "diagnostic line break lost")
assert(unusual_markdown:gsub("\\(%p)", "%1"):find("D:\\[project]\\file`name.ts", 1, true),
    "escaped path changed")
passed = passed + 1

print(string.format("RG match verification passed: %d cases.", passed))
return passed
