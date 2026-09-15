//! Repository path normalization and hard-exclusion policy.
//! 仓库路径规范化与强制排除策略。

use std::path::{Component, Path};

use crate::error::RepoStatsError;

/// Directory names that remain excluded even when ordinary ignore files are disabled.
/// 即使关闭普通 ignore 文件也始终排除的目录名称。
pub(crate) const HARD_EXCLUDED_DIRECTORY_NAMES: [&str; 10] = [
    ".git",
    "target",
    "node_modules",
    "dist",
    "build",
    "vendor",
    "output",
    ".idea",
    ".vscode",
    "__pycache__",
];

/// Gitignore-style patterns passed to Tokei for the same hard-exclusion boundary.
/// 传给 Tokei、用于维持相同强制排除边界的 gitignore 风格模式。
pub(crate) const TOKEI_HARD_EXCLUDE_PATTERNS: [&str; 10] = [
    ".git",
    "target",
    "node_modules",
    "dist",
    "build",
    "vendor",
    "output",
    ".idea",
    ".vscode",
    "__pycache__",
];

/// Render one canonical path without platform-internal verbatim prefixes.
/// 渲染一个不包含平台内部逐字路径前缀的规范路径。
///
/// # Parameters / 参数
/// - `path`: Canonical filesystem path.
/// - `path`：规范化后的文件系统路径。
///
/// # Returns / 返回值
/// Stable human-facing path text that preserves the underlying path identity.
/// 保留底层路径身份的稳定人类可读路径文本。
pub(crate) fn display_canonical_path(path: &Path) -> String {
    // Convert through the platform's loss-tolerant display form exactly once.
    // 仅通过平台容错展示形式转换一次。
    let rendered = path.to_string_lossy().to_string();
    #[cfg(windows)]
    {
        // Convert verbatim UNC paths back to their ordinary network-path representation.
        // 将逐字 UNC 路径还原为普通网络路径表示。
        if let Some(unc_path) = rendered.strip_prefix(r"\\?\UNC\") {
            return format!(r"\\{unc_path}");
        }
        // Remove the internal verbatim prefix from ordinary drive paths.
        // 从普通盘符路径移除内部逐字前缀。
        if let Some(drive_path) = rendered.strip_prefix(r"\\?\") {
            return drive_path.to_string();
        }
    }
    rendered
}

/// Return whether a directory entry name belongs to the hard-exclusion set.
/// 判断目录项名称是否属于强制排除集合。
///
/// # Parameters / 参数
/// - `name`: One directory basename without parent components.
/// - `name`：不包含父路径的单个目录基础名称。
///
/// # Returns / 返回值
/// `true` when the directory must never be traversed.
/// 当该目录必须始终禁止遍历时返回 `true`。
pub(crate) fn is_hard_excluded_directory(name: &str) -> bool {
    HARD_EXCLUDED_DIRECTORY_NAMES
        .iter()
        .any(|candidate| candidate.eq_ignore_ascii_case(name))
}

/// Normalize an absolute repository path into a stable root-relative path.
/// 将绝对仓库路径规范化为稳定的根目录相对路径。
///
/// # Parameters / 参数
/// - `root`: Canonical repository root.
/// - `root`：规范化后的仓库根目录。
/// - `path`: Canonical or root-descendant path to normalize.
/// - `path`：需要规范化的规范路径或根目录后代路径。
///
/// # Returns / 返回值
/// `.` for the root, otherwise a slash-separated relative path.
/// 根目录返回 `.`，否则返回使用正斜杠分隔的相对路径。
pub(crate) fn normalize_relative_path(root: &Path, path: &Path) -> Result<String, RepoStatsError> {
    // Keep repository identity stable by rejecting reports outside the requested root.
    // 通过拒绝根目录之外的报告来保持仓库身份稳定。
    let relative = path.strip_prefix(root).map_err(|error| {
        RepoStatsError::new(
            "path_outside_root",
            format!(
                "path `{}` is outside repository root `{}`: {error}",
                path.display(),
                root.display()
            ),
        )
    })?;

    if relative.as_os_str().is_empty() {
        return Ok(".".to_string());
    }

    // Reject parent and platform-prefix components instead of normalizing ambiguous identities.
    // 拒绝父级和平台前缀组件，避免规范化出身份不明确的路径。
    let mut normalized_components = Vec::new();
    for component in relative.components() {
        match component {
            Component::Normal(value) => {
                normalized_components.push(value.to_string_lossy().to_string());
            }
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(RepoStatsError::new(
                    "invalid_relative_path",
                    format!(
                        "path `{}` contains an invalid relative component",
                        path.display()
                    ),
                ));
            }
        }
    }

    Ok(normalized_components.join("/"))
}

/// Return the stable parent directory path for one normalized relative path.
/// 返回一个已规范化相对路径的稳定父目录路径。
///
/// # Parameters / 参数
/// - `path`: `.` or one slash-separated root-relative path.
/// - `path`：`.` 或一个使用正斜杠分隔的根目录相对路径。
///
/// # Returns / 返回值
/// `None` for `.`, otherwise the normalized parent path.
/// `.` 返回 `None`，其他路径返回规范化父路径。
pub(crate) fn parent_directory(path: &str) -> Option<String> {
    if path == "." {
        return None;
    }

    match path.rsplit_once('/') {
        Some((parent, _)) if !parent.is_empty() => Some(parent.to_string()),
        _ => Some(".".to_string()),
    }
}

/// Return the directory depth of one normalized root-relative directory.
/// 返回一个已规范化根目录相对目录的深度。
///
/// # Parameters / 参数
/// - `path`: `.` or one slash-separated directory path.
/// - `path`：`.` 或一个使用正斜杠分隔的目录路径。
///
/// # Returns / 返回值
/// Zero for the root and one plus the separator count for descendants.
/// 根目录返回零，后代目录返回分隔段数量。
pub(crate) fn directory_depth(path: &str) -> usize {
    if path == "." {
        0
    } else {
        path.split('/').count()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Verify stable parent and depth calculations for normalized paths.
    /// 验证规范路径的稳定父级与深度计算。
    #[test]
    fn calculates_parent_and_depth() {
        assert_eq!(parent_directory("."), None);
        assert_eq!(parent_directory("src"), Some(".".to_string()));
        assert_eq!(parent_directory("src/nested"), Some("src".to_string()));
        assert_eq!(directory_depth("."), 0);
        assert_eq!(directory_depth("src/nested"), 2);
    }

    /// Verify that all configured build-noise directories remain hard excluded.
    /// 验证全部已配置构建噪音目录始终处于强制排除状态。
    #[test]
    fn recognizes_hard_excluded_directories() {
        assert!(is_hard_excluded_directory(".git"));
        assert!(is_hard_excluded_directory("TARGET"));
        assert!(is_hard_excluded_directory("node_modules"));
        assert!(is_hard_excluded_directory("__PYCACHE__"));
        assert!(!is_hard_excluded_directory(".github"));
        assert!(!is_hard_excluded_directory("src"));
    }

    /// Verify canonical paths keep a stable human-facing display form.
    /// 验证规范路径保持稳定的人类可读展示形式。
    #[test]
    fn renders_canonical_paths_for_humans() {
        #[cfg(windows)]
        {
            assert_eq!(
                display_canonical_path(Path::new(r"\\?\D:\repo")),
                r"D:\repo"
            );
            assert_eq!(
                display_canonical_path(Path::new(r"\\?\UNC\server\share\repo")),
                r"\\server\share\repo"
            );
        }
        #[cfg(not(windows))]
        assert_eq!(display_canonical_path(Path::new("/repo")), "/repo");
    }
}
