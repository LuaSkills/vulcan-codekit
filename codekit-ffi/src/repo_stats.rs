//! Repository-scale directory and source statistics powered by Tokei.
//! 基于 Tokei 的仓库级目录与源码统计。

use std::collections::{BTreeMap, BTreeSet};
use std::ffi::CStr;
use std::fs;
use std::os::raw::c_char;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

use ignore::WalkBuilder;
use serde::{Deserialize, Serialize};
use tokei::{Config, Languages};

use crate::error::RepoStatsError;
use crate::path_policy::{
    directory_depth, display_canonical_path, is_hard_excluded_directory, normalize_relative_path,
    parent_directory, HARD_EXCLUDED_DIRECTORY_NAMES, TOKEI_HARD_EXCLUDE_PATTERNS,
};

/// Default model-visible directory depth.
/// 默认模型可见目录深度。
const DEFAULT_MAX_DEPTH: usize = 3;
/// Largest accepted model-visible directory depth.
/// 允许的最大模型可见目录深度。
const MAX_MAX_DEPTH: usize = 8;
/// Default maximum number of returned directory nodes.
/// 默认返回目录节点数量上限。
const DEFAULT_MAX_RENDERED_DIRECTORIES: usize = 2_000;
/// Absolute maximum number of returned directory nodes.
/// 返回目录节点数量的绝对上限。
const MAX_RENDERED_DIRECTORIES: usize = 10_000;
/// Maximum number of individual traversal diagnostics retained in one response.
/// 单次响应保留的目录遍历诊断数量上限。
const MAX_DIAGNOSTICS: usize = 100;
/// Stable repository-statistics protocol version.
/// 稳定的仓库统计协议版本。
pub(crate) const REPO_STATS_PROTOCOL_VERSION: &str = "1";
/// Exact Tokei version represented by the locked Cargo dependency.
/// Cargo 精确锁定依赖所对应的 Tokei 版本。
pub(crate) const TOKEI_ENGINE_VERSION: &str = "15.0.0";

/// Process-wide gate that prevents concurrent full-repository scans.
/// 防止多个全仓库扫描并发执行的进程级门限。
static REPO_SCAN_GATE: OnceLock<Mutex<()>> = OnceLock::new();

/// Describe one JSON repository-statistics request.
/// 描述一个 JSON 仓库统计请求。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct RepoStatsRequest {
    /// Repository or directory root to scan recursively.
    /// 需要递归扫描的仓库或目录根路径。
    root: String,
    /// Maximum directory depth returned to the caller.
    /// 返回给调用方的最大目录深度。
    max_depth: Option<usize>,
    /// Whether hidden files such as `.github` participate in the scan.
    /// `.github` 等隐藏文件是否参与扫描。
    include_hidden: Option<bool>,
    /// Whether `.gitignore`, `.ignore`, and `.tokeignore` are respected.
    /// 是否遵循 `.gitignore`、`.ignore` 与 `.tokeignore`。
    respect_ignore: Option<bool>,
    /// Maximum number of directory records serialized into the response.
    /// 序列化到响应中的目录记录数量上限。
    max_rendered_directories: Option<usize>,
}

/// Hold one validated repository-statistics request.
/// 保存一个经过校验的仓库统计请求。
#[derive(Debug)]
struct ValidatedRequest {
    /// Canonical repository root.
    /// 规范化后的仓库根路径。
    root: PathBuf,
    /// Stable display form of the canonical repository root.
    /// 规范化仓库根路径的稳定展示文本。
    root_display: String,
    /// Maximum returned directory depth.
    /// 最大返回目录深度。
    max_depth: usize,
    /// Whether hidden entries participate in the scan.
    /// 隐藏目录项是否参与扫描。
    include_hidden: bool,
    /// Whether ordinary ignore files are respected.
    /// 是否遵循普通 ignore 文件。
    respect_ignore: bool,
    /// Maximum returned directory record count.
    /// 最大返回目录记录数量。
    max_rendered_directories: usize,
}

/// Count files, bytes, and Tokei source lines for one scope.
/// 统计一个范围内的文件、字节与 Tokei 源码行。
#[derive(Clone, Debug, Default)]
struct AggregateCounts {
    /// All ordinary files after ignore policies are applied.
    /// 应用忽略策略后的全部普通文件数量。
    files: u64,
    /// Files recognized by Tokei.
    /// 被 Tokei 识别的文件数量。
    recognized_files: u64,
    /// Total byte size of all ordinary files.
    /// 全部普通文件的总字节数。
    bytes: u64,
    /// Tokei code-line count.
    /// Tokei 代码行数量。
    code: u64,
    /// Tokei comment-line count.
    /// Tokei 注释行数量。
    comments: u64,
    /// Tokei blank-line count.
    /// Tokei 空行数量。
    blanks: u64,
}

impl AggregateCounts {
    /// Add another aggregate with checked arithmetic.
    /// 使用受检查算术累加另一个统计聚合。
    ///
    /// # Parameters / 参数
    /// - `other`: Aggregate that should be added to the current scope.
    /// - `other`：需要累加到当前范围的统计聚合。
    ///
    /// # Returns / 返回值
    /// Success, or a stable overflow error.
    /// 成功结果，或稳定的溢出错误。
    fn checked_add_assign(&mut self, other: &Self) -> Result<(), RepoStatsError> {
        self.files = checked_add(self.files, other.files, "files")?;
        self.recognized_files = checked_add(
            self.recognized_files,
            other.recognized_files,
            "recognizedFiles",
        )?;
        self.bytes = checked_add(self.bytes, other.bytes, "bytes")?;
        self.code = checked_add(self.code, other.code, "code")?;
        self.comments = checked_add(self.comments, other.comments, "comments")?;
        self.blanks = checked_add(self.blanks, other.blanks, "blanks")?;
        Ok(())
    }

    /// Return the sum of code, comments, and blank lines.
    /// 返回代码、注释与空行之和。
    ///
    /// # Returns / 返回值
    /// Total Tokei-recognized line count.
    /// Tokei 识别出的总行数。
    fn lines(&self) -> Result<u64, RepoStatsError> {
        // Combine the three Tokei-exclusive line categories without silent saturation.
        // 合并三个互斥的 Tokei 行类别，禁止静默饱和。
        let code_and_comments = checked_add(self.code, self.comments, "lines")?;
        checked_add(code_and_comments, self.blanks, "lines")
    }

    /// Return the number of files not recognized by Tokei.
    /// 返回未被 Tokei 识别的文件数量。
    ///
    /// # Returns / 返回值
    /// Difference between all files and recognized files.
    /// 全部文件与已识别文件的差值。
    fn unrecognized_files(&self) -> Result<u64, RepoStatsError> {
        self.files
            .checked_sub(self.recognized_files)
            .ok_or_else(|| {
                RepoStatsError::new(
                    "invalid_recognized_file_count",
                    "recognized file count exceeded the complete file census",
                )
            })
    }
}

/// Accumulate one language inside a direct or recursive directory scope.
/// 聚合一个语言在目录直接范围或递归范围内的统计。
#[derive(Clone, Debug, Default)]
struct LanguageAccumulator {
    /// Number of primary files reported for the language.
    /// 该语言报告的主文件数量。
    files: u64,
    /// Tokei statistics including summarized embedded-language blobs.
    /// 包含内嵌语言汇总的 Tokei 统计。
    counts: AggregateCounts,
    /// Whether Tokei marked this language as potentially inaccurate.
    /// Tokei 是否将该语言标记为可能不准确。
    inaccurate: bool,
}

impl LanguageAccumulator {
    /// Merge another language accumulator into this scope.
    /// 将另一个语言聚合合并到当前范围。
    ///
    /// # Parameters / 参数
    /// - `other`: Language aggregate from a child scope.
    /// - `other`：来自子范围的语言聚合。
    ///
    /// # Returns / 返回值
    /// Success, or a stable overflow error.
    /// 成功结果，或稳定的溢出错误。
    fn checked_add_assign(&mut self, other: &Self) -> Result<(), RepoStatsError> {
        self.files = checked_add(self.files, other.files, "language.files")?;
        self.counts.checked_add_assign(&other.counts)?;
        self.inaccurate |= other.inaccurate;
        Ok(())
    }
}

/// Hold direct and recursive statistics for one directory.
/// 保存一个目录的直接统计与递归统计。
#[derive(Clone, Debug)]
struct DirectoryAccumulator {
    /// Stable normalized parent path, absent only for the root.
    /// 稳定规范化父路径，仅根目录为空。
    parent_path: Option<String>,
    /// Number of direct child directories.
    /// 直接子目录数量。
    direct_directories: u64,
    /// Number of recursive descendant directories, excluding this directory.
    /// 递归后代目录数量，不包含当前目录自身。
    total_directories: u64,
    /// Direct file and source statistics.
    /// 当前目录直接文件与源码统计。
    direct: AggregateCounts,
    /// Recursive file and source statistics including the current directory.
    /// 包含当前目录的递归文件与源码统计。
    total: AggregateCounts,
    /// Direct language statistics.
    /// 当前目录直接语言统计。
    direct_languages: BTreeMap<String, LanguageAccumulator>,
    /// Recursive language statistics.
    /// 当前目录递归语言统计。
    total_languages: BTreeMap<String, LanguageAccumulator>,
    /// Whether any Tokei language in the subtree was marked inaccurate.
    /// 子树内是否存在被 Tokei 标记为不准确的语言。
    inaccurate: bool,
}

