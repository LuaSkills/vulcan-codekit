//! Stable internal errors used by the repository statistics protocol.
//! 仓库统计协议使用的稳定内部错误。

/// Describe one stable CodeKit repository-statistics failure.
/// 描述一个稳定的 CodeKit 仓库统计失败。
#[derive(Debug)]
pub(crate) struct RepoStatsError {
    /// Machine-readable error code exposed to Lua.
    /// 暴露给 Lua 的机器可读错误码。
    pub(crate) code: &'static str,
    /// Human-readable error explanation exposed to diagnostics.
    /// 暴露到诊断信息中的人类可读错误说明。
    pub(crate) message: String,
}

impl RepoStatsError {
    /// Construct a repository-statistics error from a stable code and message.
    /// 使用稳定错误码和说明构造仓库统计错误。
    ///
    /// # Parameters / 参数
    /// - `code`: Stable machine-readable error code.
    /// - `code`：稳定的机器可读错误码。
    /// - `message`: Human-readable diagnostic message.
    /// - `message`：人类可读诊断说明。
    ///
    /// # Returns / 返回值
    /// A fully initialized repository-statistics error.
    /// 一个完整初始化的仓库统计错误。
    pub(crate) fn new(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }
}
