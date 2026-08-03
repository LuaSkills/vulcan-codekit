"""
Validate the public CodeKit output contract and the post-write verification wiring.
校验 CodeKit 公共输出契约以及写入后验证链路。
"""

from __future__ import annotations

import sys
from pathlib import Path


def repository_root() -> Path:
    """
    Return the skill repository root containing this verification script.
    返回包含本验证脚本的技能仓库根目录。
    """

    return Path(__file__).resolve().parent.parent


def read_text(root: Path, relative_path: str) -> str:
    """
    Read one repository text file as UTF-8.
    以 UTF-8 读取仓库中的一个文本文件。
    """

    return (root / relative_path).read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    """
    Raise a clear contract failure when one assertion is not satisfied.
    当某项契约断言不满足时抛出清晰的校验错误。
    """

    if not condition:
        raise RuntimeError(message)


def renderer_body(source: str, marker: str) -> str:
    """
    Return the source segment of one renderer up to its final return statement.
    返回一个渲染函数从声明到最终 return 语句的源码片段。
    """

    start = source.index(marker)
    end = source.index("\n    return table.concat(lines", start)
    return source[start:end]


def verify_node_source_output(root: Path) -> None:
    """
    Verify that normal node-source output contains source semantics only.
    校验 node-source 正常输出只包含源码语义信息。
    """

    source = read_text(root, "runtime/codekit-node-source.lua")
    rendered = renderer_body(source, "local function render_node_source_result")
    require("overflow_mode" not in rendered, "node-source renderer still exposes overflow metadata")
    require("node_hash" not in rendered, "node-source renderer still exposes node_hash")
    require("file_hash" not in rendered, "node-source renderer still exposes file_hash")
    require("source_text" in rendered, "node-source renderer no longer returns source text")
    require("compute_source_hash" not in source, "node-source still computes removed hashes")
    require("node_hash" not in source, "node-source still stores removed node_hash state")
    require("file_hash" not in source, "node-source still stores removed file_hash state")


def verify_patch_output(root: Path) -> None:
    """
    Verify that patch output is built from actual post-write state.
    校验 patch 输出确实基于写入后的实际状态构造。
    """

    source = read_text(root, "runtime/codekit-patch.lua")
    rendered = renderer_body(source, "local function render_patch_batch_result")
    require("previous_node_hash" not in rendered, "patch renderer still exposes previous_node_hash")
    require("new_node_hash" not in rendered, "patch renderer still exposes new_node_hash")
    require("patched_lines" in rendered, "patch renderer does not expose patched lines")
    require("before_context" in rendered, "patch renderer does not expose before context")
    require("after_context" in rendered, "patch renderer does not expose after context")
    require("post_write_read_failed" in source, "patch commit path lacks post-write read failure handling")
    require("record.post_content" in source, "patch commit path lacks the post-write source snapshot")
    require("build_applied_patch_result" in source, "patch result builder is missing")
    require("original_start - 5" in source, "patch before context is not five lines")
    require("current_end + 5" in source, "patch after context is not five lines")


def verify_compact_read_outputs(root: Path) -> None:
    """
    Verify that read-only navigation tools do not render aggregate noise by default.
    校验只读导航工具默认不渲染聚合统计噪声。
    """

    renderers = {
        "runtime/codekit-ast-detail.lua": "local function build_ast_detail_text",
        "runtime/codekit-ast-tree.lua": "local function build_tree_content",
        "runtime/codekit-rg.lua": "local function build_rg_markdown",
        "runtime/codekit-markdown-menu.lua": "local function build_markdown_menu_content",
    }
    forbidden = (
        "- files_scanned:",
        "files_scanned: %",
        "- files_with_symbols:",
        "- items_found:",
        "heading_items: %",
    )
    for relative_path, marker in renderers.items():
        source = read_text(root, relative_path)
        rendered = renderer_body(source, marker)
        require(
            not any(item in rendered for item in forbidden),
            f"{relative_path} renderer still exposes aggregate scan counters",
        )

    dead_aggregate_fields = (
        "files_scanned",
        "files_with_symbols",
        "items_found",
        "files_with_matches",
        "rg_matches",
        "files_with_headings",
        "headings_found",
        "total_rg_matches",
        "total_items",
        "symbol_count",
    )
    for relative_path in renderers:
        source = read_text(root, relative_path)
        require(
            not any(field in source for field in dead_aggregate_fields),
            f"{relative_path} still computes removed aggregate fields",
        )


def verify_cleanup(root: Path) -> None:
    """
    Verify that removed cache and Markdown-export remnants do not return.
    校验已删除的缓存和 Markdown 导出遗留代码不会重新出现。
    """

    ast_detail = read_text(root, "runtime/codekit-ast-detail.lua")
    require("export_md_path" not in ast_detail, "ast-detail still contains the removed export path chain")
    require("LFS_MODULE" not in ast_detail, "ast-detail still contains the removed LuaFileSystem cache state")
    runtime_text = "\n".join(
        path.read_text(encoding="utf-8")
        for path in (root / "runtime").glob("*.lua")
    )
    require("FILE_CACHE" not in runtime_text, "persistent FILE_CACHE marker returned to runtime")
    require("IGNORE_RULE_CACHE" not in runtime_text, "persistent IGNORE_RULE_CACHE marker returned to runtime")


def main() -> int:
    """
    Run every output-contract check and return a process status.
    执行全部输出契约检查并返回进程状态码。
    """

    root = repository_root()
    try:
        verify_node_source_output(root)
        verify_patch_output(root)
        verify_compact_read_outputs(root)
        verify_cleanup(root)
    except Exception as error:  # noqa: BLE001
        print(f"Output contract verification failed: {error}")
        return 1

    print("Output contract verification passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