impl DirectoryAccumulator {
    /// Construct an empty directory accumulator.
    /// 构造一个空目录聚合器。
    ///
    /// # Parameters / 参数
    /// - `parent_path`: Stable parent path or `None` for the root.
    /// - `parent_path`：稳定父路径，根目录使用 `None`。
    ///
    /// # Returns / 返回值
    /// An empty direct and recursive directory accumulator.
    /// 一个空的目录直接与递归统计聚合器。
    fn new(parent_path: Option<String>) -> Self {
        Self {
            parent_path,
            direct_directories: 0,
            total_directories: 0,
            direct: AggregateCounts::default(),
            total: AggregateCounts::default(),
            direct_languages: BTreeMap::new(),
            total_languages: BTreeMap::new(),
            inaccurate: false,
        }
    }
}

/// Describe the statistics engine and public protocol versions.
/// 描述统计引擎与公共协议版本。
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct EngineInfo {
    /// CodeKit dynamic-library version.
    /// CodeKit 动态库版本。
    codekit_ffi: &'static str,
    /// Tokei statistics-engine version.
    /// Tokei 统计引擎版本。
    tokei: &'static str,
    /// Repository-statistics protocol version.
    /// 仓库统计协议版本。
    protocol: &'static str,
}

/// Describe the effective scan policy applied to one request.
/// 描述一次请求实际应用的扫描策略。
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ScopeInfo {
    /// Whether hidden entries participated in the scan.
    /// 隐藏目录项是否参与扫描。
    include_hidden: bool,
    /// Whether ordinary ignore files were respected.
    /// 是否遵循普通 ignore 文件。
    respect_ignore: bool,
    /// Whether symbolic links were followed.
    /// 是否跟随符号链接。
    follow_symlinks: bool,
    /// Directory basenames excluded regardless of ignore settings.
    /// 不受 ignore 设置影响而始终排除的目录基础名称。
    hard_excludes: Vec<&'static str>,
}

/// Describe aggregate repository or directory counts in the public response.
/// 描述公共响应中的仓库或目录聚合统计。
#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct PublicCounts {
    /// All ordinary files after ignore policies.
    /// 应用忽略策略后的全部普通文件数量。
    files: u64,
    /// Files recognized by Tokei.
    /// 被 Tokei 识别的文件数量。
    recognized_files: u64,
    /// Files not recognized by Tokei.
    /// 未被 Tokei 识别的文件数量。
    unrecognized_files: u64,
    /// Total byte size of all ordinary files.
    /// 全部普通文件总字节数。
    bytes: u64,
    /// Sum of code, comments, and blank lines.
    /// 代码、注释与空行的总和。
    lines: u64,
    /// Tokei code-line count.
    /// Tokei 代码行数量。
    code: u64,
    /// Tokei comment-line count.
    /// Tokei 注释行数量。
    comments: u64,
    /// Tokei blank-line count.
    /// Tokei 空行数量。
    blanks: u64,
}

/// Describe complete repository totals.
/// 描述完整仓库总量。
#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct RepositoryTotals {
    /// Number of scanned directories including the root.
    /// 扫描目录数量，包含根目录。
    directories: u64,
    /// Flattened public file and line counts.
    /// 展平后的公共文件与行数统计。
    #[serde(flatten)]
    counts: PublicCounts,
}

/// Describe one language summary returned to Lua.
/// 描述一个返回给 Lua 的语言摘要。
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct LanguageStats {
    /// Tokei language display name.
    /// Tokei 语言展示名称。
    name: String,
    /// Number of primary files for the language.
    /// 该语言的主文件数量。
    files: u64,
    /// Sum of code, comments, and blank lines.
    /// 代码、注释与空行的总和。
    lines: u64,
    /// Tokei code-line count including summarized embedded blobs.
    /// 包含内嵌代码块汇总的 Tokei 代码行数量。
    code: u64,
    /// Tokei comment-line count including summarized embedded blobs.
    /// 包含内嵌代码块汇总的 Tokei 注释行数量。
    comments: u64,
    /// Tokei blank-line count including summarized embedded blobs.
    /// 包含内嵌代码块汇总的 Tokei 空行数量。
    blanks: u64,
    /// Whether Tokei marked the language as potentially inaccurate.
    /// Tokei 是否将该语言标记为可能不准确。
    inaccurate: bool,
}

/// Describe one model-visible directory and its recursive statistics.
/// 描述一个模型可见目录及其递归统计。
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct DirectoryStats {
    /// Stable root-relative path using `/` separators.
    /// 使用 `/` 分隔符的稳定根目录相对路径。
    path: String,
    /// Directory depth where the root is zero.
    /// 目录深度，根目录为零。
    depth: usize,
    /// Stable parent path, absent only for the root.
    /// 稳定父路径，仅根目录为空。
    #[serde(skip_serializing_if = "Option::is_none")]
    parent_path: Option<String>,
    /// Number of direct child directories before output folding.
    /// 输出折叠前的直接子目录数量。
    direct_directories: u64,
    /// Number of recursive descendant directories, excluding self.
    /// 递归后代目录数量，不包含自身。
    total_directories: u64,
    /// Number of direct ordinary files.
    /// 直接普通文件数量。
    direct_files: u64,
    /// Number of recursive ordinary files.
    /// 递归普通文件数量。
    total_files: u64,
    /// Number of recursive files recognized by Tokei.
    /// 递归范围内被 Tokei 识别的文件数量。
    recognized_files: u64,
    /// Number of recursive files not recognized by Tokei.
    /// 递归范围内未被 Tokei 识别的文件数量。
    unrecognized_files: u64,
    /// Recursive byte size of all ordinary files.
    /// 递归范围内全部普通文件的字节数。
    bytes: u64,
    /// Recursive sum of code, comments, and blank lines.
    /// 递归范围内代码、注释与空行的总和。
    lines: u64,
    /// Recursive Tokei code-line count.
    /// 递归范围内 Tokei 代码行数量。
    code: u64,
    /// Recursive Tokei comment-line count.
    /// 递归范围内 Tokei 注释行数量。
    comments: u64,
    /// Recursive Tokei blank-line count.
    /// 递归范围内 Tokei 空行数量。
    blanks: u64,
    /// Recursive language distribution sorted by name.
    /// 按名称排序的递归语言分布。
    languages: Vec<LanguageStats>,
    /// Number of descendant directory records omitted from the response.
    /// 响应中省略的后代目录记录数量。
    collapsed_descendants: u64,
    /// Whether any language in the subtree was marked inaccurate.
    /// 子树内是否存在被标记为不准确的语言。
    inaccurate: bool,
}

/// Describe display-depth and record-count limits applied after a complete scan.
/// 描述完整扫描后应用的展示深度与记录数量限制。
#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct RenderLimit {
    /// Requested maximum directory depth.
    /// 请求的最大目录深度。
    max_depth: usize,
    /// Requested maximum number of returned directory records.
    /// 请求的最大返回目录记录数量。
    max_rendered_directories: usize,
    /// Number of directory records returned.
    /// 实际返回目录记录数量。
    returned_directories: usize,
    /// Complete number of scanned directories.
    /// 完整扫描目录数量。
    total_directories: usize,
    /// Whether one or more directory records were folded.
    /// 是否折叠了一个或多个目录记录。
    truncated: bool,
}

/// Describe one complete repository-statistics response.
/// 描述一个完整的仓库统计响应。
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct RepoStatsResponse {
    /// Whether the request completed successfully.
    /// 请求是否成功完成。
    ok: bool,
    /// Canonical repository root display path.
    /// 规范化仓库根目录展示路径。
    root: String,
    /// Engine and protocol version information.
    /// 引擎与协议版本信息。
    engine: EngineInfo,
    /// Effective scan policy.
    /// 实际扫描策略。
    scope: ScopeInfo,
    /// Complete repository totals.
    /// 完整仓库总量。
    totals: RepositoryTotals,
    /// Complete repository language distribution.
    /// 完整仓库语言分布。
    languages: Vec<LanguageStats>,
    /// Model-visible directory records.
    /// 模型可见目录记录。
    directories: Vec<DirectoryStats>,
    /// Non-fatal diagnostics and explicit omissions.
    /// 非致命诊断与显式省略说明。
    diagnostics: Vec<String>,
    /// Whether any scan result may be inaccurate.
    /// 扫描结果是否可能不准确。
    inaccurate: bool,
    /// Applied rendering limits.
    /// 实际应用的渲染限制。
    render_limit: RenderLimit,
    /// Stable fatal error code.
    /// 稳定的致命错误码。
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<&'static str>,
    /// Human-readable fatal error explanation.
    /// 人类可读的致命错误说明。
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
}

