//! Shared C ABI memory helpers for the CodeKit dynamic library.
//! CodeKit 动态库共享的 C ABI 内存辅助函数。

use std::ffi::CString;
use std::os::raw::{c_char, c_void};
use std::ptr;

/// Convert an owned Rust string into an owned C string pointer.
/// 将 Rust 自有字符串转换为需要调用方释放的 C 字符串指针。
///
/// # Parameters / 参数
/// - `value`: UTF-8 response text returned across the C ABI.
/// - `value`：通过 C ABI 返回的 UTF-8 响应文本。
///
/// # Returns / 返回值
/// An allocated C string pointer, or null when the value contains an interior NUL byte.
/// 已分配的 C 字符串指针；当文本包含内部 NUL 字节时返回空指针。
pub(crate) fn string_to_c_pointer(value: String) -> *mut c_char {
    CString::new(value)
        .map(CString::into_raw)
        .unwrap_or_else(|_| ptr::null_mut::<c_void>().cast())
}

/// Free one C string allocated by this dynamic library.
/// 释放一个由当前动态库分配的 C 字符串。
///
/// # Parameters / 参数
/// - `value`: Pointer previously returned by a CodeKit FFI JSON function.
/// - `value`：此前由 CodeKit FFI JSON 函数返回的指针。
///
/// # Safety / 安全性
/// The pointer must be null or originate from `CString::into_raw` in this library, and it must be freed once.
/// 指针必须为空，或来源于当前动态库中的 `CString::into_raw`，且只能释放一次。
pub(crate) fn free_string(value: *mut c_char) {
    if value.is_null() {
        return;
    }

    // Reclaim the allocation with the same Rust allocator that created it.
    // 使用创建该指针的同一个 Rust 分配器回收内存。
    unsafe { drop(CString::from_raw(value)) };
}
