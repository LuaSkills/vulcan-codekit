"""
Package one unified CodeKit FFI dynamic library for GitHub release upload.
为 GitHub Release 上传打包一个统一 CodeKit FFI 动态库。
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


# Map each LuaSkills platform to its exact unified dynamic-library filename.
# 将每个 LuaSkills 平台映射到精确的统一动态库文件名。
EXPECTED_LIBRARY_NAMES = {
    "windows-x64": "vulcan_codekit_ffi.dll",
    "linux-x64": "libvulcan_codekit_ffi.so",
    "linux-arm64": "libvulcan_codekit_ffi.so",
    "macos-arm64": "libvulcan_codekit_ffi.dylib",
    "macos-x64": "libvulcan_codekit_ffi.dylib",
}


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
Return the exact dynamic-library filename required for one release platform.
返回一个发布平台要求的精确动态库文件名。
"""
def expected_library_name(platform: str) -> str:
    try:
        return EXPECTED_LIBRARY_NAMES[platform]
    except KeyError as error:
        supported = ", ".join(sorted(EXPECTED_LIBRARY_NAMES))
        raise RuntimeError(f"Unsupported FFI platform '{platform}'. Expected one of: {supported}") from error


"""
Return repository license and notice files that must travel with FFI binaries.
返回应随 FFI 二进制一起分发的仓库许可证与声明文件。
"""
def collect_license_files(root: Path) -> list[Path]:
    # Define the exact compliance payload required in every native release archive.
    # 定义每个原生发布归档必须包含的精确合规载荷。
    license_names = [
        "LICENSE",
        "THIRD_PARTY_NOTICES.md",
        "THIRD_PARTY_LICENSES.md",
    ]
    # Resolve all paths before validating the set as one atomic package contract.
    # 在把文件集作为一个原子打包契约校验前解析全部路径。
    license_paths = [root / name for name in license_names]
    # Identify missing compliance files explicitly instead of silently omitting them.
    # 显式识别缺失的合规文件，禁止静默省略。
    missing_names = [path.name for path in license_paths if not path.is_file()]
    if missing_names:
        raise RuntimeError(f"Missing required FFI license files: {', '.join(missing_names)}")
    return license_paths


"""
Build one platform-specific FFI zip and checksum file.
构建一个平台专属 FFI zip 与校验文件。
"""
def build_ffi_package(root: Path, out_dir: Path, platform: str, library_path: Path) -> tuple[Path, Path]:
    # Resolve the exact platform contract before producing any release artifact.
    # 在生成任何发布产物前解析精确平台契约。
    required_library_name = expected_library_name(platform)
    if library_path.name != required_library_name:
        raise RuntimeError(
            f"FFI library for {platform} must be named {required_library_name}, got {library_path.name}"
        )
    out_dir.mkdir(parents=True, exist_ok=True)
    package_name = f"codekit-ffi-{platform}.zip"
    checksum_name = f"codekit-ffi-{platform}.sha256.txt"
    package_path = out_dir / package_name
    checksum_path = out_dir / checksum_name

    with ZipFile(package_path, "w", compression=ZIP_DEFLATED) as archive:
        archive.write(library_path, library_path.name)
        for notice_path in collect_license_files(root):
            archive.write(notice_path, f"licenses/{notice_path.name}")

    digest = hashlib.sha256(package_path.read_bytes()).hexdigest()
    checksum_path.write_text(f"{digest}  {package_name}\n", encoding="utf-8")
    return package_path, checksum_path


"""
Parse command-line arguments for the FFI package builder.
解析 FFI 打包脚本使用的命令行参数。
"""
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Package one unified CodeKit FFI release asset.")
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
    package_path, checksum_path = build_ffi_package(root, out_dir, args.platform, library_path)
    print(f"FFI package created: {package_path}")
    print(f"FFI checksum created: {checksum_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