/// Decode and execute one raw C ABI repository-statistics request.
/// 解码并执行一个原始 C ABI 仓库统计请求。
///
/// # Parameters / 参数
/// - `request_json`: UTF-8 JSON request pointer supplied by LuaJIT FFI.
/// - `request_json`：由 LuaJIT FFI 提供的 UTF-8 JSON 请求指针。
///
/// # Returns / 返回值
/// A typed success or failure response ready for JSON serialization.
/// 一个可直接序列化为 JSON 的类型化成功或失败响应。
pub(crate) fn execute_c_request(request_json: *const c_char) -> RepoStatsResponse {
    if request_json.is_null() {
        return failure_response(RepoStatsError::new(
            "null_request",
            "request_json must not be null",
        ));
    }

    // Borrow the NUL-terminated request only for the duration of this call.
    // 仅在本次调用期间借用以 NUL 结尾的请求。
    let request_bytes = unsafe { CStr::from_ptr(request_json) };
    // Validate UTF-8 before attempting JSON decoding.
    // 在尝试 JSON 解码前验证 UTF-8。
    let request_text = match request_bytes.to_str() {
        Ok(value) => value,
        Err(error) => {
            return failure_response(RepoStatsError::new(
                "invalid_request_utf8",
                format!("request_json is not valid UTF-8: {error}"),
            ));
        }
    };

    execute_request_text(request_text)
}

/// Execute one UTF-8 JSON repository-statistics request.
/// 执行一个 UTF-8 JSON 仓库统计请求。
///
/// # Parameters / 参数
/// - `request_text`: JSON request body.
/// - `request_text`：JSON 请求正文。
///
/// # Returns / 返回值
/// A typed success or failure response.
/// 一个类型化的成功或失败响应。
fn execute_request_text(request_text: &str) -> RepoStatsResponse {
    // Decode only the CodeKit-owned protocol, rejecting speculative fields.
    // 仅解码 CodeKit 自有协议，并拒绝投机性字段。
    let request = match serde_json::from_str::<RepoStatsRequest>(request_text) {
        Ok(value) => value,
        Err(error) => {
            return failure_response(RepoStatsError::new(
                "invalid_request_json",
                format!("failed to decode repository statistics request JSON: {error}"),
            ));
        }
    };

    // Validate path and bounds before acquiring the expensive scan gate.
    // 在获取高成本扫描门限前先校验路径与边界。
    let validated = match validate_request(request) {
        Ok(value) => value,
        Err(error) => return failure_response(error),
    };

    // Serialize complete scans to prevent full-repository CPU and disk contention.
    // 串行化完整扫描，避免全仓库 CPU 与磁盘争抢。
    let gate = REPO_SCAN_GATE.get_or_init(|| Mutex::new(()));
    // Treat a poisoned gate as an explicit failure instead of silently continuing.
    // 将被污染的门限视为显式失败，禁止静默继续。
    let scan_guard = match gate.lock() {
        Ok(value) => value,
        Err(error) => {
            return failure_response(RepoStatsError::new(
                "scan_gate_poisoned",
                format!("repository scan gate was poisoned: {error}"),
            ));
        }
    };

    // Keep the guard alive until both census and Tokei aggregation complete.
    // 保持门限直到目录普查与 Tokei 聚合全部完成。
    let response = match build_repository_stats(&validated) {
        Ok(value) => value,
        Err(error) => failure_response(error),
    };
    drop(scan_guard);
    response
}

/// Serialize one repository-statistics response with a stable fatal fallback.
/// 序列化一个仓库统计响应，并提供稳定的致命错误回退。
///
/// # Parameters / 参数
/// - `response`: Typed repository-statistics response.
/// - `response`：类型化仓库统计响应。
///
/// # Returns / 返回值
/// UTF-8 JSON text suitable for crossing the C ABI.
/// 适合跨越 C ABI 的 UTF-8 JSON 文本。
pub(crate) fn serialize_response(response: &RepoStatsResponse) -> String {
    serde_json::to_string(response).unwrap_or_else(|error| {
        // The fallback is hand-constructed only after typed serialization fails.
        // 仅在类型化序列化失败后手工构造回退响应。
        let escaped_message = escape_json_string(&error.to_string());
        format!(
            "{{\"ok\":false,\"root\":\"\",\"engine\":{{\"codekitFfi\":\"{}\",\"tokei\":\"{}\",\"protocol\":\"{}\"}},\"scope\":{{\"includeHidden\":true,\"respectIgnore\":true,\"followSymlinks\":false,\"hardExcludes\":[]}},\"totals\":{{\"directories\":0,\"files\":0,\"recognizedFiles\":0,\"unrecognizedFiles\":0,\"bytes\":0,\"lines\":0,\"code\":0,\"comments\":0,\"blanks\":0}},\"languages\":[],\"directories\":[],\"diagnostics\":[],\"inaccurate\":true,\"renderLimit\":{{\"maxDepth\":0,\"maxRenderedDirectories\":0,\"returnedDirectories\":0,\"totalDirectories\":0,\"truncated\":false}},\"error\":\"response_encode_failed\",\"message\":\"{}\"}}",
            env!("CARGO_PKG_VERSION"),
            TOKEI_ENGINE_VERSION,
            REPO_STATS_PROTOCOL_VERSION,
            escaped_message
        )
    })
}

/// Construct an explicit panic response for the public FFI boundary.
/// 为公共 FFI 边界构造显式 panic 响应。
///
/// # Returns / 返回值
/// A stable fatal response that contains no Rust panic payload.
/// 一个不包含 Rust panic 载荷的稳定致命响应。
pub(crate) fn panic_response() -> RepoStatsResponse {
    failure_response(RepoStatsError::new(
        "panic",
        "repository statistics scan panicked",
    ))
}

/// Validate request fields and canonicalize the repository root.
/// 校验请求字段并规范化仓库根目录。
///
/// # Parameters / 参数
/// - `request`: Decoded public request.
/// - `request`：解码后的公共请求。
///
/// # Returns / 返回值
/// A validated request, or a stable validation error.
/// 一个已校验请求，或稳定的校验错误。
fn validate_request(request: RepoStatsRequest) -> Result<ValidatedRequest, RepoStatsError> {
    if request.root.trim().is_empty() {
        return Err(RepoStatsError::new(
            "invalid_root",
            "root must be a non-empty directory path",
        ));
    }

    // Resolve the exact requested path before checking directory identity.
    // 在检查目录身份前解析精确请求路径。
    let requested_root = PathBuf::from(request.root.trim());
    if !requested_root.is_dir() {
        return Err(RepoStatsError::new(
            "root_not_directory",
            format!(
                "repository statistics root is not an existing directory: {}",
                requested_root.display()
            ),
        ));
    }

    // Canonicalization gives Tokei and the directory census one shared path identity.
    // 规范化使 Tokei 与目录普查共享同一个路径身份。
    let root = fs::canonicalize(&requested_root).map_err(|error| {
        RepoStatsError::new(
            "root_canonicalize_failed",
            format!(
                "failed to canonicalize repository root `{}`: {error}",
                requested_root.display()
            ),
        )
    })?;
    // Use the canonical path as the stable response root.
    // 使用规范路径作为稳定响应根目录。
    let root_display = display_canonical_path(&root);
    // Apply the documented default directory depth.
    // 应用文档约定的默认目录深度。
    let max_depth = request.max_depth.unwrap_or(DEFAULT_MAX_DEPTH);
    if !(1..=MAX_MAX_DEPTH).contains(&max_depth) {
        return Err(RepoStatsError::new(
            "invalid_max_depth",
            format!("maxDepth must be between 1 and {MAX_MAX_DEPTH}"),
        ));
    }

    // Apply the documented default response-node limit.
    // 应用文档约定的默认响应节点上限。
    let max_rendered_directories = request
        .max_rendered_directories
        .unwrap_or(DEFAULT_MAX_RENDERED_DIRECTORIES);
    if !(1..=MAX_RENDERED_DIRECTORIES).contains(&max_rendered_directories) {
        return Err(RepoStatsError::new(
            "invalid_max_rendered_directories",
            format!("maxRenderedDirectories must be between 1 and {MAX_RENDERED_DIRECTORIES}"),
        ));
    }

    Ok(ValidatedRequest {
        root,
        root_display,
        max_depth,
        include_hidden: request.include_hidden.unwrap_or(true),
        respect_ignore: request.respect_ignore.unwrap_or(true),
        max_rendered_directories,
    })
}

