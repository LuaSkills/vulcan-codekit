"""
Validate the Vulcan CodeKit LuaSkill repository against the strict package rules.
校验 Vulcan CodeKit LuaSkill 仓库是否满足严格包结构规则。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml


"""
Return the repository root that also acts as the skill root.
返回同时作为技能根目录的仓库根目录。
"""
def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


"""
Raise one validation error when the condition is false.
当条件不成立时抛出一条校验错误。
"""
def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


"""
Return whether one version string follows strict semantic-version syntax.
返回单个版本字符串是否满足严格的语义化版本语法。
"""
def is_valid_semver(value: str) -> bool:
    pattern = re.compile(
        r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
        r"(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?"
        r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
    )
    return bool(pattern.fullmatch(value.strip()))


"""
Load one YAML document from disk.
从磁盘加载一份 YAML 文档。
"""
def load_yaml(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        payload = yaml.safe_load(handle) or {}
    require(isinstance(payload, dict), f"Expected one YAML object in {path}")
    return payload


"""
Validate the strict top-level repository layout.
校验严格的顶层仓库目录结构。
"""
def validate_layout(root: Path) -> None:
    required_files = [
        root / "skill.yaml",
        root / "dependencies.yaml",
        root / "README.md",
        root / "THIRD_PARTY_NOTICES.md",
    ]
    required_dirs = [
        root / "runtime",
        root / "help",
        root / "overflow_templates",
        root / "rules",
        root / "skills",
    ]

    for file_path in required_files:
        require(file_path.is_file(), f"Missing required file: {file_path.name}")
    for dir_path in required_dirs:
        require(dir_path.is_dir(), f"Missing required directory: {dir_path.name}")


"""
Validate the skill manifest and entry references.
校验技能清单及其入口引用。
"""
def validate_manifest(root: Path) -> None:
    manifest = load_yaml(root / "skill.yaml")
    require("skill_id" not in manifest, "skill.yaml must not declare skill_id")
    version = manifest.get("version")
    require(isinstance(version, str) and version.strip(), "skill.yaml must declare a non-empty version")
    require(is_valid_semver(version), "skill.yaml version must be a valid semantic version")
    entries = manifest.get("entries")
    require(isinstance(entries, list) and entries, "skill.yaml must declare at least one entry")

    for entry in entries:
        require(isinstance(entry, dict), "Each entry must be one YAML object")
        entry_name = entry.get("name")
        lua_entry = entry.get("lua_entry")
        require(isinstance(entry_name, str) and entry_name, "Each entry requires a non-empty name")
        require(isinstance(lua_entry, str) and lua_entry, f"Entry '{entry_name}' requires lua_entry")
        require((root / lua_entry).is_file(), f"Entry '{entry_name}' points to a missing file: {lua_entry}")

    help_block = manifest.get("help", {})
    main_help = help_block.get("main")
    require(isinstance(main_help, dict), "skill.yaml must declare help.main")
    main_help_file = main_help.get("file")
    require(isinstance(main_help_file, str) and main_help_file, "help.main.file must be a non-empty string")
    require((root / main_help_file).is_file(), f"Main help file is missing: {main_help_file}")

    for topic in help_block.get("topics", []) or []:
        require(isinstance(topic, dict), "Each help topic must be one YAML object")
        topic_name = topic.get("name")
        topic_file = topic.get("file")
        require(isinstance(topic_name, str) and topic_name, "Each help topic requires a non-empty name")
        require(isinstance(topic_file, str) and topic_file, f"Help topic '{topic_name}' requires one file path")
        require((root / topic_file).is_file(), f"Help topic '{topic_name}' points to a missing file: {topic_file}")


"""
Validate the dependency manifest used by the CodeKit package.
校验 CodeKit 包使用的依赖清单。
"""
def validate_dependencies(root: Path) -> None:
    dependency_manifest = load_yaml(root / "dependencies.yaml")
    tools = dependency_manifest.get("tool_dependencies", [])
    require(isinstance(tools, list), "tool_dependencies must be a YAML list")
    require(any(item.get("name") == "rg" for item in tools if isinstance(item, dict)), "CodeKit must declare one rg dependency")
    rg_dependency = next(item for item in tools if isinstance(item, dict) and item.get("name") == "rg")
    rg_packages = rg_dependency.get("packages", {})
    require(isinstance(rg_packages, dict) and rg_packages, "rg must declare platform packages")
    for platform_name in ("windows-x64", "linux-x64", "linux-arm64", "macos-arm64", "macos-x64"):
        require(platform_name in rg_packages, f"rg missing package for {platform_name}")
    require(not any(item.get("name") == "ast-grep" for item in tools if isinstance(item, dict)), "ast-grep must be provided as an FFI dependency, not as a CLI tool dependency")

    lua_dependencies = dependency_manifest.get("lua_dependencies", [])
    ffi_dependencies = dependency_manifest.get("ffi_dependencies", [])
    require(isinstance(lua_dependencies, list), "lua_dependencies must be a YAML list")
    require(isinstance(ffi_dependencies, list), "ffi_dependencies must be a YAML list")
    require(
        any(item.get("name") == "ast-grep-ffi" for item in ffi_dependencies if isinstance(item, dict)),
        "CodeKit must declare one ast-grep-ffi dependency",
    )
    ast_grep_ffi = next(
        item for item in ffi_dependencies if isinstance(item, dict) and item.get("name") == "ast-grep-ffi"
    )
    ast_grep_source = ast_grep_ffi.get("source", {})
    require(isinstance(ast_grep_source, dict), "ast-grep-ffi must declare one source object")
    ast_grep_github = ast_grep_source.get("github", {})
    require(ast_grep_source.get("type") == "github_release", "ast-grep-ffi must install from GitHub Release")
    require(isinstance(ast_grep_github, dict), "ast-grep-ffi github_release source must declare github config")
    require(
        ast_grep_github.get("repo") == "LuaSkills/vulcan-codekit",
        "ast-grep-ffi must point to the current GitHub release repository",
    )
    packages = ast_grep_ffi.get("packages", {})
    require(isinstance(packages, dict) and packages, "ast-grep-ffi must declare platform packages")
    for platform_name in ("windows-x64", "linux-x64", "linux-arm64", "macos-arm64", "macos-x64"):
        require(platform_name in packages, f"ast-grep-ffi missing package for {platform_name}")

    for group_name in ("lua_dependencies", "ffi_dependencies"):
        group = dependency_manifest.get(group_name, [])
        require(isinstance(group, list), f"{group_name} must be a YAML list")


"""
Execute the repository validation flow and return one process exit code.
执行仓库校验流程并返回进程退出码。
"""
def main() -> int:
    root = repo_root()
    try:
        validate_layout(root)
        validate_manifest(root)
        validate_dependencies(root)
    except Exception as error:  # noqa: BLE001
        print(f"Validation failed: {error}")
        return 1

    print("Validation passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
