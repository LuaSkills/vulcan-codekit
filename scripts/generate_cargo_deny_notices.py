"""
Generate the Rust FFI third-party dependency license report from cargo-deny JSON output.
基于 cargo-deny JSON 输出生成 Rust FFI 第三方依赖许可证报告。
"""

from __future__ import annotations

import argparse
import json
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any


# Repository-relative output path for the generated dependency license report.
# 生成的依赖许可证报告在仓库内的相对输出路径。
DEFAULT_OUTPUT_PATH = Path("THIRD_PARTY_LICENSES.md")

# Cargo-deny version used by CI and expected by local generation.
# CI 与本地生成流程使用的 cargo-deny 版本。
CARGO_DENY_VERSION = "0.19.4"


@dataclass(frozen=True)
class DependencyLicenseRow:
    """
    Describe one third-party Rust package row in the generated license report.
    描述生成许可证报告中的单个第三方 Rust 包条目。

    Parameters:
    参数:
    - name: Package name emitted by cargo-deny.
      cargo-deny 输出的包名。
    - version: Package version emitted by cargo-deny.
      cargo-deny 输出的包版本。
    - declared_license: SPDX expression declared by the package metadata.
      包元数据声明的 SPDX 许可证表达式。
    - detected_licenses: License identifiers detected by cargo-deny.
      cargo-deny 识别出的许可证标识符列表。
    - source: Package source location.
      包来源位置。
    - repository: Upstream repository URL when available.
      可用时的上游仓库 URL。
    """

    name: str
    version: str
    declared_license: str
    detected_licenses: tuple[str, ...]
    source: str
    repository: str


def repo_root() -> Path:
    """
    Return the repository root that owns this script.
    返回拥有当前脚本的仓库根目录。

    Returns:
    返回:
    - Path: Absolute repository root path.
      仓库根目录的绝对路径。
    """
    return Path(__file__).resolve().parent.parent


