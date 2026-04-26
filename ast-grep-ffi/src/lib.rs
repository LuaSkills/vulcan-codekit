//! Public FFI entry points for Vulcan CodeKit ast-grep scanning.
//! Vulcan CodeKit ast-grep 扫描能力的公共 FFI 入口。

use ast_grep_config::{from_yaml_string, CombinedScan, GlobalRules, Metadata, RuleConfig};
use ast_grep_core::meta_var::MetaVariable;
use ast_grep_core::tree_sitter::StrDoc;
use ast_grep_core::{AstGrep, Doc, Node, NodeMatch};
use ast_grep_language::SupportLang;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::BTreeMap;
use std::ffi::{CStr, CString};
use std::fs;
use std::os::raw::{c_char, c_void};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;
use std::ptr;

/// Describe one scan request passed from Lua as JSON.
/// 描述 Lua 以 JSON 传入的一次扫描请求。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ScanRequest {
    /// Optional language hint used when rule YAML cannot provide a language.
    /// 当规则 YAML 无法提供语言时使用的可选语言提示。
    language: Option<String>,
    /// Inline ast-grep rule YAML text.
    /// 内联 ast-grep 规则 YAML 文本。
    rule_yaml: Option<String>,
    /// Alias for inline rule YAML used by validation callers.
    /// 供校验调用方使用的内联规则 YAML 别名。
    inline_rule_yaml: Option<String>,
    /// Optional filesystem path to the ast-grep rule YAML.
    /// 可选的 ast-grep 规则 YAML 文件路径。
    rule_path: Option<String>,
    /// Source files that should be scanned by the rule set.
    /// 需要由规则集扫描的源文件列表。
    files: Vec<String>,
}

/// Describe one scan response returned to Lua as JSON.
/// 描述返回给 Lua 的一次扫描响应 JSON。
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ScanResponse {
    /// Whether the FFI request completed without a fatal error.
    /// FFI 请求是否在无致命错误的情况下完成。
    ok: bool,
    /// Normalized ast-grep matches consumable by existing CodeKit Lua code.
    /// 可被现有 CodeKit Lua 代码消费的规范化 ast-grep 命中结果。
    matches: Vec<MatchRecord>,
    /// Non-fatal scan diagnostics gathered while reading or parsing files.
    /// 读取或解析文件时收集到的非致命诊断信息。
    diagnostics: Vec<String>,
    /// Fatal error code when `ok` is false.
    /// 当 `ok` 为 false 时的致命错误代码。
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
    /// Human readable fatal error message when `ok` is false.
    /// 当 `ok` 为 false 时的人类可读致命错误信息。
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
}

/// Describe one normalized ast-grep match.
/// 描述一个规范化后的 ast-grep 命中结果。
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct MatchRecord {
    /// Rule identifier that produced this match.
    /// 产生该命中的规则标识。
    rule_id: String,
    /// Source file path scanned for this match.
    /// 该命中所属的源文件路径。
    file: String,
    /// Matched node range in CLI-compatible shape.
    /// 与 CLI 兼容形态的命中节点范围。
    range: RangeRecord,
    /// Matched source text.
    /// 命中的源代码文本。
    text: String,
    /// Matched source text alias used by compact error-node validation.
    /// 供紧凑 ERROR 节点校验使用的命中文本别名。
    lines: String,
    /// Matched tree-sitter node kind.
    /// 命中的 tree-sitter 节点类型。
    node_kind: String,
    /// Rule message rendered with captured metavariables.
    /// 使用捕获元变量渲染后的规则消息。
    message: String,
    /// Rule metadata copied from the YAML rule.
    /// 从 YAML 规则复制出的规则元数据。
    metadata: Map<String, Value>,
    /// Captured metavariables in ast-grep CLI-compatible naming.
    /// 使用 ast-grep CLI 兼容命名的捕获元变量。
    #[serde(rename = "metaVariables")]
    meta_variables: MetaVariablesRecord,
}

