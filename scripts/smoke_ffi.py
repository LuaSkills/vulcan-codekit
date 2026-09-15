"""
Smoke-test the built unified CodeKit dynamic library through its public C ABI.
通过公共 C ABI 对已构建的统一 CodeKit 动态库执行冒烟测试。
"""

from __future__ import annotations

import argparse
import ctypes
import json
import re
import tempfile
from pathlib import Path
from typing import Any, Callable


"""
Resolve the repository root from this checked-in script.
从当前仓库脚本解析仓库根目录。

Returns / 返回值:
- Path: Absolute repository root. / 仓库根目录绝对路径。
"""
def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


"""
Read the exact top-level skill version without introducing a YAML runtime dependency.
在不引入 YAML 运行时依赖的情况下读取精确顶层技能版本。

Parameters / 参数:
- root: Repository root containing skill.yaml. / 包含 skill.yaml 的仓库根目录。

Returns / 返回值:
- str: Semantic version declared by skill.yaml. / skill.yaml 声明的语义化版本。
"""
def read_skill_version(root: Path) -> str:
    # Match only the first top-level version declaration used by release automation.
    # 仅匹配发布自动化使用的第一个顶层版本声明。
    version_pattern = re.compile(r'^version:\s*["\']?([^"\'\s#]+)["\']?\s*(?:#.*)?$', re.MULTILINE)
    # Read the authoritative manifest as UTF-8.
    # 以 UTF-8 读取权威清单。
    manifest_text = (root / "skill.yaml").read_text(encoding="utf-8")
    # Resolve the exact version match before loading the native library.
    # 在加载原生动态库前解析精确版本匹配。
    version_match = version_pattern.search(manifest_text)
    if version_match is None:
        raise RuntimeError("skill.yaml does not declare a readable top-level version")
    return version_match.group(1)


"""
Configure and return one required exported C function.
配置并返回一个必需的 C 导出函数。

Parameters / 参数:
- library: Loaded ctypes dynamic library. / 已加载的 ctypes 动态库。
- name: Exact exported symbol name. / 精确导出符号名称。
- argument_types: ctypes argument declarations. / ctypes 参数声明。
- result_type: ctypes return declaration. / ctypes 返回值声明。

Returns / 返回值:
- Callable[..., Any]: Configured exported function. / 已配置的导出函数。
"""
def configure_function(
    library: ctypes.CDLL,
    name: str,
    argument_types: list[Any],
    result_type: Any,
) -> Callable[..., Any]:
    try:
        # Resolve exactly one required symbol from the native library.
        # 从原生动态库精确解析一个必需符号。
        function = getattr(library, name)
    except AttributeError as error:
        raise RuntimeError(f"required CodeKit FFI symbol is missing: {name}") from error
    function.argtypes = argument_types
    function.restype = result_type
    return function


"""
Read, release, and decode one CodeKit-owned JSON response pointer.
读取、释放并解码一个由 CodeKit 持有的 JSON 响应指针。

Parameters / 参数:
- pointer: Owned native string pointer. / 原生自有字符串指针。
- free_function: Matching CodeKit release function. / 匹配的 CodeKit 释放函数。

Returns / 返回值:
- dict[str, Any]: Decoded JSON response object. / 解码后的 JSON 响应对象。
"""
def decode_owned_json(pointer: int | None, free_function: Callable[..., Any]) -> dict[str, Any]:
    if not pointer:
        raise RuntimeError("CodeKit FFI returned a null JSON response pointer")
    try:
        # Copy UTF-8 bytes before returning the native allocation to Rust.
        # 在把原生分配归还 Rust 前复制 UTF-8 字节。
        response_text = ctypes.string_at(pointer).decode("utf-8")
    finally:
        free_function(pointer)
    # Decode only a JSON object because every CodeKit protocol has an object root.
    # 仅解码 JSON 对象，因为每个 CodeKit 协议都以对象为根。
    payload = json.loads(response_text)
    if not isinstance(payload, dict):
        raise RuntimeError("CodeKit FFI JSON response must be an object")
    return payload