/// Build a complete response from one validated request.
/// 根据一个已校验请求构建完整响应。
///
/// # Parameters / 参数
/// - `request`: Validated scan policy and canonical root.
/// - `request`：已校验扫描策略与规范根目录。
///
/// # Returns / 返回值
/// Complete repository statistics, or a stable failure.
/// 完整仓库统计，或稳定失败。
fn build_repository_stats(request: &ValidatedRequest) -> Result<RepoStatsResponse, RepoStatsError> {
    // Collect explicit non-fatal traversal diagnostics.
    // 收集显式的非致命遍历诊断。
    let mut diagnostics = Vec::new();
    // Census every non-ignored directory and ordinary file without reading source contents.
    // 在不读取源码正文的情况下普查每个未忽略目录与普通文件。
    let mut directories = build_directory_census(request, &mut diagnostics)?;
    // Run Tokei once for the complete root.
    // 对完整根目录只运行一次 Tokei。
    apply_tokei_statistics(request, &mut directories, &mut diagnostics)?;
    // Aggregate direct directory statistics from leaves to the root.
    // 将目录直接统计自叶节点向根目录聚合。
    aggregate_directories(&mut directories)?;
    // Build the final model-visible records after full statistics are complete.
    // 在完整统计完成后构建最终模型可见记录。
    let (directory_records, render_limit) = render_directories(request, &directories)?;
    // Read the root aggregate as the complete repository total.
    // 读取根目录聚合作为完整仓库总量。
    let root_accumulator = directories.get(".").ok_or_else(|| {
        RepoStatsError::new(
            "root_aggregate_missing",
            "repository root aggregate was not produced",
        )
    })?;
    // Convert root counts into the public schema.
    // 将根目录统计转换为公共协议结构。
    let root_counts = public_counts(&root_accumulator.total)?;
    // Convert the stable map into sorted language records.
    // 将稳定映射转换为排序后的语言记录。
    let language_records = public_languages(&root_accumulator.total_languages)?;
    // Determine the overall inaccuracy flag from Tokei and traversal diagnostics.
    // 根据 Tokei 与遍历诊断确定整体不准确标记。
    let inaccurate = root_accumulator.inaccurate || !diagnostics.is_empty();
    // Convert the complete directory count without silent truncation.
    // 在不静默截断的前提下转换完整目录数量。
    let directory_count = u64::try_from(directories.len()).map_err(|error| {
        RepoStatsError::new(
            "directory_count_overflow",
            format!("directory count does not fit into u64: {error}"),
        )
    })?;

    Ok(RepoStatsResponse {
        ok: true,
        root: request.root_display.clone(),
        engine: engine_info(),
        scope: scope_info(request.include_hidden, request.respect_ignore),
        totals: RepositoryTotals {
            directories: directory_count,
            counts: root_counts,
        },
        languages: language_records,
        directories: directory_records,
        diagnostics,
        inaccurate,
        render_limit,
        error: None,
        message: None,
    })
}

/// Build a metadata-only census of directories and ordinary files.
/// 构建仅包含目录与普通文件元数据的普查结果。
///
/// # Parameters / 参数
/// - `request`: Validated scan request.
/// - `request`：已校验扫描请求。
/// - `diagnostics`: Bounded non-fatal diagnostic sink.
/// - `diagnostics`：有界非致命诊断接收器。
///
/// # Returns / 返回值
/// Stable directory accumulators containing direct file counts and bytes.
/// 包含直接文件数与字节数的稳定目录聚合映射。
fn build_directory_census(
    request: &ValidatedRequest,
    diagnostics: &mut Vec<String>,
) -> Result<BTreeMap<String, DirectoryAccumulator>, RepoStatsError> {
    // Configure the ignore walker from the same explicit request policy used by Tokei.
    // 使用与 Tokei 相同的显式请求策略配置 ignore 遍历器。
    let mut builder = WalkBuilder::new(&request.root);
    builder
        .hidden(!request.include_hidden)
        .parents(request.respect_ignore)
        .ignore(request.respect_ignore)
        .git_global(request.respect_ignore)
        .git_ignore(request.respect_ignore)
        .git_exclude(request.respect_ignore)
        .follow_links(false);
    if request.respect_ignore {
        // Custom ignore files stay active independently in the ignore crate, so register them only when requested.
        // ignore crate 会独立启用自定义忽略文件，因此仅在请求遵循 ignore 时注册。
        builder.add_custom_ignore_filename(".tokeignore");
    }
    builder.filter_entry(|entry| {
        if entry.depth() == 0 {
            return true;
        }
        if entry
            .file_type()
            .is_some_and(|file_type| file_type.is_dir())
        {
            return !is_hard_excluded_directory(&entry.file_name().to_string_lossy());
        }
        true
    });

    // Seed the root even when it contains no children.
    // 即使根目录没有子项也预先创建根节点。
    let mut directories = BTreeMap::new();
    directories.insert(".".to_string(), DirectoryAccumulator::new(None));
    for entry_result in builder.build() {
        // Preserve non-fatal traversal errors without aborting all useful statistics.
        // 保留非致命遍历错误，同时不中止全部可用统计。
        let entry = match entry_result {
            Ok(value) => value,
            Err(error) => {
                push_diagnostic(diagnostics, format!("walk_error:{error}"));
                continue;
            }
        };

        if entry.depth() == 0 {
            continue;
        }

        // Normalize the walker path before storing it in protocol state.
        // 在写入协议状态前规范化遍历路径。
        let relative_path = normalize_relative_path(&request.root, entry.path())?;
        // Use explicit file type information without following symbolic links.
        // 使用不跟随符号链接的显式文件类型信息。
        let file_type = match entry.file_type() {
            Some(value) => value,
            None => {
                push_diagnostic(
                    diagnostics,
                    format!("file_type_unavailable:{relative_path}"),
                );
                continue;
            }
        };

        if file_type.is_dir() {
            // Record every directory, including those that contain no recognized source files.
            // 记录每个目录，包括没有可识别源码文件的目录。
            directories
                .entry(relative_path.clone())
                .or_insert_with(|| DirectoryAccumulator::new(parent_directory(&relative_path)));
            continue;
        }

        if !file_type.is_file() {
            continue;
        }

        // Resolve the owning normalized directory from the file path.
        // 从文件路径解析所属规范化目录。
        let owner_path = parent_directory(&relative_path).unwrap_or_else(|| ".".to_string());
        // Ensure the owner exists even if a platform walker omits an intermediate callback.
        // 即使平台遍历器省略中间回调也确保所属目录存在。
        let owner = directories
            .entry(owner_path.clone())
            .or_insert_with(|| DirectoryAccumulator::new(parent_directory(&owner_path)));
        owner.direct.files = checked_add(owner.direct.files, 1, "files")?;

        // Read only filesystem metadata; source contents remain untouched.
        // 仅读取文件系统元数据，不读取源码正文。
        match entry.metadata() {
            Ok(metadata) => {
                owner.direct.bytes = checked_add(owner.direct.bytes, metadata.len(), "bytes")?;
            }
            Err(error) => {
                push_diagnostic(
                    diagnostics,
                    format!("metadata_read_failed:{relative_path}:{error}"),
                );
            }
        }
    }

    // Count direct directory relationships only after the complete directory set is known.
    // 仅在完整目录集合已知后统计直接目录关系。
    let directory_paths = directories.keys().cloned().collect::<Vec<_>>();
    for path in directory_paths {
        // Skip the root because it has no parent directory record.
        // 跳过没有父目录记录的根节点。
        let Some(parent_path) = parent_directory(&path) else {
            continue;
        };
        // Every normalized child must resolve to a census parent.
        // 每个规范化子目录都必须解析到一个普查父目录。
        let parent = directories.get_mut(&parent_path).ok_or_else(|| {
            RepoStatsError::new(
                "directory_parent_missing",
                format!("directory `{path}` references missing parent `{parent_path}`"),
            )
        })?;
        parent.direct_directories = checked_add(parent.direct_directories, 1, "directDirectories")?;
    }

    Ok(directories)
}