/// Describe all captured metavariables for one match.
/// 描述单个命中的全部捕获元变量。
#[derive(Debug, Default, Serialize)]
struct MetaVariablesRecord {
    /// Single-node metavariable captures keyed by capture name.
    /// 按捕获名索引的单节点元变量捕获。
    single: BTreeMap<String, CaptureRecord>,
    /// Multi-node metavariable captures keyed by capture name.
    /// 按捕获名索引的多节点元变量捕获。
    multi: BTreeMap<String, Vec<CaptureRecord>>,
}

/// Describe one captured node.
/// 描述一个被捕获的节点。
#[derive(Debug, Serialize)]
struct CaptureRecord {
    /// Captured source text.
    /// 捕获到的源代码文本。
    text: String,
    /// Captured source range.
    /// 捕获到的源码范围。
    range: RangeRecord,
}

/// Describe a source range with line/column and byte offsets.
/// 描述包含行列号与字节偏移的源码范围。
#[derive(Debug, Serialize)]
struct RangeRecord {
    /// Inclusive start position.
    /// 包含式起始位置。
    start: PointRecord,
    /// Exclusive end position.
    /// 排除式结束位置。
    #[serde(rename = "end")]
    end_position: PointRecord,
    /// Start and end byte offsets.
    /// 起止字节偏移。
    #[serde(rename = "byteOffset")]
    byte_offset: ByteOffsetRecord,
}

/// Describe one zero-based source point.
/// 描述一个从零开始的源码位置。
#[derive(Debug, Serialize)]
struct PointRecord {
    /// Zero-based line number.
    /// 从零开始的行号。
    line: usize,
    /// Zero-based character column.
    /// 从零开始的字符列号。
    column: usize,
}

/// Describe start and end byte offsets.
/// 描述起止字节偏移。
#[derive(Debug, Serialize)]
struct ByteOffsetRecord {
    /// Start byte offset.
    /// 起始字节偏移。
    start: usize,
    /// End byte offset.
    /// 结束字节偏移。
    #[serde(rename = "end")]
    end_offset: usize,
}

/// Return the crate version for loader diagnostics.
/// 返回 crate 版本，供加载器诊断使用。
#[no_mangle]
pub extern "C" fn vulcan_codekit_ast_grep_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr().cast()
}

/// Scan files using ast-grep rules and return one JSON response string.
/// 使用 ast-grep 规则扫描文件，并返回一个 JSON 响应字符串。
#[no_mangle]
pub extern "C" fn vulcan_codekit_ast_grep_scan_json(request_json: *const c_char) -> *mut c_char {
    let response = catch_unwind(AssertUnwindSafe(|| scan_json_impl(request_json)))
        .unwrap_or_else(|_| fatal_response("panic", "ast-grep FFI scan panicked"));
    response_to_c_string(response)
}

/// Free a response string allocated by `vulcan_codekit_ast_grep_scan_json`.
/// 释放由 `vulcan_codekit_ast_grep_scan_json` 分配的响应字符串。
#[no_mangle]
pub extern "C" fn vulcan_codekit_ast_grep_free_string(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(value));
    }
}

/// Decode the C request pointer and execute the scan.
/// 解码 C 请求指针并执行扫描。
fn scan_json_impl(request_json: *const c_char) -> ScanResponse {
    if request_json.is_null() {
        return fatal_response("null_request", "request_json must not be null");
    }

    let request_text = unsafe { CStr::from_ptr(request_json) };
    let request_text = match request_text.to_str() {
        Ok(value) => value,
        Err(error) => {
            return fatal_response(
                "invalid_request_utf8",
                format!("request_json is not valid UTF-8: {error}"),
            )
        }
    };

    execute_request(request_text)
}

