"""
Validate the Vulcan CodeKit LuaSkill repository against the strict package rules.
校验 Vulcan CodeKit LuaSkill 仓库是否满足严格包结构规则。
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tomllib
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
Return the numeric major, minor, and patch components of one semantic version.
返回单个语义化版本的主、次、补丁数字分量。
"""
def semver_core(value: str) -> tuple[int, int, int]:
    match = re.match(r"^(\d+)\.(\d+)\.(\d+)", value.strip())
    require(match is not None, f"Invalid semantic version: {value}")
    return (int(match.group(1)), int(match.group(2)), int(match.group(3)))


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
Load one JSON document from disk and require one top-level object.
从磁盘加载一份 JSON 文档，并要求其顶层为对象。

Parameters / 参数:
- path: JSON file path. / JSON 文件路径。

Returns / 返回值:
- Parsed top-level JSON object. / 解析后的顶层 JSON 对象。
"""
def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    require(isinstance(payload, dict), f"Expected one JSON object in {path}")
    return payload


"""
Load one TOML document from disk.
从磁盘加载一份 TOML 文档。
"""
def load_toml(path: Path) -> dict:
    with path.open("rb") as handle:
        payload = tomllib.load(handle)
    require(isinstance(payload, dict), f"Expected one TOML object in {path}")
    return payload


"""
Return the authoritative codekit-ffi version declared by its Cargo package table.
返回 codekit-ffi Cargo package 表声明的权威版本。
"""
def read_ffi_version(root: Path) -> str:
    cargo_package = load_toml(root / "codekit-ffi" / "Cargo.toml").get("package", {})
    require(isinstance(cargo_package, dict), "codekit-ffi Cargo.toml must declare [package]")
    return str(cargo_package.get("version", "")).strip()


"""
Validate the strict top-level repository layout.
校验严格的顶层仓库目录结构。
"""
def validate_layout(root: Path) -> None:
    required_files = [
        root / "skill.yaml",
        root / "dependencies.yaml",
        root / "README.md",
        root / "LICENSE",
        root / "THIRD_PARTY_NOTICES.md",
        root / "THIRD_PARTY_LICENSES.md",
        root / "runtime" / "codekit-ffi.lua",
        root / "runtime" / "codekit-path.lua",
        root / "runtime" / "codekit-repo-map.lua",
        root / "help" / "repo-map.md",
        root / "codekit-ffi" / "Cargo.toml",
        root / "codekit-ffi" / "Cargo.lock",
        root / "codekit-ffi" / "deny.toml",
        root / "codekit-ffi" / "src" / "lib.rs",
        root / "codekit-ffi" / "src" / "ast_grep.rs",
        root / "codekit-ffi" / "src" / "repo_stats.rs",
    ]
    required_dirs = [
        root / "runtime",
        root / "help",
        root / "overflow_templates",
        root / "rules",
        root / "schemas",
        root / "skills",
        root / "codekit-ffi",
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

    # Collect only validated tool identities so malformed values produce precise errors.
    # 仅收集已校验的工具身份，使畸形值产生精确错误。
    entry_names: list[str] = []
    for entry in entries:
        require(isinstance(entry, dict), "Each entry must be one YAML object")
        entry_name = entry.get("name")
        lua_entry = entry.get("lua_entry")
        require(isinstance(entry_name, str) and entry_name, "Each entry requires a non-empty name")
        require(isinstance(lua_entry, str) and lua_entry, f"Entry '{entry_name}' requires lua_entry")
        require((root / lua_entry).is_file(), f"Entry '{entry_name}' points to a missing file: {lua_entry}")
        entry_names.append(entry_name)
    require(len(entry_names) == len(set(entry_names)), "skill.yaml entry names must be unique")

    # Pin the repository-first entry to its exact runtime and help contracts.
    # 将仓库优先入口锁定到精确运行时与帮助契约。
    repo_map_entry = next((entry for entry in entries if entry.get("name") == "repo-map"), None)
    require(isinstance(repo_map_entry, dict), "skill.yaml must declare the repo-map entry")
    require(repo_map_entry.get("lua_entry") == "runtime/codekit-repo-map.lua", "repo-map must use runtime/codekit-repo-map.lua")
    require(repo_map_entry.get("help") == "repo-map", "repo-map must use the repo-map help topic")

    help_block = manifest.get("help", {})
    main_help = help_block.get("main")
    require(isinstance(main_help, dict), "skill.yaml must declare help.main")
    main_help_file = main_help.get("file")
    require(isinstance(main_help_file, str) and main_help_file, "help.main.file must be a non-empty string")
    require((root / main_help_file).is_file(), f"Main help file is missing: {main_help_file}")

    topics = help_block.get("topics", []) or []
    require(isinstance(topics, list), "help.topics must be a YAML list")
    # Collect only validated help identities so malformed values produce precise errors.
    # 仅收集已校验的帮助身份，使畸形值产生精确错误。
    topic_names: list[str] = []
    for topic in topics:
        require(isinstance(topic, dict), "Each help topic must be one YAML object")
        topic_name = topic.get("name")
        topic_file = topic.get("file")
        require(isinstance(topic_name, str) and topic_name, "Each help topic requires a non-empty name")
        require(isinstance(topic_file, str) and topic_file, f"Help topic '{topic_name}' requires one file path")
        require((root / topic_file).is_file(), f"Help topic '{topic_name}' points to a missing file: {topic_file}")
        topic_names.append(topic_name)
    require(len(topic_names) == len(set(topic_names)), "skill.yaml help topic names must be unique")

    # Require the repository-first help topic to point to the checked-in guide.
    # 要求仓库优先帮助主题指向已纳入仓库的指南。
    repo_map_topic = next((topic for topic in topics if topic.get("name") == "repo-map"), None)
    require(isinstance(repo_map_topic, dict), "skill.yaml must declare the repo-map help topic")
    require(repo_map_topic.get("file") == "help/repo-map.md", "repo-map help must use help/repo-map.md")


"""
Validate the shared host-managed PWD declaration and runtime usage for every path-bearing CodeKit tool.
校验所有携带路径的 CodeKit 工具是否统一声明并使用宿主管理的 PWD。
"""
def validate_pwd_contracts(root: Path) -> None:
    """
    Validate shared host-managed PWD declarations and runtime use for every path-bearing tool.
    校验所有携带路径工具的宿主管理 PWD 声明与运行时使用。

    Parameters / 参数:
    - root: Repository and LuaSkill root directory. / 仓库与 LuaSkill 根目录。

    Returns / 返回值:
    - None. Raises when any PWD contract diverges. / 无返回；任一 PWD 契约偏离时抛出异常。
    """
    # Load the canonical manifest that drives host-visible tool schemas.
    # 加载驱动宿主可见工具 Schema 的规范清单。
    manifest = load_yaml(root / "skill.yaml")
    # Index manifest entries once so every expected path-bearing tool is checked by identity.
    # 对清单入口建立一次索引，按身份校验每个预期携带路径的工具。
    entries_by_name = {
        entry.get("name"): entry
        for entry in manifest.get("entries", [])
        if isinstance(entry, dict) and isinstance(entry.get("name"), str)
    }
    # Pin the complete current path-bearing surface instead of accepting a partial rollout.
    # 锁定当前完整的路径工具面，避免只接入部分工具却静默通过。
    path_entry_names = (
        "repo-map",
        "ast-detail",
        "rg",
        "markdown-menu",
        "node-source",
        "ast-tree",
        "patch",
    )

    for entry_name in path_entry_names:
        # Resolve the exact manifest entry and require its public input contract.
        # 解析精确清单入口并要求其公开输入契约存在。
        entry = entries_by_name.get(entry_name)
        require(isinstance(entry, dict), f"Missing path-bearing entry: {entry_name}")
        # Legacy parameter lists and JSON Schema entries use different declaration formats.
        # 旧式参数列表与 JSON Schema 入口使用不同的声明格式。
        parameters = entry.get("parameters")
        schema_file = entry.get("input_schema_file")

        if isinstance(parameters, list):
            # Require exactly one top-level uppercase PWD descriptor.
            # 要求恰好一个顶层大写 PWD 描述符。
            pwd_parameters = [
                parameter
                for parameter in parameters
                if isinstance(parameter, dict) and parameter.get("name") == "PWD"
            ]
            require(len(pwd_parameters) == 1, f"Entry '{entry_name}' must declare exactly one top-level PWD parameter")
            # Validate the host-recognized optional string shape.
            # 校验宿主可识别的可选字符串形态。
            pwd_parameter = pwd_parameters[0]
            require(pwd_parameter.get("type") == "string", f"Entry '{entry_name}' PWD must have type string")
            require(pwd_parameter.get("required") is False, f"Entry '{entry_name}' PWD must be optional")
            # Keep host-management behavior explicit in generated tool descriptions.
            # 在生成的工具描述中明确保留宿主管理行为。
            pwd_description = pwd_parameter.get("description")
            require(
                isinstance(pwd_description, str)
                and "VulcanCode" in pwd_description
                and "hides and injects" in pwd_description,
                f"Entry '{entry_name}' PWD description must explain VulcanCode hiding and injection",
            )
        else:
            require(
                isinstance(schema_file, str) and schema_file,
                f"Entry '{entry_name}' must declare parameters or input_schema_file",
            )
            # Load the external schema exactly as the host exposes it.
            # 按宿主实际暴露方式加载外部 Schema。
            input_schema = load_json(root / schema_file)
            # Read only root properties so nested items cannot masquerade as host-managed PWD.
            # 仅读取根属性，避免嵌套条目冒充宿主管理的 PWD。
            properties = input_schema.get("properties")
            require(isinstance(properties, dict), f"Schema for '{entry_name}' must declare root properties")
            # Validate the root-level PWD property and host-management description.
            # 校验根级 PWD 属性及宿主管理说明。
            pwd_property = properties.get("PWD")
            require(isinstance(pwd_property, dict), f"Schema for '{entry_name}' must declare root PWD")
            require(pwd_property.get("type") == "string", f"Schema for '{entry_name}' PWD must have type string")
            pwd_description = pwd_property.get("description")
            require(
                isinstance(pwd_description, str)
                and "VulcanCode" in pwd_description
                and "hides and injects" in pwd_description,
                f"Schema for '{entry_name}' PWD description must explain VulcanCode hiding and injection",
            )
            # PWD stays optional so other hosts can continue using absolute target paths.
            # PWD 保持可选，使其他宿主仍可继续使用绝对目标路径。
            required_properties = input_schema.get("required", [])
            require(isinstance(required_properties, list), f"Schema for '{entry_name}' required must be a list")
            require("PWD" not in required_properties, f"Schema for '{entry_name}' must not require PWD")

        # Pin runtime consumption so public declarations cannot drift from path resolution.
        # 锁定运行时消费，避免公开声明与路径解析发生漂移。
        lua_entry = entry.get("lua_entry")
        require(isinstance(lua_entry, str) and lua_entry, f"Entry '{entry_name}' requires lua_entry")
        # Read the checked-in runtime source using explicit UTF-8.
        # 使用显式 UTF-8 读取已纳入仓库的运行时源码。
        runtime_source = (root / lua_entry).read_text(encoding="utf-8")
        require(
            "resolve_pwd_root(args and args.PWD)" in runtime_source,
            f"Entry '{entry_name}' runtime must resolve args.PWD through the shared contract",
        )


"""
Validate the dependency manifest used by the CodeKit package.
校验 CodeKit 包使用的依赖清单。
"""
def validate_dependencies(root: Path) -> None:
    # Load the skill version; the FFI version is independent but may never be newer than the skill.
    # 加载技能版本；FFI 版本独立演进，但不得新于技能版本。
    skill_manifest = load_yaml(root / "skill.yaml")
    skill_version = str(skill_manifest.get("version"))
    # Load the unified native crate version from its authoritative Cargo package table.
    # 从权威 Cargo package 表加载统一原生 crate 版本。
    cargo_manifest = load_toml(root / "codekit-ffi" / "Cargo.toml")
    cargo_package = cargo_manifest.get("package", {})
    require(isinstance(cargo_package, dict), "codekit-ffi Cargo.toml must declare [package]")
    require(cargo_package.get("name") == "vulcan-codekit-ffi", "codekit-ffi Cargo package name mismatch")
    ffi_version = read_ffi_version(root)
    require(is_valid_semver(ffi_version), "codekit-ffi Cargo version must be a semantic version")
    require(
        semver_core(ffi_version) <= semver_core(skill_version),
        "codekit-ffi Cargo version must not be newer than skill.yaml version",
    )
    # Keep the lockfile root package identical to the manifest version.
    # 保持锁文件根 package 版本与清单版本一致。
    cargo_lock = load_toml(root / "codekit-ffi" / "Cargo.lock")
    locked_versions = [
        item.get("version")
        for item in cargo_lock.get("package", [])
        if isinstance(item, dict) and item.get("name") == "vulcan-codekit-ffi"
    ]
    require(locked_versions == [ffi_version], "codekit-ffi Cargo.lock version must match Cargo.toml version")
    # Validate the unified dynamic-library identity and the exact no-CLI Tokei integration.
    # 校验统一动态库身份与精确的无 CLI Tokei 集成。
    cargo_library = cargo_manifest.get("lib", {})
    require(isinstance(cargo_library, dict), "codekit-ffi Cargo.toml must declare [lib]")
    require(cargo_library.get("name") == "vulcan_codekit_ffi", "codekit-ffi Cargo library name mismatch")
    crate_types = cargo_library.get("crate-type", [])
    require(isinstance(crate_types, list) and "cdylib" in crate_types, "codekit-ffi must build a cdylib")
    cargo_dependencies = cargo_manifest.get("dependencies", {})
    require(isinstance(cargo_dependencies, dict), "codekit-ffi Cargo.toml must declare dependencies")
    tokei_dependency = cargo_dependencies.get("tokei", {})
    require(isinstance(tokei_dependency, dict), "Tokei must use an explicit Cargo dependency table")
    require(tokei_dependency.get("version") == "=15.0.0", "Tokei must be pinned exactly to 15.0.0")
    require(tokei_dependency.get("default-features") is False, "Tokei default CLI features must remain disabled")

    # Pin the Lua loader identity and version to the validated release contract.
    # 将 Lua 加载器身份与版本锁定到已校验的发布契约。
    loader_text = (root / "runtime" / "codekit-ffi.lua").read_text(encoding="utf-8")
    dependency_name_match = re.search(r'^local CODEKIT_FFI_DEPENDENCY_NAME = "([^"]+)"$', loader_text, re.MULTILINE)
    loader_version_match = re.search(r'^local CODEKIT_FFI_VERSION = "([^"]+)"$', loader_text, re.MULTILINE)
    require(
        dependency_name_match is not None and dependency_name_match.group(1) == "codekit-ffi",
        "CodeKit FFI Lua dependency identity mismatch",
    )
    require(
        loader_version_match is not None and loader_version_match.group(1) == ffi_version,
        "CodeKit FFI Lua loader version must match codekit-ffi Cargo version",
    )
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
    codekit_dependencies = [
        item for item in ffi_dependencies if isinstance(item, dict) and item.get("name") == "codekit-ffi"
    ]
    require(len(codekit_dependencies) == 1, "CodeKit must declare exactly one codekit-ffi dependency")
    require(
        not any(item.get("name") == "ast-grep-ffi" for item in ffi_dependencies if isinstance(item, dict)),
        "The retired ast-grep-ffi dependency name must not remain in dependencies.yaml",
    )
    codekit_ffi = codekit_dependencies[0]
    require(codekit_ffi.get("version") == ffi_version, "codekit-ffi dependency version must match codekit-ffi Cargo version")
    codekit_source = codekit_ffi.get("source", {})
    require(isinstance(codekit_source, dict), "codekit-ffi must declare one source object")
    codekit_github = codekit_source.get("github", {})
    require(codekit_source.get("type") == "github_release", "codekit-ffi must install from GitHub Release")
    require(isinstance(codekit_github, dict), "codekit-ffi github_release source must declare github config")
    require(
        codekit_github.get("repo") == "LuaSkills/vulcan-codekit",
        "codekit-ffi must point to the current GitHub release repository",
    )
    packages = codekit_ffi.get("packages", {})
    require(isinstance(packages, dict) and packages, "codekit-ffi must declare platform packages")
    # Map each required platform to its exact release asset and dynamic-library filename.
    # 将每个必需平台映射到精确发布资产与动态库文件名。
    expected_packages = {
        "windows-x64": ("codekit-ffi-windows-x64.zip", "vulcan_codekit_ffi.dll", False),
        "linux-x64": ("codekit-ffi-linux-x64.zip", "libvulcan_codekit_ffi.so", True),
        "linux-arm64": ("codekit-ffi-linux-arm64.zip", "libvulcan_codekit_ffi.so", True),
        "macos-arm64": ("codekit-ffi-macos-arm64.zip", "libvulcan_codekit_ffi.dylib", True),
        "macos-x64": ("codekit-ffi-macos-x64.zip", "libvulcan_codekit_ffi.dylib", True),
    }
    require(set(packages) == set(expected_packages), "codekit-ffi packages must match the supported release matrix exactly")
    for platform_name in expected_packages:
        require(platform_name in packages, f"codekit-ffi missing package for {platform_name}")
        # Validate the exact asset and first exported library path used by LuaSkills installation.
        # 校验 LuaSkills 安装使用的精确资产与第一个导出动态库路径。
        package = packages[platform_name]
        expected_asset, expected_library, expected_executable = expected_packages[platform_name]
        require(package.get("asset_name") == expected_asset, f"codekit-ffi asset mismatch for {platform_name}")
        require(package.get("archive_type") == "zip", f"codekit-ffi archive type mismatch for {platform_name}")
        exports = package.get("exports")
        require(isinstance(exports, list) and len(exports) == 1, f"codekit-ffi must export one library for {platform_name}")
        export = exports[0]
        require(isinstance(export, dict), f"codekit-ffi export must be an object for {platform_name}")
        require(export.get("archive_path") == expected_library, f"codekit-ffi library mismatch for {platform_name}")
        require(export.get("target_path") == f"lib/{expected_library}", f"codekit-ffi target path mismatch for {platform_name}")
        require(bool(export.get("executable", False)) is expected_executable, f"codekit-ffi executable flag mismatch for {platform_name}")

    for group_name in ("lua_dependencies", "ffi_dependencies"):
        group = dependency_manifest.get(group_name, [])
        require(isinstance(group, list), f"{group_name} must be a YAML list")


"""
Validate that a release reusing an older FFI version ships exactly that version's native sources.
校验复用旧 FFI 版本的发布所携带的原生源码与该版本完全一致。