/// Apply one complete Tokei scan to the directory census.
/// 将一次完整 Tokei 扫描应用到目录普查结果。
///
/// # Parameters / 参数
/// - `request`: Validated scan request.
/// - `request`：已校验扫描请求。
/// - `directories`: Directory census to enrich.
/// - `directories`：需要增强的目录普查映射。
/// - `diagnostics`: Bounded non-fatal diagnostic sink.
/// - `diagnostics`：有界非致命诊断接收器。
///
/// # Returns / 返回值
/// Success, or a stable path/count failure.
/// 成功结果，或稳定的路径/计数失败。
fn apply_tokei_statistics(
    request: &ValidatedRequest,
    directories: &mut BTreeMap<String, DirectoryAccumulator>,
    diagnostics: &mut Vec<String>,
) -> Result<(), RepoStatsError> {
    // Build an explicit configuration that never reads user or project Tokei config files.
    // 构建不读取用户或项目 Tokei 配置文件的显式配置。
    let config = Config {
        hidden: Some(request.include_hidden),
        no_ignore: Some(!request.respect_ignore),
        no_ignore_parent: Some(!request.respect_ignore),
        no_ignore_dot: Some(!request.respect_ignore),
        no_ignore_vcs: Some(!request.respect_ignore),
        types: None,
        ..Config::default()
    };
    // Initialize the Tokei language collection once for the entire root.
    // 为整个根目录仅初始化一次 Tokei 语言集合。
    let mut languages = Languages::new();
    // Borrow hard-exclude patterns in Tokei's required string-slice form.
    // 以 Tokei 所需的字符串切片形式借用强制排除模式。
    let ignored = TOKEI_HARD_EXCLUDE_PATTERNS.as_slice();
    languages.get_statistics(&[request.root.as_path()], ignored, &config);

    // Track recognized paths so each physical file contributes once to recognized-file totals.
    // 跟踪已识别路径，确保每个物理文件只对已识别文件总量贡献一次。
    let mut recognized_paths = BTreeSet::new();
    for (language_type, language) in &languages {
        // Use Tokei's stable language display implementation.
        // 使用 Tokei 的稳定语言展示实现。
        let language_name = language_type.to_string();
        if language.inaccurate {
            // Preserve language-level parse failures even when Tokei emitted no successful file report.
            // 即使 Tokei 没有成功文件报告，也保留语言级解析失败状态。
            let root = directories.get_mut(".").ok_or_else(|| {
                RepoStatsError::new(
                    "root_aggregate_missing",
                    "repository root aggregate was unavailable during Tokei scan",
                )
            })?;
            root.inaccurate = true;
            push_diagnostic(
                diagnostics,
                format!("tokei_language_inaccurate:{language_name}"),
            );
        }
        for report in &language.reports {
            // Resolve every report to the same canonical root identity as the census.
            // 将每个报告解析到与目录普查相同的规范根目录身份。
            let report_path = resolve_report_path(&request.root, &report.name)?;
            // Normalize the report path for stable joining and protocol output.
            // 规范化报告路径，以便稳定关联与协议输出。
            let relative_path = normalize_relative_path(&request.root, &report_path)?;
            // Ignore a Tokei report that is absent from the complete census, but report the mismatch.
            // 忽略不在完整普查中的 Tokei 报告，同时显式报告口径不一致。
            let owner_path = parent_directory(&relative_path).unwrap_or_else(|| ".".to_string());
            let Some(owner) = directories.get_mut(&owner_path) else {
                push_diagnostic(
                    diagnostics,
                    format!("tokei_report_directory_missing:{relative_path}"),
                );
                continue;
            };

            // Summarize embedded language blobs exactly once into the primary file total.
            // 将内嵌语言代码块恰好一次汇总到主文件总量。
            let summarized = report.stats.summarise();
            // Convert platform-sized Tokei counters before crossing the stable u64 protocol.
            // 在跨越稳定 u64 协议前转换平台相关大小的 Tokei 计数。
            let code = usize_to_u64(summarized.code, "code")?;
            let comments = usize_to_u64(summarized.comments, "comments")?;
            let blanks = usize_to_u64(summarized.blanks, "blanks")?;

            if recognized_paths.insert(relative_path.clone()) {
                owner.direct.recognized_files =
                    checked_add(owner.direct.recognized_files, 1, "recognizedFiles")?;
            }
            owner.direct.code = checked_add(owner.direct.code, code, "code")?;
            owner.direct.comments = checked_add(owner.direct.comments, comments, "comments")?;
            owner.direct.blanks = checked_add(owner.direct.blanks, blanks, "blanks")?;
            owner.inaccurate |= language.inaccurate;

            // Accumulate one primary file under its detected language.
            // 将一个主文件累计到其检测语言下。
            let language_entry = owner
                .direct_languages
                .entry(language_name.clone())
                .or_default();
            language_entry.files = checked_add(language_entry.files, 1, "language.files")?;
            language_entry.counts.code = checked_add(language_entry.counts.code, code, "code")?;
            language_entry.counts.comments =
                checked_add(language_entry.counts.comments, comments, "comments")?;
            language_entry.counts.blanks =
                checked_add(language_entry.counts.blanks, blanks, "blanks")?;
            language_entry.inaccurate |= language.inaccurate;
        }
    }

    // Detect any mismatch where Tokei reported more unique files than the census saw.
    // 检测 Tokei 唯一报告文件数超过目录普查的口径不一致。
    let census_file_count = directories.values().try_fold(0_u64, |total, directory| {
        checked_add(total, directory.direct.files, "files")
    })?;
    // Convert the unique recognized path count into the public counter width.
    // 将唯一已识别路径数量转换为公共计数宽度。
    let recognized_file_count = u64::try_from(recognized_paths.len()).map_err(|error| {
        RepoStatsError::new(
            "recognized_file_count_overflow",
            format!("recognized path count does not fit into u64: {error}"),
        )
    })?;
    if recognized_file_count > census_file_count {
        return Err(RepoStatsError::new(
            "statistics_scope_mismatch",
            format!(
                "Tokei recognized {recognized_file_count} files but the directory census found {census_file_count} files"
            ),
        ));
    }

    Ok(())
}

/// Resolve one Tokei report path against the canonical repository root.
/// 将一个 Tokei 报告路径解析到规范仓库根目录。
///
/// # Parameters / 参数
/// - `root`: Canonical repository root.
/// - `root`：规范仓库根目录。
/// - `report_path`: Path stored by Tokei.
/// - `report_path`：Tokei 保存的路径。
///
/// # Returns / 返回值
/// Canonical report path inside the repository.
/// 仓库内部的规范报告路径。
fn resolve_report_path(root: &Path, report_path: &Path) -> Result<PathBuf, RepoStatsError> {
    // Absolute reports can be canonicalized directly; relative reports are rooted explicitly.
    // 绝对报告可直接规范化，相对报告则显式挂载到根目录。
    let candidate = if report_path.is_absolute() {
        report_path.to_path_buf()
    } else {
        root.join(report_path)
    };
    fs::canonicalize(&candidate).map_err(|error| {
        RepoStatsError::new(
            "tokei_report_canonicalize_failed",
            format!(
                "failed to canonicalize Tokei report path `{}`: {error}",
                candidate.display()
            ),
        )
    })
}

/// Aggregate all directory statistics from leaves to the root.
/// 将全部目录统计自叶节点聚合到根目录。
///
/// # Parameters / 参数
/// - `directories`: Complete directory census enriched by Tokei.
/// - `directories`：已由 Tokei 增强的完整目录普查。
///
/// # Returns / 返回值
/// Success, or a stable count/relationship failure.
/// 成功结果，或稳定的计数/关系失败。
fn aggregate_directories(
    directories: &mut BTreeMap<String, DirectoryAccumulator>,
) -> Result<(), RepoStatsError> {
    // Initialize recursive state from each directory's direct state.
    // 使用每个目录的直接状态初始化递归状态。
    for directory in directories.values_mut() {
        directory.total = directory.direct.clone();
        directory.total_languages = directory.direct_languages.clone();
        directory.total_directories = 0;
    }

    // Process deeper paths first so every child is complete before reaching its parent.
    // 优先处理更深路径，确保每个子目录在进入父目录前已经完整。
    let mut paths = directories.keys().cloned().collect::<Vec<_>>();
    paths.sort_by(|left, right| {
        directory_depth(right)
            .cmp(&directory_depth(left))
            .then(left.cmp(right))
    });

    for path in paths {
        if path == "." {
            continue;
        }

        // Clone completed child state to avoid overlapping mutable map borrows.
        // 克隆已完成子节点状态，避免映射发生重叠可变借用。
        let child = directories.get(&path).cloned().ok_or_else(|| {
            RepoStatsError::new(
                "directory_aggregate_missing",
                format!("directory aggregate disappeared for `{path}`"),
            )
        })?;
        // Every non-root directory must have one exact parent from the census.
        // 每个非根目录都必须拥有一个来自普查的精确父目录。
        let parent_path = child.parent_path.clone().ok_or_else(|| {
            RepoStatsError::new(
                "directory_parent_missing",
                format!("directory `{path}` has no parent"),
            )
        })?;
        // Merge the complete child subtree into its parent.
        // 将完整子树合并到父目录。
        let parent = directories.get_mut(&parent_path).ok_or_else(|| {
            RepoStatsError::new(
                "directory_parent_missing",
                format!("directory `{path}` references missing parent `{parent_path}`"),
            )
        })?;
        parent.total.checked_add_assign(&child.total)?;
        parent.total_directories = checked_add(
            parent.total_directories,
            checked_add(child.total_directories, 1, "totalDirectories")?,
            "totalDirectories",
        )?;
        parent.inaccurate |= child.inaccurate;
        merge_language_maps(&mut parent.total_languages, &child.total_languages)?;
    }

    Ok(())
}

/// Merge one stable language map into another with checked arithmetic.
/// 使用受检查算术将一个稳定语言映射合并到另一个映射。
///
/// # Parameters / 参数
/// - `target`: Parent or repository language aggregate.
/// - `target`：父目录或仓库语言聚合。
/// - `source`: Completed child language aggregate.
/// - `source`：已完成的子目录语言聚合。
///
/// # Returns / 返回值
/// Success, or a stable overflow error.
/// 成功结果，或稳定的溢出错误。
fn merge_language_maps(
    target: &mut BTreeMap<String, LanguageAccumulator>,
    source: &BTreeMap<String, LanguageAccumulator>,
) -> Result<(), RepoStatsError> {
    for (name, source_language) in source {
        // Create the target language lazily and then merge checked counters.
        // 延迟创建目标语言，再合并受检查计数。
        let target_language = target.entry(name.clone()).or_default();
        target_language.checked_add_assign(source_language)?;
    }
    Ok(())
}