/// Execute one decoded JSON request.
/// 执行一个已解码的 JSON 请求。
fn execute_request(request_text: &str) -> ScanResponse {
    let request: ScanRequest = match serde_json::from_str(request_text) {
        Ok(value) => value,
        Err(error) => {
            return fatal_response(
                "invalid_request_json",
                format!("failed to decode ast-grep FFI request JSON: {error}"),
            )
        }
    };

    let rule_yaml = match resolve_rule_yaml(&request) {
        Ok(value) => value,
        Err(response) => return response,
    };
    let rules = match from_yaml_string::<SupportLang>(&rule_yaml, &GlobalRules::default()) {
        Ok(value) => value,
        Err(error) => {
            return fatal_response(
                "invalid_rule_yaml",
                format!("failed to parse ast-grep rule YAML: {error}"),
            )
        }
    };
    if rules.is_empty() {
        return fatal_response(
            "empty_rule_yaml",
            "rule YAML did not contain any ast-grep rules",
        );
    }
    if request.files.is_empty() {
        return ScanResponse {
            ok: true,
            matches: Vec::new(),
            diagnostics: vec!["no_files_requested".to_string()],
            error: None,
            message: None,
        };
    }

    let language = match resolve_language(&request, &rules) {
        Ok(value) => value,
        Err(response) => return response,
    };
    scan_files(language, &rules, &request.files)
}

/// Resolve inline or file-based rule YAML from a request.
/// 从请求中解析内联或基于文件的规则 YAML。
fn resolve_rule_yaml(request: &ScanRequest) -> Result<String, ScanResponse> {
    if let Some(rule_yaml) = request
        .rule_yaml
        .as_deref()
        .or(request.inline_rule_yaml.as_deref())
    {
        if !rule_yaml.trim().is_empty() {
            return Ok(rule_yaml.to_string());
        }
    }

    let Some(rule_path) = request.rule_path.as_deref() else {
        return Err(fatal_response(
            "rule_yaml_missing",
            "request must provide ruleYaml, inlineRuleYaml, or rulePath",
        ));
    };
    fs::read_to_string(rule_path).map_err(|error| {
        fatal_response(
            "rule_yaml_read_failed",
            format!("failed to read ast-grep rule YAML `{rule_path}`: {error}"),
        )
    })
}

/// Resolve the language used to parse source files.
/// 解析用于解析源文件的语言。
fn resolve_language(
    request: &ScanRequest,
    rules: &[RuleConfig<SupportLang>],
) -> Result<SupportLang, ScanResponse> {
    if let Some(language) = request.language.as_deref() {
        if !language.trim().is_empty() {
            return language.parse::<SupportLang>().map_err(|error| {
                fatal_response(
                    "unsupported_language",
                    format!("unsupported ast-grep language `{language}`: {error}"),
                )
            });
        }
    }

    rules
        .first()
        .map(|rule| rule.language)
        .ok_or_else(|| fatal_response("empty_rule_yaml", "rule YAML did not contain any rules"))
}

/// Scan all requested files with the prepared ast-grep rule set.
/// 使用准备好的 ast-grep 规则集扫描所有请求文件。
fn scan_files(
    language: SupportLang,
    rules: &[RuleConfig<SupportLang>],
    files: &[String],
) -> ScanResponse {
    let rule_refs: Vec<&RuleConfig<SupportLang>> = rules.iter().collect();
    let scanner = CombinedScan::new(rule_refs);
    let mut matches = Vec::new();
    let mut diagnostics = Vec::new();

    for file_path in files {
        let source = match fs::read_to_string(file_path) {
            Ok(value) => value,
            Err(error) => {
                diagnostics.push(format!("file_read_failed:{file_path}:{error}"));
                continue;
            }
        };
        let document = match StrDoc::try_new(&source, language) {
            Ok(value) => value,
            Err(error) => {
                diagnostics.push(format!("file_parse_failed:{file_path}:{error}"));
                continue;
            }
        };
        let root: AstGrep<StrDoc<SupportLang>> = AstGrep::doc(document);
        let scanned = scanner.scan(&root, false);
        append_scan_matches(file_path, scanned.matches, &mut matches);
    }

    matches.sort_by(|left, right| {
        left.file
            .cmp(&right.file)
            .then(
                left.range
                    .byte_offset
                    .start
                    .cmp(&right.range.byte_offset.start),
            )
            .then(left.rule_id.cmp(&right.rule_id))
    });

    ScanResponse {
        ok: true,
        matches,
        diagnostics,
        error: None,
        message: None,
    }
}