A release whose FFI version equals the skill version builds and publishes the FFI assets itself.
FFI 版本等于技能版本的发布会自行构建并发布 FFI 资产。

Otherwise dependencies.yaml installs the assets from release v{ffi version}, so that tag must exist and
codekit-ffi/ must be unchanged since it; any native change requires bumping the FFI version.
否则 dependencies.yaml 会从 v{FFI 版本} 发布安装资产，因此该标签必须存在，且 codekit-ffi/ 自该标签以来
不得有任何变更；任何原生改动都必须提升 FFI 版本。
"""
def validate_ffi_release_source(root: Path) -> None:
    skill_version = str(load_yaml(root / "skill.yaml")["version"]).strip()
    ffi_version = read_ffi_version(root)
    if ffi_version == skill_version:
        return

    ffi_tag = f"v{ffi_version}"
    tag_lookup = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "--quiet", "--verify", f"refs/tags/{ffi_tag}^{{commit}}"],
        capture_output=True,
        text=True,
    )
    require(
        tag_lookup.returncode == 0,
        f"codekit-ffi {ffi_version} is reused, but its release tag {ffi_tag} does not exist locally",
    )
    native_diff = subprocess.run(
        ["git", "-C", str(root), "diff", "--quiet", ffi_tag, "--", "codekit-ffi"],
        capture_output=True,
        text=True,
    )
    require(
        native_diff.returncode == 0,
        f"codekit-ffi/ changed since {ffi_tag}; bump the codekit-ffi version to the skill version to publish new native assets",
    )


"""
Execute the repository validation flow and return one process exit code.
执行仓库校验流程并返回进程退出码。
"""
def main() -> int:
    # Accept only the machine-readable modes needed by release entrypoints.
    # 仅接受发布入口所需的机器可读模式。
    command_arguments = sys.argv[1:]
    supported_arguments = {"--print-version", "--release"}
    if len(set(command_arguments)) != len(command_arguments) or not set(command_arguments) <= supported_arguments:
        print("Usage: validate_skill.py [--release] [--print-version]")
        return 2

    # Keep normal validation output human-readable while allowing scripts to capture only the version.
    # 保持常规校验输出便于人工阅读，同时允许脚本仅捕获版本号。
    print_version_only = "--print-version" in command_arguments
    # Release mode additionally checks the git history that backs a reused FFI version.
    # 发布模式额外校验支撑复用 FFI 版本的 git 历史。
    release_mode = "--release" in command_arguments

    # Resolve the repository once for every validation and version lookup.
    # 为全部校验与版本读取统一解析一次仓库路径。
    root = repo_root()
    try:
        validate_layout(root)
        validate_manifest(root)
        validate_pwd_contracts(root)
        validate_dependencies(root)
        if release_mode:
            validate_ffi_release_source(root)
    except Exception as error:  # noqa: BLE001
        print(f"Validation failed: {error}")
        return 1

    # Read the already-validated canonical version instead of reparsing YAML in release scripts.
    # 读取已经通过校验的规范版本，避免发布脚本再次解析 YAML。
    skill_version = str(load_yaml(root / "skill.yaml")["version"]).strip()
    if print_version_only:
        print(skill_version)
    else:
        print("Validation passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