/// Render directory records after complete recursive aggregation.
/// 在完成递归聚合后渲染目录记录。
///
/// # Parameters / 参数
/// - `request`: Validated display limits.
/// - `request`：已校验展示限制。
/// - `directories`: Complete directory aggregates.
/// - `directories`：完整目录聚合。
///
/// # Returns / 返回值
/// Stable visible directory records and explicit folding metadata.
/// 稳定的可见目录记录与显式折叠元数据。
fn render_directories(
    request: &ValidatedRequest,
    directories: &BTreeMap<String, DirectoryAccumulator>,
) -> Result<(Vec<DirectoryStats>, RenderLimit), RepoStatsError> {
    // Select only display-depth eligible paths before applying the record limit.
    // 在应用记录数量上限前仅选择满足展示深度的路径。
    let eligible_paths = directories
        .keys()
        .filter(|path| directory_depth(path) <= request.max_depth)
        .cloned()
        .collect::<Vec<_>>();
    // Preserve stable lexical path order and cap only the returned representation.
    // 保持稳定字典序，并且只裁剪返回表示层。
    let visible_paths = eligible_paths
        .into_iter()
        .take(request.max_rendered_directories)
        .collect::<Vec<_>>();
    // Use a set for deterministic nearest-visible-ancestor lookup.
    // 使用集合进行确定性的最近可见祖先查找。
    let visible_set = visible_paths.iter().cloned().collect::<BTreeSet<_>>();
    // Count omitted descendants on the nearest visible ancestor.
    // 在最近可见祖先节点上统计被省略后代数量。
    let mut collapsed_by_path = BTreeMap::<String, u64>::new();

    for path in directories.keys() {
        if visible_set.contains(path) {
            continue;
        }

        // Walk upward until the closest returned directory is found.
        // 向上查找直到找到最近的已返回目录。
        let mut cursor = parent_directory(path);
        while let Some(parent_path) = cursor {
            if visible_set.contains(&parent_path) {
                // Increment exactly one ancestor so omitted records are not double-counted.
                // 仅递增一个祖先，避免省略记录被重复统计。
                let collapsed = collapsed_by_path.entry(parent_path).or_default();
                *collapsed = checked_add(*collapsed, 1, "collapsedDescendants")?;
                break;
            }
            cursor = parent_directory(&parent_path);
        }
    }

    // Convert visible accumulators into stable public records.
    // 将可见聚合转换为稳定公共记录。
    let mut records = Vec::with_capacity(visible_paths.len());
    for path in &visible_paths {
        // Every visible path originated from the complete directory map.
        // 每个可见路径都来自完整目录映射。
        let directory = directories.get(path).ok_or_else(|| {
            RepoStatsError::new(
                "directory_render_missing",
                format!("visible directory `{path}` disappeared before rendering"),
            )
        })?;
        // Convert the aggregate once so all public counters share the same checked values.
        // 只转换一次聚合，确保全部公共计数共享相同的受检查值。
        let counts = public_counts(&directory.total)?;
        records.push(DirectoryStats {
            path: path.clone(),
            depth: directory_depth(path),
            parent_path: directory.parent_path.clone(),
            direct_directories: directory.direct_directories,
            total_directories: directory.total_directories,
            direct_files: directory.direct.files,
            total_files: counts.files,
            recognized_files: counts.recognized_files,
            unrecognized_files: counts.unrecognized_files,
            bytes: counts.bytes,
            lines: counts.lines,
            code: counts.code,
            comments: counts.comments,
            blanks: counts.blanks,
            languages: public_languages(&directory.total_languages)?,
            collapsed_descendants: collapsed_by_path.get(path).copied().unwrap_or(0),
            inaccurate: directory.inaccurate,
        });
    }

    // Record whether display depth or record count folded any directory.
    // 记录展示深度或记录数量是否折叠了任何目录。
    let truncated = records.len() < directories.len();
    // Report exact scan and rendering sizes.
    // 报告精确扫描与渲染规模。
    let render_limit = RenderLimit {
        max_depth: request.max_depth,
        max_rendered_directories: request.max_rendered_directories,
        returned_directories: records.len(),
        total_directories: directories.len(),
        truncated,
    };
    Ok((records, render_limit))
}

/// Convert internal aggregate counts into the public response shape.
/// 将内部聚合统计转换为公共响应结构。
///
/// # Parameters / 参数
/// - `counts`: Checked internal counters.
/// - `counts`：受检查的内部计数。
///
/// # Returns / 返回值
/// Public file, byte, and line counts.
/// 公共文件、字节与行数统计。
fn public_counts(counts: &AggregateCounts) -> Result<PublicCounts, RepoStatsError> {
    Ok(PublicCounts {
        files: counts.files,
        recognized_files: counts.recognized_files,
        unrecognized_files: counts.unrecognized_files()?,
        bytes: counts.bytes,
        lines: counts.lines()?,
        code: counts.code,
        comments: counts.comments,
        blanks: counts.blanks,
    })
}

/// Convert a stable language map into sorted public records.
/// 将稳定语言映射转换为排序后的公共记录。
///
/// # Parameters / 参数
/// - `languages`: Internal language aggregates keyed by Tokei name.
/// - `languages`：以 Tokei 名称索引的内部语言聚合。
///
/// # Returns / 返回值
/// Public language records sorted by name.
/// 按名称排序的公共语言记录。
fn public_languages(
    languages: &BTreeMap<String, LanguageAccumulator>,
) -> Result<Vec<LanguageStats>, RepoStatsError> {
    languages
        .iter()
        .map(|(name, language)| {
            Ok(LanguageStats {
                name: name.clone(),
                files: language.files,
                lines: language.counts.lines()?,
                code: language.counts.code,
                comments: language.counts.comments,
                blanks: language.counts.blanks,
                inaccurate: language.inaccurate,
            })
        })
        .collect()
}

/// Construct stable engine metadata.
/// 构造稳定引擎元数据。
///
/// # Returns / 返回值
/// Current CodeKit, Tokei, and protocol versions.
/// 当前 CodeKit、Tokei 与协议版本。
fn engine_info() -> EngineInfo {
    EngineInfo {
        codekit_ffi: env!("CARGO_PKG_VERSION"),
        tokei: TOKEI_ENGINE_VERSION,
        protocol: REPO_STATS_PROTOCOL_VERSION,
    }
}

/// Construct stable effective-scope metadata.
/// 构造稳定的实际范围元数据。
///
/// # Parameters / 参数
/// - `include_hidden`: Whether hidden entries were included.
/// - `include_hidden`：是否包含隐藏目录项。
/// - `respect_ignore`: Whether ordinary ignore files were respected.
/// - `respect_ignore`：是否遵循普通 ignore 文件。
///
/// # Returns / 返回值
/// Public effective scan policy.
/// 公共实际扫描策略。
fn scope_info(include_hidden: bool, respect_ignore: bool) -> ScopeInfo {
    ScopeInfo {
        include_hidden,
        respect_ignore,
        follow_symlinks: false,
        hard_excludes: HARD_EXCLUDED_DIRECTORY_NAMES.to_vec(),
    }
}

/// Construct one complete fatal response with empty statistics.
/// 构造一个统计为空的完整致命失败响应。
///
/// # Parameters / 参数
/// - `error`: Stable repository-statistics error.
/// - `error`：稳定仓库统计错误。
///
/// # Returns / 返回值
/// Public failure response preserving the full schema.
/// 保持完整协议结构的公共失败响应。
fn failure_response(error: RepoStatsError) -> RepoStatsResponse {
    RepoStatsResponse {
        ok: false,
        root: String::new(),
        engine: engine_info(),
        scope: scope_info(true, true),
        totals: RepositoryTotals::default(),
        languages: Vec::new(),
        directories: Vec::new(),
        diagnostics: Vec::new(),
        inaccurate: true,
        render_limit: RenderLimit::default(),
        error: Some(error.code),
        message: Some(error.message),
    }
}

/// Add two counters and surface overflow explicitly.
/// 累加两个计数并显式报告溢出。
///
/// # Parameters / 参数
/// - `left`: Existing counter value.
/// - `left`：现有计数值。
/// - `right`: Increment value.
/// - `right`：增量值。
/// - `field`: Stable field name used in diagnostics.
/// - `field`：诊断中使用的稳定字段名。
///
/// # Returns / 返回值
/// Checked sum, or a stable overflow error.
/// 受检查的和，或稳定的溢出错误。
fn checked_add(left: u64, right: u64, field: &'static str) -> Result<u64, RepoStatsError> {
    left.checked_add(right).ok_or_else(|| {
        RepoStatsError::new(
            "counter_overflow",
            format!("repository statistics counter overflowed: {field}"),
        )
    })
}

/// Convert a platform-sized counter into the stable protocol width.
/// 将平台相关大小的计数转换为稳定协议宽度。
///
/// # Parameters / 参数
/// - `value`: Platform-sized Tokei counter.
/// - `value`：平台相关大小的 Tokei 计数。
/// - `field`: Stable field name used in diagnostics.
/// - `field`：诊断中使用的稳定字段名。
///
/// # Returns / 返回值
/// Stable u64 value, or a conversion error.
/// 稳定的 u64 值，或转换错误。
fn usize_to_u64(value: usize, field: &'static str) -> Result<u64, RepoStatsError> {
    u64::try_from(value).map_err(|error| {
        RepoStatsError::new(
            "counter_conversion_failed",
            format!("failed to convert {field} counter into u64: {error}"),
        )
    })
}