/// Append ast-grep scan matches to the output list.
/// 将 ast-grep 扫描命中追加到输出列表。
fn append_scan_matches(
    file_path: &str,
    scanned_matches: Vec<(
        &RuleConfig<SupportLang>,
        Vec<NodeMatch<'_, StrDoc<SupportLang>>>,
    )>,
    output: &mut Vec<MatchRecord>,
) {
    for (rule, node_matches) in scanned_matches {
        let metadata = serialize_metadata(&rule.metadata);
        for node_match in node_matches {
            output.push(build_match_record(file_path, rule, &metadata, &node_match));
        }
    }
}

/// Build one normalized match record from ast-grep internals.
/// 从 ast-grep 内部数据构造一个规范化命中记录。
fn build_match_record(
    file_path: &str,
    rule: &RuleConfig<SupportLang>,
    metadata: &Map<String, Value>,
    node_match: &NodeMatch<'_, StrDoc<SupportLang>>,
) -> MatchRecord {
    let text = node_match.text().to_string();
    MatchRecord {
        rule_id: rule.id.clone(),
        file: normalize_output_path(file_path),
        range: build_range_record(node_match.get_node()),
        text: text.clone(),
        lines: text,
        node_kind: node_match.kind().to_string(),
        message: rule.get_message(node_match),
        metadata: metadata.clone(),
        meta_variables: build_meta_variables_record(node_match),
    }
}

/// Build captured metavariable records for one match.
/// 为单个命中构造捕获元变量记录。
fn build_meta_variables_record(
    node_match: &NodeMatch<'_, StrDoc<SupportLang>>,
) -> MetaVariablesRecord {
    let mut variables = MetaVariablesRecord::default();
    let env = node_match.get_env();

    for variable in env.get_matched_variables() {
        match variable {
            MetaVariable::Capture(name, _) => {
                if let Some(node) = env.get_match(&name) {
                    variables.single.insert(name, build_capture_record(node));
                }
            }
            MetaVariable::MultiCapture(name) => {
                let captures = env
                    .get_multiple_matches(&name)
                    .iter()
                    .map(build_capture_record)
                    .collect::<Vec<_>>();
                variables.multi.insert(name, captures);
            }
            MetaVariable::Dropped(_) | MetaVariable::Multiple => {}
        }
    }

    variables
}