"""
Assert one condition and raise a stable smoke-test failure otherwise.
断言一个条件，否则抛出稳定的冒烟测试错误。

Parameters / 参数:
- condition: Condition that must be true. / 必须为真的条件。
- message: Failure message. / 失败消息。

Returns / 返回值:
- None: Returns only when the condition is true. / 仅在条件成立时返回。
"""
def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


"""
Execute capability, repository-statistics, Unicode-path, and legacy AST ABI checks.
执行能力、仓库统计、Unicode 路径与旧版 AST ABI 检查。

Parameters / 参数:
- library_path: Built platform-native dynamic library. / 已构建的平台原生动态库。
- root: Repository root used for a real Repo Stats scan. / 用于真实 Repo Stats 扫描的仓库根目录。

Returns / 返回值:
- None: Returns after every public ABI check passes. / 全部公共 ABI 检查通过后返回。
"""
def run_smoke(library_path: Path, root: Path) -> None:
    # Load the exact built artifact instead of relying on the process search path.
    # 加载精确构建产物，不依赖进程搜索路径。
    library = ctypes.CDLL(str(library_path))
    # Configure process-lifetime version accessors.
    # 配置进程生命周期版本访问函数。
    unified_version = configure_function(library, "vulcan_codekit_ffi_version", [], ctypes.c_char_p)
    legacy_version = configure_function(library, "vulcan_codekit_ast_grep_version", [], ctypes.c_char_p)
    # Configure owned-response functions and their matching release functions.
    # 配置自有响应函数及其匹配的释放函数。
    capabilities_json = configure_function(library, "vulcan_codekit_ffi_capabilities_json", [], ctypes.c_void_p)
    repo_stats_json = configure_function(
        library,
        "vulcan_codekit_repo_stats_json",
        [ctypes.c_char_p],
        ctypes.c_void_p,
    )
    legacy_scan_json = configure_function(
        library,
        "vulcan_codekit_ast_grep_scan_json",
        [ctypes.c_char_p],
        ctypes.c_void_p,
    )
    unified_free = configure_function(library, "vulcan_codekit_free_string", [ctypes.c_void_p], None)
    legacy_free = configure_function(
        library,
        "vulcan_codekit_ast_grep_free_string",
        [ctypes.c_void_p],
        None,
    )

    # Require both version symbols to identify the same joint release.
    # 要求新旧版本符号标识同一个联合版本。
    expected_version = read_skill_version(root)
    require(unified_version().decode("utf-8") == expected_version, "unified FFI version does not match skill.yaml")
    require(legacy_version().decode("utf-8") == expected_version, "legacy AST FFI version does not match skill.yaml")

    # Verify the discoverable native capability contract.
    # 验证可发现的原生能力契约。
    capabilities = decode_owned_json(capabilities_json(), unified_free)
    capability_contracts = {
        (item.get("name"), str(item.get("protocol")))
        for item in capabilities.get("capabilities", [])
        if isinstance(item, dict)
    }
    require(capabilities.get("ok") is True, "capability discovery failed")
    require(
        capability_contracts == {("ast-grep", "1"), ("repo-stats", "1")},
        "unexpected unified FFI capability protocols",
    )

    # Scan the real checkout to verify non-empty, directory-only repository statistics.
    # 扫描真实检出目录，验证非空且仅含目录的仓库统计。
    repository_request = json.dumps(
        {
            "root": str(root),
            "maxDepth": 2,
            "includeHidden": True,
            "respectIgnore": True,
            "maxRenderedDirectories": 2_000,
        },
        ensure_ascii=False,
    ).encode("utf-8")
    repository_stats = decode_owned_json(repo_stats_json(repository_request), unified_free)
    require(repository_stats.get("ok") is True, "real repository statistics scan failed")
    require(repository_stats.get("totals", {}).get("files", 0) > 0, "real repository scan returned no files")
    require(isinstance(repository_stats.get("directories"), list), "repository directories must be an array")
    require(all("files" not in item for item in repository_stats["directories"]), "directory records must not expose file lists")

    with tempfile.TemporaryDirectory(prefix="codekit-ffi-smoke-") as temporary_root_text:
        # Create one Unicode repository directory to verify path transport through JSON and C ABI.
        # 创建一个 Unicode 仓库目录，验证路径可通过 JSON 与 C ABI 传输。
        unicode_root = Path(temporary_root_text) / "仓库测试"
        unicode_root.mkdir()
        # Write one recognized file and one unrecognized file for exact census assertions.
        # 写入一个已识别文件和一个未识别文件以进行精确普查断言。
        (unicode_root / "示例.rs").write_text("fn main() {}\n", encoding="utf-8")
        (unicode_root / "未知.bin").write_bytes(b"unknown")
        unicode_request = json.dumps(
            {
                "root": str(unicode_root),
                "maxDepth": 1,
                "includeHidden": True,
                "respectIgnore": True,
                "maxRenderedDirectories": 32,
            },
            ensure_ascii=False,
        ).encode("utf-8")
        unicode_stats = decode_owned_json(repo_stats_json(unicode_request), unified_free)
        require(unicode_stats.get("ok") is True, "Unicode repository statistics scan failed")
        require(unicode_stats.get("totals", {}).get("files") == 2, "Unicode file census mismatch")
        require(unicode_stats.get("totals", {}).get("recognizedFiles") == 1, "Unicode recognized-file count mismatch")
        require(unicode_stats.get("totals", {}).get("unrecognizedFiles") == 1, "Unicode unknown-file count mismatch")

        # Reuse the Unicode source file for one legacy-compatible ast-grep request.
        # 复用 Unicode 源文件执行一次兼容旧版的 ast-grep 请求。
        rule_yaml = """id: rust-function\nlanguage: Rust\nseverity: info\nrule:\n  kind: function_item\nmessage: function\n"""
        legacy_request = json.dumps(
            {
                "language": "rust",
                "ruleYaml": rule_yaml,
                "files": [str(unicode_root / "示例.rs")],
            },
            ensure_ascii=False,
        ).encode("utf-8")
        legacy_result = decode_owned_json(legacy_scan_json(legacy_request), legacy_free)
        require(legacy_result.get("ok") is True, "legacy ast-grep scan failed")
        require(len(legacy_result.get("matches", [])) == 1, "legacy ast-grep match count mismatch")


