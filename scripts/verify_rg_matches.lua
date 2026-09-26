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

print(string.format("RG match verification passed: %d cases.", passed))
return passed
