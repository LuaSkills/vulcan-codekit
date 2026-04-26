"""
Package one ast-grep FFI dynamic library for GitHub release upload.
为 GitHub Release 上传打包一个 ast-grep FFI 动态库。
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


"""
Return the repository root that also acts as the skill root.
返回同时作为技能根目录的仓库根目录。
"""
def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


"""
Validate a required file argument and return its absolute path.
校验必需文件参数并返回其绝对路径。
"""
def resolve_required_file(value: str) -> Path:
    path = Path(value).resolve()
    if not path.is_file():
        raise RuntimeError(f"Missing FFI library: {path}")
    return path


"""
Build one platform-specific FFI zip and checksum file.
构建一个平台专属 FFI zip 与校验文件。
"""
def build_ffi_package(out_dir: Path, platform: str, library_path: Path) -> tuple[Path, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    package_name = f"ast-grep-ffi-{platform}.zip"
    checksum_name = f"ast-grep-ffi-{platform}.sha256.txt"
    package_path = out_dir / package_name
    checksum_path = out_dir / checksum_name

    with ZipFile(package_path, "w", compression=ZIP_DEFLATED) as archive:
        archive.write(library_path, library_path.name)

    digest = hashlib.sha256(package_path.read_bytes()).hexdigest()
    checksum_path.write_text(f"{digest}  {package_name}\n", encoding="utf-8")
    return package_path, checksum_path


"""
Parse command-line arguments for the FFI package builder.
解析 FFI 打包脚本使用的命令行参数。
"""
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Package one ast-grep FFI release asset.")
    parser.add_argument("--platform", required=True, help="LuaSkills platform key, such as linux-x64.")
    parser.add_argument("--library-path", required=True, help="Compiled dynamic library path.")
    parser.add_argument("--out-dir", default="dist", help="Output directory for release assets.")
    return parser.parse_args()


"""
Run the FFI package build and print the generated artifact paths.
执行 FFI 打包流程并输出生成的产物路径。
"""
def main() -> int:
    args = parse_args()
    root = repo_root()
    out_dir = (root / args.out_dir).resolve()
    library_path = resolve_required_file(args.library_path)
    package_path, checksum_path = build_ffi_package(out_dir, args.platform, library_path)
    print(f"FFI package created: {package_path}")
    print(f"FFI checksum created: {checksum_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
