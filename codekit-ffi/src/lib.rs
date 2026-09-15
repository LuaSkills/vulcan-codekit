//! Unified native capabilities for the Vulcan CodeKit LuaSkill.
//! Vulcan CodeKit LuaSkill 的统一原生能力入口。

mod ast_grep;
mod error;
mod ffi;
mod path_policy;
mod repo_stats;

use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};

use serde::Serialize;

/// Describe one native capability exposed by the unified dynamic library.
/// 描述统一动态库暴露的一个原生能力。
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct CapabilityInfo {
    /// Stable capability identifier.
    /// 稳定能力标识。
    name: &'static str,
    /// Stable protocol version implemented by the capability.
    /// 该能力实现的稳定协议版本。
    protocol: &'static str,
    /// Optional implementation engine name and version.
    /// 可选的实现引擎名称与版本。
    #[serde(skip_serializing_if = "Option::is_none")]
    engine: Option<&'static str>,
}

/// Describe all native capabilities exposed by the unified dynamic library.
/// 描述统一动态库暴露的全部原生能力。
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct CapabilitiesResponse {
    /// Whether capability discovery succeeded.
    /// 能力发现是否成功。
    ok: bool,
    /// Unified CodeKit FFI version.
    /// 统一 CodeKit FFI 版本。
    ffi_version: &'static str,
    /// Stable list of native capabilities.
    /// 稳定的原生能力列表。
    capabilities: Vec<CapabilityInfo>,
}

/// Return the unified CodeKit FFI crate version for loader diagnostics.
/// 返回统一 CodeKit FFI crate 版本，供加载器诊断使用。
///
/// # Returns / 返回值
/// Process-lifetime NUL-terminated semantic-version text.
/// 进程生命周期内有效、以 NUL 结尾的语义化版本文本。
#[no_mangle]
pub extern "C" fn vulcan_codekit_ffi_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr().cast()
}

/// Return a JSON description of all capabilities in the unified library.
/// 返回统一动态库全部能力的 JSON 描述。
///
/// # Returns / 返回值
/// Allocated UTF-8 JSON string that must be released with `vulcan_codekit_free_string`.
/// 需要使用 `vulcan_codekit_free_string` 释放的已分配 UTF-8 JSON 字符串。
#[no_mangle]
pub extern "C" fn vulcan_codekit_ffi_capabilities_json() -> *mut c_char {
    // Keep the capability list explicit so ABI additions require an intentional source change.
    // 显式维护能力列表，使 ABI 新增必须经过有意的源码变更。
    let response = CapabilitiesResponse {
        ok: true,
        ffi_version: env!("CARGO_PKG_VERSION"),
        capabilities: vec![
            CapabilityInfo {
                name: "ast-grep",
                protocol: "1",
                engine: Some("ast-grep 0.42.1"),
            },
            CapabilityInfo {
                name: "repo-stats",
                protocol: repo_stats::REPO_STATS_PROTOCOL_VERSION,
                engine: Some("tokei 15.0.0"),
            },
        ],
    };
    // Serialize the infallible static capability shape into an owned C string.
    // 将不会失败的静态能力结构序列化为自有 C 字符串。
    let json = serde_json::to_string(&response).unwrap_or_else(|error| {
        format!(
            "{{\"ok\":false,\"ffiVersion\":\"{}\",\"capabilities\":[],\"error\":\"response_encode_failed\",\"message\":{:?}}}",
            env!("CARGO_PKG_VERSION"),
            error.to_string()
        )
    });
    ffi::string_to_c_pointer(json)
}

/// Scan one repository and return directory plus all-language statistics as JSON.
/// 扫描一个仓库，并以 JSON 返回目录与全部语言统计。
///
/// # Parameters / 参数
/// - `request_json`: NUL-terminated UTF-8 CodeKit repository-statistics request.
/// - `request_json`：以 NUL 结尾的 UTF-8 CodeKit 仓库统计请求。
///
/// # Returns / 返回值
/// Allocated UTF-8 JSON string that must be released with `vulcan_codekit_free_string`.
/// 需要使用 `vulcan_codekit_free_string` 释放的已分配 UTF-8 JSON 字符串。
#[no_mangle]
pub extern "C" fn vulcan_codekit_repo_stats_json(request_json: *const c_char) -> *mut c_char {
    // Contain all panics at the FFI boundary and never expose Rust unwind state to LuaJIT.
    // 在 FFI 边界阻断全部 panic，绝不向 LuaJIT 暴露 Rust 展开状态。
    let response = catch_unwind(AssertUnwindSafe(|| {
        repo_stats::execute_c_request(request_json)
    }))
    .unwrap_or_else(|_| repo_stats::panic_response());
    // Serialize the typed response before transferring ownership to LuaJIT.
    // 在向 LuaJIT 转移所有权前序列化类型化响应。
    let json = repo_stats::serialize_response(&response);
    ffi::string_to_c_pointer(json)
}

/// Free any owned response string allocated by the unified CodeKit FFI.
/// 释放统一 CodeKit FFI 分配的任意自有响应字符串。
///
/// # Parameters / 参数
/// - `value`: Pointer returned by a unified CodeKit FFI JSON function.
/// - `value`：由统一 CodeKit FFI JSON 函数返回的指针。
#[no_mangle]
pub extern "C" fn vulcan_codekit_free_string(value: *mut c_char) {
    ffi::free_string(value);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

    /// Verify capability discovery reports both AST and repository statistics.
    /// 验证能力发现会同时报告 AST 与仓库统计。
    #[test]
    fn reports_unified_capabilities() {
        // Request one owned capability response through the public ABI.
        // 通过公共 ABI 请求一个自有能力响应。
        let pointer = vulcan_codekit_ffi_capabilities_json();
        assert!(!pointer.is_null());
        // Copy the response into Rust-owned text before freeing the ABI allocation.
        // 在释放 ABI 分配前将响应复制到 Rust 自有文本。
        let text = unsafe { CStr::from_ptr(pointer) }
            .to_str()
            .expect("capability response should be UTF-8")
            .to_string();
        vulcan_codekit_free_string(pointer);
        // Decode the public JSON shape for exact capability assertions.
        // 解码公共 JSON 结构以执行精确能力断言。
        let response: serde_json::Value =
            serde_json::from_str(&text).expect("capability response should be valid JSON");
        assert_eq!(response["ok"], true);
        assert_eq!(response["ffiVersion"], env!("CARGO_PKG_VERSION"));
        assert_eq!(response["capabilities"][0]["name"], "ast-grep");
        assert_eq!(response["capabilities"][1]["name"], "repo-stats");
    }

    /// Verify the repository statistics ABI returns a stable null-request error.
    /// 验证仓库统计 ABI 会为 null 请求返回稳定错误。
    #[test]
    fn rejects_null_repository_request() {
        // Request repository statistics with a null input pointer.
        // 使用空输入指针请求仓库统计。
        let pointer = vulcan_codekit_repo_stats_json(std::ptr::null());
        assert!(!pointer.is_null());
        // Copy the response text before freeing the ABI allocation.
        // 在释放 ABI 分配前复制响应文本。
        let text = unsafe { CStr::from_ptr(pointer) }
            .to_str()
            .expect("error response should be UTF-8")
            .to_string();
        vulcan_codekit_free_string(pointer);
        // Decode the public JSON response for exact error assertions.
        // 解码公共 JSON 响应以执行精确错误断言。
        let response: serde_json::Value =
            serde_json::from_str(&text).expect("error response should be valid JSON");
        assert_eq!(response["ok"], false);
        assert_eq!(response["error"], "null_request");
    }
}