"""
Parse command-line arguments for the native ABI smoke test.
解析原生 ABI 冒烟测试的命令行参数。

Returns / 返回值:
- argparse.Namespace: Parsed command-line arguments. / 已解析的命令行参数。
"""
def parse_args() -> argparse.Namespace:
    # Describe only the exact built library and optional repository root inputs.
    # 仅描述精确构建动态库与可选仓库根目录输入。
    parser = argparse.ArgumentParser(description="Smoke-test the unified CodeKit FFI public ABI.")
    parser.add_argument("--library-path", required=True, help="Built platform-native CodeKit dynamic library.")
    parser.add_argument("--repo-root", default=str(repo_root()), help="Repository root used for real statistics.")
    return parser.parse_args()


"""
Run the command-line smoke test.
执行命令行冒烟测试。

Returns / 返回值:
- int: Zero after all checks pass. / 全部检查通过后返回零。
"""
def main() -> int:
    # Parse and canonicalize the exact requested paths.
    # 解析并规范化精确请求路径。
    arguments = parse_args()
    library_path = Path(arguments.library_path).resolve()
    root = Path(arguments.repo_root).resolve()
    require(library_path.is_file(), f"CodeKit FFI library does not exist: {library_path}")
    require(root.is_dir(), f"repository root does not exist: {root}")
    run_smoke(library_path, root)
    print(f"CodeKit FFI smoke passed: {library_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
