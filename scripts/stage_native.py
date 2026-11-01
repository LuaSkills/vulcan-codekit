"""
Stage the unified CodeKit FFI libraries into native/{platform}/ so the skill package bundles them.
将统一 CodeKit FFI 动态库暂存到 native/{platform}/，使技能包直接携带原生库。

The libraries come from verified codekit-ffi-{platform}.zip assets: either a local directory produced by
the release FFI builds, or the GitHub release named by the reused codekit-ffi version.
动态库来自经过校验的 codekit-ffi-{platform}.zip 资产：要么是发布 FFI 构建产出的本地目录，要么是
被复用的 codekit-ffi 版本对应的 GitHub Release。
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


# GitHub repository that publishes the codekit-ffi release assets.
# 发布 codekit-ffi 资产的 GitHub 仓库。
RELEASE_REPOSITORY = "LuaSkills/vulcan-codekit"


"""
Return the repository root that also acts as the skill root.
返回同时作为技能根目录的仓库根目录。
"""
def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


"""
Return the bundled codekit-ffi declaration as (version, {platform: (payload path, library name)}).
返回内置 codekit-ffi 声明：(版本, {平台: (载荷路径, 动态库文件名)})。
"""
def load_bundled_packages(root: Path) -> tuple[str, dict[str, tuple[str, str]]]:
    with (root / "dependencies.yaml").open("r", encoding="utf-8") as handle:
        manifest = yaml.safe_load(handle) or {}
    matches = [
        item
        for item in manifest.get("ffi_dependencies", [])
        if isinstance(item, dict) and item.get("name") == "codekit-ffi"
    ]
    if len(matches) != 1:
        raise RuntimeError("dependencies.yaml must declare exactly one codekit-ffi dependency")
    dependency = matches[0]
    if dependency.get("source", {}).get("type") != "bundled":
        raise RuntimeError("codekit-ffi must use a bundled source to be staged into the skill package")
    packages: dict[str, tuple[str, str]] = {}
    for platform, package in dependency.get("packages", {}).items():
        exports = package.get("exports", [])
        if len(exports) != 1:
            raise RuntimeError(f"codekit-ffi {platform} must export exactly one library")
        packages[platform] = (package["path"], exports[0]["archive_path"])
    return str(dependency["version"]), packages


"""
Download one release asset into the target directory and return its path.
将一个发布资产下载到目标目录并返回其路径。
"""
def download_asset(tag: str, asset_name: str, target_dir: Path) -> Path:
    url = f"https://github.com/{RELEASE_REPOSITORY}/releases/download/{tag}/{asset_name}"
    target_path = target_dir / asset_name
    with urllib.request.urlopen(url, timeout=120) as response, target_path.open("wb") as output:
        shutil.copyfileobj(response, output)
    return target_path


"""
Verify one FFI zip against its published checksum file.
用发布的校验文件验证一个 FFI zip。
"""
def verify_checksum(archive_path: Path, checksum_path: Path) -> None:
    expected_digest = checksum_path.read_text(encoding="utf-8").split()[0].lower()
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
Parse command-line arguments for the native staging script.
解析原生库暂存脚本的命令行参数。
"""
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Stage bundled CodeKit FFI libraries into native/.")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--asset-dir", help="Directory holding codekit-ffi-{platform}.zip and .sha256.txt files.")
    source.add_argument(
        "--from-release",
        action="store_true",
        help="Download the assets from release v{codekit-ffi version} declared in dependencies.yaml.",
    )
    return parser.parse_args()


"""
Stage every declared platform library and fail when any platform is missing.
暂存每个声明平台的动态库，任一平台缺失即失败。
"""
def main() -> int:
    args = parse_args()
    root = repo_root()
    version, packages = load_bundled_packages(root)
    native_root = root / "native"
    if native_root.exists():
        shutil.rmtree(native_root)

    with tempfile.TemporaryDirectory() as download_dir:
        asset_dir = Path(args.asset_dir).resolve() if args.asset_dir else Path(download_dir)
        for platform, (payload_path, library_name) in sorted(packages.items()):
            archive_name = f"codekit-ffi-{platform}.zip"
            checksum_name = f"codekit-ffi-{platform}.sha256.txt"
            if args.from_release:
                tag = f"v{version}"
                download_asset(tag, archive_name, asset_dir)
                download_asset(tag, checksum_name, asset_dir)
            archive_path = asset_dir / archive_name
            checksum_path = asset_dir / checksum_name
            if not archive_path.is_file() or not checksum_path.is_file():
                raise RuntimeError(f"Missing {archive_name} or {checksum_name} in {asset_dir}")
            verify_checksum(archive_path, checksum_path)
            staged_path = stage_platform(root, archive_path, payload_path, library_name)
            print(f"Staged {platform}: {staged_path.relative_to(root).as_posix()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