def run_text_command(command: list[str], cwd: Path) -> str:
    """
    Run one command and return its standard output as text.
    执行一个命令并以文本形式返回标准输出。

    Parameters:
    参数:
    - command: Command argument vector.
      命令参数数组。
    - cwd: Working directory used for command execution.
      命令执行时使用的工作目录。

    Returns:
    返回:
    - str: Standard output emitted by the command.
      命令输出的标准输出文本。
    """
    completed = subprocess.run(
        command,
        cwd=cwd,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return completed.stdout


def load_cargo_deny_license_payload(ffi_dir: Path) -> dict[str, Any]:
    """
    Load crate license data from cargo-deny JSON output.
    从 cargo-deny JSON 输出中加载 crate 许可证数据。

    Parameters:
    参数:
    - ffi_dir: ast-grep FFI crate directory.
      ast-grep FFI crate 所在目录。

    Returns:
    返回:
    - dict[str, Any]: cargo-deny crate-layout JSON object.
      cargo-deny crate 布局的 JSON 对象。
    """
    output = run_text_command(
        [
            "cargo",
            "deny",
            "list",
            "-c",
            "deny.toml",
            "--format",
            "json",
            "--layout",
            "crate",
        ],
        cwd=ffi_dir,
    )
    payload = json.loads(output)
    if not isinstance(payload, dict):
        raise RuntimeError("cargo-deny JSON output must be an object")
    return payload


def load_cargo_metadata(ffi_dir: Path) -> dict[str, Any]:
    """
    Load cargo metadata for enriching cargo-deny rows.
    加载 cargo metadata，用于补充 cargo-deny 条目信息。

    Parameters:
    参数:
    - ffi_dir: ast-grep FFI crate directory.
      ast-grep FFI crate 所在目录。

    Returns:
    返回:
    - dict[str, Any]: Cargo metadata JSON object.
      Cargo metadata JSON 对象。
    """
    output = run_text_command(
        ["cargo", "metadata", "--format-version", "1", "--locked"],
        cwd=ffi_dir,
    )
    payload = json.loads(output)
    if not isinstance(payload, dict):
        raise RuntimeError("cargo metadata output must be an object")
    return payload


def parse_cargo_deny_key(value: str) -> tuple[str, str, str]:
    """
    Parse one cargo-deny crate-layout key into name, version, and source.
    将一个 cargo-deny crate 布局键解析为包名、版本与来源。

    Parameters:
    参数:
    - value: cargo-deny JSON object key.
      cargo-deny JSON 对象键。

    Returns:
    返回:
    - tuple[str, str, str]: Package name, version, and source.
      包名、版本与来源。
    """
    parts = value.split(" ", 2)
    if len(parts) != 3:
        raise RuntimeError(f"Unexpected cargo-deny crate key: {value}")
    return parts[0], parts[1], parts[2]


def build_package_index(metadata: dict[str, Any]) -> dict[tuple[str, str, str], dict[str, Any]]:
    """
    Build a lookup table from cargo package identity to metadata package object.
    构建从 Cargo 包身份到元数据包对象的查询表。

    Parameters:
    参数:
    - metadata: Cargo metadata JSON object.
      Cargo metadata JSON 对象。

    Returns:
    返回:
    - dict[tuple[str, str, str], dict[str, Any]]: Package lookup table keyed by name, version, and source.
      以包名、版本与来源为键的包查询表。
    """
    package_index: dict[tuple[str, str, str], dict[str, Any]] = {}
    for package in metadata.get("packages", []):
        if not isinstance(package, dict):
            continue
        source = package.get("source")
        if not isinstance(source, str):
            continue
        name = str(package.get("name", ""))
        version = str(package.get("version", ""))
        package_index[(name, version, source)] = package
    return package_index


def normalize_license_list(value: Any) -> tuple[str, ...]:
    """
    Normalize a cargo-deny license array into a sorted tuple.
    将 cargo-deny 许可证数组规范化为排序元组。

    Parameters:
    参数:
    - value: cargo-deny licenses field value.
      cargo-deny licenses 字段值。

    Returns:
    返回:
    - tuple[str, ...]: Sorted license identifiers.
      排序后的许可证标识符。
    """
    if not isinstance(value, list):
        return tuple()
    licenses = sorted({str(item) for item in value if str(item).strip()})
    return tuple(licenses)


def build_license_rows(
    cargo_deny_payload: dict[str, Any],
    package_index: dict[tuple[str, str, str], dict[str, Any]],
) -> list[DependencyLicenseRow]:
    """
    Build third-party dependency rows from cargo-deny and cargo metadata.
    根据 cargo-deny 与 cargo metadata 构建第三方依赖条目。

    Parameters:
    参数:
    - cargo_deny_payload: cargo-deny crate-layout JSON object.
      cargo-deny crate 布局 JSON 对象。
    - package_index: Metadata package lookup table.
      元数据包查询表。

    Returns:
    返回:
    - list[DependencyLicenseRow]: Third-party dependency rows sorted by name and version.
      按包名与版本排序的第三方依赖条目列表。
    """
    rows: list[DependencyLicenseRow] = []
    for crate_key, crate_payload in cargo_deny_payload.items():
        name, version, source = parse_cargo_deny_key(crate_key)
        if source.startswith("path+file://"):
            continue
        package = package_index.get((name, version, source), {})
        licenses = normalize_license_list(
            crate_payload.get("licenses") if isinstance(crate_payload, dict) else None
        )
        declared_license = str(package.get("license") or "")
        repository = str(package.get("repository") or package.get("homepage") or "")
        rows.append(
            DependencyLicenseRow(
                name=name,
                version=version,
                declared_license=declared_license or "未声明",
                detected_licenses=licenses,
                source=source,
                repository=repository or "未声明",
            )
        )
    return sorted(rows, key=lambda row: (row.name.lower(), row.version, row.source))


def escape_markdown_cell(value: str) -> str:
    """
    Escape a value for safe Markdown table rendering.
    转义 Markdown 表格单元格中的特殊字符。

    Parameters:
    参数:
    - value: Raw table cell value.
      原始表格单元格内容。

    Returns:
    返回:
    - str: Escaped table cell value.
      转义后的表格单元格内容。
    """
    return value.replace("|", "\\|").replace("\n", " ")


def render_report(rows: list[DependencyLicenseRow]) -> str:
    """
    Render the generated third-party license report as Markdown.
    将生成的第三方许可证报告渲染为 Markdown。

    Parameters:
    参数:
    - rows: Third-party dependency rows.
      第三方依赖条目列表。

    Returns:
    返回:
    - str: Markdown report text.
      Markdown 报告文本。
    """
    license_families: dict[str, int] = {}
    for row in rows:
        for license_name in row.detected_licenses:
            license_families[license_name] = license_families.get(license_name, 0) + 1

    lines = [
        "# 第三方 Rust 依赖许可证报告",
        "",
        "本文件由 `python scripts/generate_cargo_deny_notices.py` 通过 `cargo deny list --format json --layout crate` 自动生成。",
        "",
        "适用范围：`ast-grep-ffi` Rust 动态库构建时进入非 dev 依赖图的第三方 crates。",
        "",
        "说明：",
        "",
        "- 本报告不替代各上游项目的原始许可证文本。",
        "- 发布 FFI 动态库时，应随包保留本报告、`THIRD_PARTY_NOTICES.md` 与仓库 `LICENSE`。",
        "- 本报告排除了当前仓库自身的 workspace crate，仅列出第三方依赖。",
        "",
        "## 许可证统计",
        "",
        "| License | Crates |",
        "| --- | ---: |",
    ]
    for license_name, count in sorted(license_families.items()):
        lines.append(f"| `{escape_markdown_cell(license_name)}` | {count} |")

    lines.extend(
        [
            "",
            "## 依赖清单",
            "",
            "| Crate | Version | Declared License | cargo-deny Licenses | Source | Repository |",
            "| --- | --- | --- | --- | --- | --- |",
        ]
    )
    for row in rows:
        detected = ", ".join(f"`{license_name}`" for license_name in row.detected_licenses)
        lines.append(
            "| "
            + " | ".join(
                [
                    f"`{escape_markdown_cell(row.name)}`",
                    escape_markdown_cell(row.version),
                    f"`{escape_markdown_cell(row.declared_license)}`",
                    detected or "未识别",
                    escape_markdown_cell(row.source),
                    escape_markdown_cell(row.repository),
                ]
            )
            + " |"
        )
    lines.append("")
    return "\n".join(lines)


def generate_report(root: Path) -> str:
    """
    Generate the full third-party license report for the repository.
    为仓库生成完整第三方许可证报告。

    Parameters:
    参数:
    - root: Repository root path.
      仓库根目录路径。

    Returns:
    返回:
    - str: Generated Markdown report text.
      生成后的 Markdown 报告文本。
    """
    ffi_dir = root / "ast-grep-ffi"
    cargo_deny_payload = load_cargo_deny_license_payload(ffi_dir)
    metadata = load_cargo_metadata(ffi_dir)
    rows = build_license_rows(cargo_deny_payload, build_package_index(metadata))
    return render_report(rows)


def parse_args() -> argparse.Namespace:
    """
    Parse command-line arguments for the license report generator.
    解析许可证报告生成器的命令行参数。

    Returns:
    返回:
    - argparse.Namespace: Parsed command-line arguments.
      解析后的命令行参数。
    """
    parser = argparse.ArgumentParser(description="Generate cargo-deny based third-party license notices.")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT_PATH), help="Repository-relative output path.")
    parser.add_argument("--check", action="store_true", help="Fail when the generated report differs from disk.")
    return parser.parse_args()


def main() -> int:
    """
    Execute the license report generation or freshness check.
    执行许可证报告生成或新鲜度检查。

    Returns:
    返回:
    - int: Process exit code.
      进程退出码。
    """
    args = parse_args()
    root = repo_root()
    output_path = (root / args.output).resolve()
    report = generate_report(root)
    if args.check:
        existing = output_path.read_text(encoding="utf-8") if output_path.exists() else ""
        if existing != report:
            raise RuntimeError(
                f"{output_path.relative_to(root)} is stale; run python scripts/generate_cargo_deny_notices.py"
            )
        print(f"License report is up to date: {output_path}")
        return 0
    output_path.write_text(report, encoding="utf-8")
    print(f"License report generated: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
