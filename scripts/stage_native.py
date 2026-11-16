"""
Stage the CodeKit FFI libraries and ripgrep archives declared in dependencies.yaml.
暂存 dependencies.yaml 声明的 CodeKit FFI 动态库与 ripgrep 归档。

The libraries come from verified codekit-ffi-{platform}.zip assets: either a local directory produced by
the release FFI builds, or the GitHub release named by the reused codekit-ffi version.
动态库来自经过校验的 codekit-ffi-{platform}.zip 资产：要么是发布 FFI 构建产出的本地目录，要么是
被复用的 codekit-ffi 版本对应的 GitHub Release。

Keep the upstream ripgrep archives intact so the package also carries their license files.
保留 ripgrep 上游归档的原始内容，使技能包同时携带其中的许可证文件。
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import tempfile
import urllib.request
from pathlib import Path
from zipfile import ZipFile

import yaml


"""
Return the repository root that also acts as the skill root.
返回同时作为技能根目录的仓库根目录。
"""
def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


"""
Read one named bundled dependency from a manifest group.
从清单指定分组中读取一个具名的内置依赖。
"""
def bundled_dependency(manifest: dict, group: str, name: str) -> dict:
    matches = [
        item
        for item in manifest[group]
        if isinstance(item, dict) and item.get("name") == name
    ]
    if len(matches) != 1 or matches[0]["source"] != {"type": "bundled"}:
        raise RuntimeError(f"dependencies.yaml must declare exactly one bundled {name} dependency")
    return matches[0]


"""
Download the named release asset from a GitHub repository to target_dir and return its path.
从指定 GitHub 仓库下载发布资产到 target_dir 并返回其路径。
"""
def download_asset(repository: str, tag: str, asset_name: str, target_dir: Path) -> Path:
    url = f"https://github.com/{repository}/releases/download/{tag}/{asset_name}"
    target_path = target_dir / asset_name
    with urllib.request.urlopen(url, timeout=120) as response, target_path.open("wb") as output:
        shutil.copyfileobj(response, output)
    return target_path


"""
Verify an asset archive against the supplied SHA-256 digest.
根据给定的 SHA-256 摘要校验资产归档。
"""
def verify_checksum(archive_path: Path, expected_digest: str) -> None:
    actual_digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    if actual_digest != expected_digest:
        raise RuntimeError(f"Checksum mismatch for {archive_path.name}: expected {expected_digest}, got {actual_digest}")


"""
Extract the declared library from one verified FFI zip into its bundled payload path.
将声明的动态库从一个已校验的 FFI zip 解出到其内置载荷路径。
"""
def stage_platform(root: Path, archive_path: Path, payload_path: str, library_name: str) -> Path:
    target_path = root / payload_path
    target_path.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(archive_path) as archive:
        if library_name not in archive.namelist():
            raise RuntimeError(f"{archive_path.name} does not contain {library_name}")
        with archive.open(library_name) as source, target_path.open("wb") as output:
            shutil.copyfileobj(source, output)
    return target_path


"""
Stage the upstream ripgrep archives using each platform's locked payload path and digest.
按各平台锁定的载荷路径和摘要暂存 ripgrep 上游归档。
"""
def stage_ripgrep(root: Path, dependency: dict, download_dir: Path) -> None:
    # Keep the archive as published so LuaSkills can use the original export path and license files.
    # 保留发布归档的原样字节，使 LuaSkills 可沿用原导出路径并保留许可证文件。
    for platform, package in sorted(dependency["packages"].items()):
        target_path = root / package["path"]
        archive_path = download_asset(
            "BurntSushi/ripgrep", str(dependency["version"]), target_path.name, download_dir
        )
        verify_checksum(archive_path, package["sha256"])
        target_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(archive_path, target_path)
        print(f"Staged ripgrep for {platform}: {target_path.relative_to(root).as_posix()}")


"""
Parse the source selection for FFI; ripgrep always comes from its pinned upstream release.
解析 FFI 的来源选择，ripgrep 始终取自已锁定的上游发布。
"""
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Stage bundled CodeKit dependencies into native/.")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--asset-dir", help="Directory holding codekit-ffi-{platform}.zip and .sha256.txt files.")
    source.add_argument(
        "--from-release",
        action="store_true",
        help="Download the assets from release v{codekit-ffi version} declared in dependencies.yaml.",
    )
    return parser.parse_args()


"""
Stage the required library and tool archives and fail when any platform is missing.
暂存必需的动态库和工具归档，任一平台缺失即失败。
"""
def main() -> int:
    args = parse_args()
    root = repo_root()
    with (root / "dependencies.yaml").open("r", encoding="utf-8") as handle:
        manifest = yaml.safe_load(handle)
    ffi = bundled_dependency(manifest, "ffi_dependencies", "codekit-ffi")
    ripgrep = bundled_dependency(manifest, "tool_dependencies", "rg")
    native_root = root / "native"
    if native_root.exists():
        shutil.rmtree(native_root)

    with tempfile.TemporaryDirectory() as temporary_dir:
        download_dir = Path(temporary_dir)
        asset_dir = Path(args.asset_dir).resolve() if args.asset_dir else download_dir
        for platform, package in sorted(ffi["packages"].items()):
            exports = package["exports"]
            if len(exports) != 1:
                raise RuntimeError(f"codekit-ffi {platform} must export exactly one library")
            archive_name = f"codekit-ffi-{platform}.zip"
            checksum_name = f"codekit-ffi-{platform}.sha256.txt"
            if args.from_release:
                tag = f"v{ffi['version']}"
                download_asset("LuaSkills/vulcan-codekit", tag, archive_name, asset_dir)
                download_asset("LuaSkills/vulcan-codekit", tag, checksum_name, asset_dir)
            archive_path = asset_dir / archive_name
            checksum_path = asset_dir / checksum_name
            if not archive_path.is_file() or not checksum_path.is_file():
                raise RuntimeError(f"Missing {archive_name} or {checksum_name} in {asset_dir}")
            verify_checksum(archive_path, checksum_path.read_text(encoding="utf-8").split()[0].lower())
            staged_path = stage_platform(root, archive_path, package["path"], exports[0]["archive_path"])
            print(f"Staged {platform}: {staged_path.relative_to(root).as_posix()}")
        stage_ripgrep(root, ripgrep, download_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