/// Build one capture record from an ast-grep node.
/// 从 ast-grep 节点构造一个捕获记录。
fn build_capture_record<D>(node: &Node<'_, D>) -> CaptureRecord
where
    D: Doc,
{
    CaptureRecord {
        text: node.text().to_string(),
        range: build_range_record(node),
    }
}

/// Convert a node range to the JSON shape expected by Lua.
/// 将节点范围转换为 Lua 期望的 JSON 形态。
fn build_range_record<D>(node: &Node<'_, D>) -> RangeRecord
where
    D: Doc,
{
    let start = node.start_pos();
    let end = node.end_pos();
    let range = node.range();
    RangeRecord {
        start: PointRecord {
            line: start.line(),
            column: start.column(node),
        },
        end_position: PointRecord {
            line: end.line(),
            column: end.column(node),
        },
        byte_offset: ByteOffsetRecord {
            start: range.start,
            end_offset: range.end,
        },
    }
}

/// Serialize rule metadata into a mutable JSON object.
/// 将规则元数据序列化为可变 JSON 对象。
fn serialize_metadata(metadata: &Option<Metadata>) -> Map<String, Value> {
    let Some(metadata) = metadata else {
        return Map::new();
    };
    match serde_json::to_value(metadata) {
        Ok(Value::Object(map)) => map,
        _ => Map::new(),
    }
}

/// Normalize output paths without changing their identity.
/// 规范化输出路径但不改变其身份。
fn normalize_output_path(file_path: &str) -> String {
    Path::new(file_path).to_string_lossy().to_string()
}

/// Construct a fatal JSON response.
/// 构造一个致命错误 JSON 响应。
fn fatal_response(error: impl Into<String>, message: impl Into<String>) -> ScanResponse {
    ScanResponse {
        ok: false,
        matches: Vec::new(),
        diagnostics: Vec::new(),
        error: Some(error.into()),
        message: Some(message.into()),
    }
}

/// Convert a response object to an owned C string.
/// 将响应对象转换成拥有所有权的 C 字符串。
fn response_to_c_string(response: ScanResponse) -> *mut c_char {
    let json = match serde_json::to_string(&response) {
        Ok(value) => value,
        Err(error) => {
            format!(
                "{{\"ok\":false,\"matches\":[],\"diagnostics\":[],\"error\":\"response_encode_failed\",\"message\":\"{}\"}}",
                escape_json_string(&error.to_string())
            )
        }
    };
    CString::new(json)
        .map(CString::into_raw)
        .unwrap_or_else(|_| ptr::null_mut::<c_void>().cast())
}

/// Escape text for the fallback JSON encoder.
/// 为兜底 JSON 编码器转义文本。
fn escape_json_string(value: &str) -> String {
    value
        .chars()
        .flat_map(|character| match character {
            '"' => "\\\"".chars().collect::<Vec<_>>(),
            '\\' => "\\\\".chars().collect::<Vec<_>>(),
            '\n' => "\\n".chars().collect::<Vec<_>>(),
            '\r' => "\\r".chars().collect::<Vec<_>>(),
            '\t' => "\\t".chars().collect::<Vec<_>>(),
            current => vec![current],
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    /// Verify that kind-based Lua rules return normalized matches.
    /// 验证基于 kind 的 Lua 规则会返回规范化命中。
    #[test]
    fn scans_lua_function_rule() {
        let mut source = tempfile::NamedTempFile::new().expect("temp file should be created");
        writeln!(source, "local function demo(value)\n  return value\nend")
            .expect("temp source should be written");
        let rule_yaml = r#"
id: lua-function
language: Lua
severity: info
rule:
  kind: function_declaration
metadata:
  symbol_kind: function
  container: false
message: "function"
"#;
        let request = serde_json::json!({
            "language": "lua",
            "ruleYaml": rule_yaml,
            "files": [source.path().to_string_lossy()]
        });

        let response = execute_request(&request.to_string());

        assert!(response.ok);
        assert_eq!(response.matches.len(), 1);
        assert_eq!(
            response.matches[0]
                .metadata
                .get("symbol_kind")
                .and_then(Value::as_str),
            Some("function")
        );
    }

    /// Verify that pattern captures are exported for Lua normalization.
    /// 验证 pattern 捕获会导出给 Lua 归一化逻辑。
    #[test]
    fn exports_pattern_captures() {
        let mut source = tempfile::NamedTempFile::new().expect("temp file should be created");
        writeln!(source, "const run = (value) => {{ return value }};")
            .expect("temp source should be written");
        let rule_yaml = r#"
id: javascript-arrow-block
language: JavaScript
severity: info
rule:
  pattern:
    context: |
      const $NAME = ($$$PARAMS) => {
        $$$BODY
      }
    selector: variable_declarator
    strictness: signature
metadata:
  symbol_kind: function
  container: false
  name_capture: NAME
  params_capture: PARAMS
message: "function:$NAME"
"#;
        let request = serde_json::json!({
            "language": "javascript",
            "ruleYaml": rule_yaml,
            "files": [source.path().to_string_lossy()]
        });

        let response = execute_request(&request.to_string());

        assert!(response.ok);
        assert_eq!(response.matches.len(), 1);
        assert!(response.matches[0]
            .meta_variables
            .single
            .contains_key("NAME"));
    }
}