/// Append one non-fatal diagnostic within the response budget.
/// 在响应预算内追加一条非致命诊断。
///
/// # Parameters / 参数
/// - `diagnostics`: Existing diagnostic sink.
/// - `diagnostics`：现有诊断接收器。
/// - `message`: Stable diagnostic message.
/// - `message`：稳定诊断消息。
fn push_diagnostic(diagnostics: &mut Vec<String>, message: String) {
    if diagnostics.len() < MAX_DIAGNOSTICS {
        diagnostics.push(message);
        return;
    }

    // Replace the last retained diagnostic with an explicit omission counter on first overflow.
    // 首次溢出时用显式省略计数替换最后一条已保留诊断。
    const OMITTED_PREFIX: &str = "additional_diagnostics_omitted:";
    let Some(last) = diagnostics.last_mut() else {
        // A zero diagnostic budget retains no content and must never panic at the FFI boundary.
        // 零诊断预算不保留任何内容，并且绝不能在 FFI 边界触发 panic。
        return;
    };
    // The first overflow omits both the replaced last item and the new item; later overflows add one.
    // 首次溢出会省略被替换的末项与新项，后续每次再增加一项。
    let omitted = last
        .strip_prefix(OMITTED_PREFIX)
        .and_then(|value| value.parse::<u128>().ok())
        .and_then(|value| value.checked_add(1))
        .unwrap_or(2);
    *last = format!("{OMITTED_PREFIX}{omitted}");
}

/// Escape one message for the last-resort JSON fallback.
/// 为最后回退 JSON 转义一条消息。
///
/// # Parameters / 参数
/// - `value`: Untrusted serializer error text.
/// - `value`：不受信任的序列化错误文本。
///
/// # Returns / 返回值
/// JSON-string-safe text without surrounding quotes.
/// 不包含外层引号的 JSON 字符串安全文本。
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

    /// Write one UTF-8 fixture file below a temporary repository.
    /// 在临时仓库下写入一个 UTF-8 fixture 文件。
    ///
    /// # Parameters / 参数
    /// - `root`: Temporary repository root.
    /// - `root`：临时仓库根目录。
    /// - `relative_path`: Slash-separated fixture path.
    /// - `relative_path`：使用正斜杠分隔的 fixture 路径。
    /// - `content`: UTF-8 file content.
    /// - `content`：UTF-8 文件内容。
    fn write_fixture(root: &Path, relative_path: &str, content: &str) {
        // Resolve the requested fixture path below the temporary root.
        // 在临时根目录下解析请求的 fixture 路径。
        let path = root.join(relative_path);
        // Create the exact parent directory when the fixture is nested.
        // 当 fixture 嵌套时创建精确父目录。
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("fixture parent should be created");
        }
        // Create and populate the fixture file.
        // 创建并填充 fixture 文件。
        let mut file = fs::File::create(path).expect("fixture file should be created");
        file.write_all(content.as_bytes())
            .expect("fixture file should be written");
    }

    /// Execute a request against one temporary root and decode its JSON value.
    /// 对一个临时根目录执行请求并解码其 JSON 值。
    ///
    /// # Parameters / 参数
    /// - `root`: Temporary repository root.
    /// - `root`：临时仓库根目录。
    /// - `max_depth`: Model-visible directory depth.
    /// - `max_depth`：模型可见目录深度。
    ///
    /// # Returns / 返回值
    /// Decoded public response JSON.
    /// 解码后的公共响应 JSON。
    fn run_request(root: &Path, max_depth: usize) -> serde_json::Value {
        // Construct the exact CodeKit-owned request shape.
        // 构造精确的 CodeKit 自有请求结构。
        let request = serde_json::json!({
            "root": root.to_string_lossy(),
            "maxDepth": max_depth,
            "includeHidden": true,
            "respectIgnore": true,
            "maxRenderedDirectories": 2000
        });
        // Execute and serialize the typed response.
        // 执行并序列化类型化响应。
        let response = execute_request_text(&request.to_string());
        serde_json::from_str(&serialize_response(&response))
            .expect("repository response should be valid JSON")
    }

    /// Verify empty repositories still return one root directory record.
    /// 验证空仓库仍返回一个根目录记录。
    #[test]
    fn scans_empty_repository() {
        // Create an isolated empty repository fixture.
        // 创建隔离的空仓库 fixture。
        let repository = tempfile::tempdir().expect("temporary repository should be created");
        // Run the complete repository scan.
        // 执行完整仓库扫描。
        let response = run_request(repository.path(), 3);
        assert_eq!(response["ok"], true);
        assert_eq!(response["totals"]["directories"], 1);
        assert_eq!(response["totals"]["files"], 0);
        assert_eq!(response["directories"].as_array().map(Vec::len), Some(1));
        assert_eq!(response["directories"][0]["path"], ".");
    }

    /// Verify recognized and unknown files remain distinguishable.
    /// 验证已识别文件与未知文件始终可区分。
    #[test]
    fn distinguishes_recognized_and_unknown_files() {
        // Create an isolated mixed-language fixture repository.
        // 创建隔离的混合文件 fixture 仓库。
        let repository = tempfile::tempdir().expect("temporary repository should be created");
        write_fixture(repository.path(), "src/main.rs", "fn main() {}\n");
        write_fixture(repository.path(), "assets/blob.unknown", "opaque\n");
        // Run the complete repository scan.
        // 执行完整仓库扫描。
        let response = run_request(repository.path(), 3);
        assert_eq!(response["ok"], true);
        assert_eq!(response["totals"]["files"], 2);
        assert_eq!(response["totals"]["recognizedFiles"], 1);
        assert_eq!(response["totals"]["unrecognizedFiles"], 1);
        assert_eq!(response["languages"][0]["name"], "Rust");
    }

    /// Verify hidden formal directories are included while hard exclusions remain absent.
    /// 验证隐藏正式目录会被包含，而强制排除目录始终缺席。
    #[test]
    fn includes_hidden_structure_and_excludes_build_noise() {
        // Create an isolated repository with formal and noisy hidden directories.
        // 创建同时包含正式隐藏目录与噪音目录的隔离仓库。
        let repository = tempfile::tempdir().expect("temporary repository should be created");
        write_fixture(
            repository.path(),
            ".github/workflows/validate.yml",
            "name: test\n",
        );
        write_fixture(repository.path(), ".git/config", "ignored\n");
        write_fixture(
            repository.path(),
            "target/generated.rs",
            "fn generated() {}\n",
        );
        // Run the complete repository scan.
        // 执行完整仓库扫描。
        let response = run_request(repository.path(), 3);
        // Collect returned directory path values for exact membership checks.
        // 收集返回目录路径以执行精确成员检查。
        let paths = response["directories"]
            .as_array()
            .expect("directories should be an array")
            .iter()
            .filter_map(|item| item["path"].as_str())
            .collect::<Vec<_>>();
        assert!(paths.contains(&".github"));
        assert!(paths.contains(&".github/workflows"));
        assert!(!paths.contains(&".git"));
        assert!(!paths.contains(&"target"));
        assert_eq!(response["totals"]["files"], 1);
    }

    /// Verify ignore files affect the census and Tokei through one shared policy.
    /// 验证 ignore 文件通过同一策略影响目录普查与 Tokei。
    #[test]
    fn respects_repository_ignore_files() {
        // Create an isolated repository with one ignored subtree.
        // 创建包含一个被忽略子树的隔离仓库。
        let repository = tempfile::tempdir().expect("temporary repository should be created");
        write_fixture(repository.path(), ".git/HEAD", "ref: refs/heads/main\n");
        write_fixture(repository.path(), ".gitignore", "ignored/\n");
        write_fixture(repository.path(), "ignored/hidden.rs", "fn hidden() {}\n");
        write_fixture(repository.path(), "kept/main.rs", "fn kept() {}\n");
        // Run the complete repository scan.
        // 执行完整仓库扫描。
        let response = run_request(repository.path(), 3);
        assert_eq!(response["totals"]["files"], 2);
        assert_eq!(response["totals"]["recognizedFiles"], 1);
        // The `.gitignore` control file remains part of the all-file census.
        // `.gitignore` 控制文件仍属于全部文件普查范围。
        assert_eq!(response["totals"]["unrecognizedFiles"], 1);
    }

    /// Verify `.ignore` and `.tokeignore` share the same census and Tokei boundary.
    /// 验证 `.ignore` 与 `.tokeignore` 在目录普查和 Tokei 中共享同一边界。
    #[test]
    fn respects_all_supported_ignore_files() {
        // Create one repository containing every supported non-VCS ignore file.
        // 创建包含全部受支持非 VCS ignore 文件的仓库。
        let repository = tempfile::tempdir().expect("temporary repository should be created");
        write_fixture(repository.path(), ".ignore", "ignored.rs\n");
        write_fixture(repository.path(), ".tokeignore", "tokei-ignored.py\n");
        write_fixture(repository.path(), "ignored.rs", "fn ignored() {}\n");
        write_fixture(repository.path(), "tokei-ignored.py", "print('ignored')\n");
        write_fixture(repository.path(), "kept.rs", "fn kept() {}\n");

        // Execute the default ignore-respecting scan.
        // 执行默认遵循 ignore 的扫描。
        let response = run_request(repository.path(), 3);
        assert_eq!(response["ok"], true);
        assert_eq!(response["totals"]["files"], 3);
        assert_eq!(response["totals"]["recognizedFiles"], 1);
        assert_eq!(response["totals"]["unrecognizedFiles"], 2);
        assert_eq!(response["diagnostics"].as_array().map(Vec::len), Some(0));
    }

    /// Verify no-ignore disables both ordinary and Tokei custom ignore files while retaining hard exclusions.
    /// 验证 no-ignore 会禁用普通及 Tokei 自定义忽略文件，同时保留强制排除规则。
    #[test]
    fn disables_ordinary_ignore_files_but_keeps_hard_exclusions() {
        let directory = tempfile::tempdir().expect("temporary repository should be created");
        write_fixture(directory.path(), ".ignore", "ignored.rs\n");
        write_fixture(directory.path(), ".tokeignore", "tokei-ignored.py\n");
        write_fixture(directory.path(), "ignored.rs", "fn included() {}\n");
        write_fixture(directory.path(), "tokei-ignored.py", "print('included')\n");
        write_fixture(directory.path(), "target/excluded.rs", "fn excluded() {}\n");
        // Disable ordinary ignore files through the exact public request contract.
        // 通过精确公共请求契约禁用普通忽略文件。
        let request = serde_json::json!({
            "root": directory.path(),
            "maxDepth": 3,
            "includeHidden": true,
            "respectIgnore": false,
            "maxRenderedDirectories": 2_000
        });
        let response = execute_request_text(&request.to_string());
        let payload = serde_json::to_value(response).expect("serialize response");

        assert_eq!(payload["ok"], true);
        assert_eq!(payload["totals"]["files"], 4);
        assert_eq!(payload["totals"]["recognizedFiles"], 2);
        assert!(payload["directories"]
            .as_array()
            .expect("directory array")
            .iter()
            .all(|entry| entry["path"] != "target"));
    }

    /// Verify display folding preserves complete root totals and reports omitted descendants.
    /// 验证展示折叠保持完整根总量并报告省略后代。
    #[test]
    fn folds_deep_directories_without_changing_totals() {
        // Create an isolated deep repository fixture.
        // 创建隔离的深层仓库 fixture。
        let repository = tempfile::tempdir().expect("temporary repository should be created");
        write_fixture(
            repository.path(),
            "one/two/three/four/deep.rs",
            "fn deep() {}\n",
        );
        // Limit model-visible depth while retaining a complete recursive scan.
        // 限制模型可见深度，同时保留完整递归扫描。
        let response = run_request(repository.path(), 2);
        assert_eq!(response["totals"]["recognizedFiles"], 1);
        assert_eq!(response["renderLimit"]["truncated"], true);
        assert_eq!(response["directories"][2]["path"], "one/two");
        assert_eq!(response["directories"][2]["collapsedDescendants"], 2);
        assert_eq!(response["directories"][0]["totalFiles"], 1);
    }

    /// Verify the directory-record limit preserves totals and reports exact omissions.
    /// 验证目录记录数量上限会保持总量并精确报告省略数量。
    #[test]
    fn limits_directory_records_without_changing_totals() {
        // Create three sibling source directories that all participate in complete totals.
        // 创建三个都会参与完整总量统计的同级源码目录。
        let repository = tempfile::tempdir().expect("temporary repository should be created");
        write_fixture(repository.path(), "alpha/a.rs", "fn alpha() {}\n");
        write_fixture(repository.path(), "beta/b.rs", "fn beta() {}\n");
        write_fixture(repository.path(), "gamma/c.rs", "fn gamma() {}\n");
        // Apply a two-record output limit while leaving the scan depth unrestricted for this fixture.
        // 应用两个记录的输出上限，同时保持该 fixture 的扫描深度不受限制。
        let request = serde_json::json!({
            "root": repository.path(),
            "maxDepth": 3,
            "includeHidden": true,
            "respectIgnore": true,
            "maxRenderedDirectories": 2
        });
        // Decode the bounded public response.
        // 解码受限的公共响应。
        let response = execute_request_text(&request.to_string());
        let payload = serde_json::to_value(response).expect("serialize response");

        assert_eq!(payload["totals"]["directories"], 4);
        assert_eq!(payload["totals"]["recognizedFiles"], 3);
        assert_eq!(payload["renderLimit"]["returnedDirectories"], 2);
        assert_eq!(payload["renderLimit"]["totalDirectories"], 4);
        assert_eq!(payload["renderLimit"]["truncated"], true);
        assert_eq!(payload["directories"][0]["path"], ".");
        assert_eq!(payload["directories"][0]["collapsedDescendants"], 2);
    }

    /// Verify Unicode paths remain visible while file names and source text remain private.
    /// 验证 Unicode 路径保持可见，同时文件名与源码文本保持不公开。
    #[test]
    fn preserves_unicode_directories_without_exposing_files_or_source() {
        // Create a non-BMP Unicode directory with recognized and unknown files.
        // 创建包含已识别与未知文件的非 BMP Unicode 目录。
        let repository = tempfile::tempdir().expect("temporary repository should be created");
        write_fixture(
            repository.path(),
            "模块😀/秘密实现.rs",
            "fn secret_source_body() {}\n",
        );
        write_fixture(
            repository.path(),
            "模块😀/未知文件.bin",
            "PRIVATE_FILE_BODY\n",
        );

        // Serialize the public response exactly as the C ABI would return it.
        // 按照 C ABI 的实际返回方式序列化公共响应。
        let response = execute_request_text(
            &serde_json::json!({
                "root": repository.path(),
                "maxDepth": 3,
                "includeHidden": true,
                "respectIgnore": true,
                "maxRenderedDirectories": 2_000
            })
            .to_string(),
        );
        let response_text = serialize_response(&response);
        let payload: serde_json::Value =
            serde_json::from_str(&response_text).expect("repository response should be valid JSON");

        assert!(payload["directories"]
            .as_array()
            .expect("directory array")
            .iter()
            .any(|entry| entry["path"] == "模块😀"));
        assert!(!response_text.contains("秘密实现.rs"));
        assert!(!response_text.contains("未知文件.bin"));
        assert!(!response_text.contains("secret_source_body"));
        assert!(!response_text.contains("PRIVATE_FILE_BODY"));
    }

    /// Verify identical requests produce byte-stable JSON ordering across repeated scans.
    /// 验证相同请求在重复扫描中产生字节稳定的 JSON 顺序。
    #[test]
    fn produces_stable_json_across_repeated_scans() {
        // Create a small polyglot fixture whose ordering could otherwise vary by traversal.
        // 创建一个小型多语言 fixture，用于暴露潜在的遍历顺序波动。
        let repository = tempfile::tempdir().expect("temporary repository should be created");
        write_fixture(repository.path(), "zeta/main.py", "print('zeta')\n");
        write_fixture(repository.path(), "alpha/main.rs", "fn alpha() {}\n");
        // Build one immutable request reused by every scan.
        // 构建一个由每轮扫描复用的不可变请求。
        let request = serde_json::json!({
            "root": repository.path(),
            "maxDepth": 3,
            "includeHidden": true,
            "respectIgnore": true,
            "maxRenderedDirectories": 2_000
        })
        .to_string();
        // Capture the first serialized response as the byte-level oracle.
        // 将第一次序列化响应作为字节级基准。
        let expected = serialize_response(&execute_request_text(&request));

        for _ in 0..20 {
            // Compare the complete JSON text, including array and object field order.
            // 比较完整 JSON 文本，包括数组与对象字段顺序。
            let actual = serialize_response(&execute_request_text(&request));
            assert_eq!(actual, expected);
        }
    }

    /// Verify bounded diagnostics report every omitted message explicitly.
    /// 验证有界诊断会显式报告每一条被省略的消息。
    #[test]
    fn reports_diagnostic_overflow_explicitly() {
        // Fill beyond the public diagnostic budget with deterministic messages.
        // 使用确定性消息填充并超过公共诊断预算。
        let mut diagnostics = Vec::new();
        for index in 0..105 {
            push_diagnostic(&mut diagnostics, format!("diagnostic:{index}"));
        }

        assert_eq!(diagnostics.len(), MAX_DIAGNOSTICS);
        assert_eq!(diagnostics[98], "diagnostic:98");
        assert_eq!(diagnostics[99], "additional_diagnostics_omitted:6");
    }

    /// Verify unsupported request fields fail instead of being silently ignored.
    /// 验证不受支持的请求字段会失败而非被静默忽略。
    #[test]
    fn rejects_language_filters() {
        // Create an isolated repository fixture.
        // 创建隔离仓库 fixture。
        let repository = tempfile::tempdir().expect("temporary repository should be created");
        // Attempt to add a forbidden language filter.
        // 尝试加入被禁止的语言过滤字段。
        let request = serde_json::json!({
            "root": repository.path().to_string_lossy(),
            "languages": ["Rust"]
        });
        // Execute the invalid request.
        // 执行无效请求。
        let response = execute_request_text(&request.to_string());
        assert!(!response.ok);
        assert_eq!(response.error, Some("invalid_request_json"));
    }

    /// Verify invalid display limits produce a stable validation failure.
    /// 验证无效展示限制会产生稳定校验失败。
    #[test]
    fn rejects_invalid_max_depth() {
        // Create an isolated repository fixture.
        // 创建隔离仓库 fixture。
        let repository = tempfile::tempdir().expect("temporary repository should be created");
        // Construct a request beyond the documented depth limit.
        // 构造超过文档深度上限的请求。
        let request = serde_json::json!({
            "root": repository.path().to_string_lossy(),
            "maxDepth": 9
        });
        // Execute the invalid request.
        // 执行无效请求。
        let response = execute_request_text(&request.to_string());
        assert!(!response.ok);
        assert_eq!(response.error, Some("invalid_max_depth"));
    }
}
