"""Verify Windows DLL workers finish before unload in an isolated process.
在隔离进程中验证 Windows DLL 的工作线程在卸载前全部退出。
"""

import argparse
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


class ThreadEntry(ctypes.Structure):
    """Represent the Windows THREADENTRY32 snapshot record without owned resources.
    表示不持有资源的 Windows THREADENTRY32 快照记录。
    """

    # Preserve the documented Win32 field widths and order.
    # 保留 Win32 文档定义的字段宽度与顺序。
    _fields_ = [
        ("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD),
        ("th32ThreadID", wintypes.DWORD), ("th32OwnerProcessID", wintypes.DWORD),
        ("tpBasePri", wintypes.LONG), ("tpDeltaPri", wintypes.LONG),
        ("dwFlags", wintypes.DWORD),
    ]


def windows_api():
    """Return kernel32 with typed handles so 64-bit addresses are never truncated.
    返回已声明句柄类型的 kernel32，防止截断 64 位地址；无参数。
    """
    # Configure only the APIs used by this lifecycle check.
    # 仅配置本生命周期验证使用的 API。
    api = ctypes.WinDLL("kernel32", use_last_error=True)
    api.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
    api.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    api.Thread32First.argtypes = [wintypes.HANDLE, ctypes.POINTER(ThreadEntry)]
    api.Thread32First.restype = wintypes.BOOL
    api.Thread32Next.argtypes = api.Thread32First.argtypes
    api.Thread32Next.restype = wintypes.BOOL
    api.CloseHandle.argtypes = [wintypes.HANDLE]
    api.CloseHandle.restype = wintypes.BOOL
    api.FreeLibrary.argtypes = [wintypes.HMODULE]
    api.FreeLibrary.restype = wintypes.BOOL
    api.GetModuleHandleW.argtypes = [wintypes.LPCWSTR]
    api.GetModuleHandleW.restype = wintypes.HMODULE
    return api


def process_threads(api):
    """Return current process thread IDs using typed kernel32 APIs; raise on snapshot failure.
    使用已声明类型的 kernel32 API 返回当前进程线程 ID 集合，快照失败时抛出异常。
    """
    # TH32CS_SNAPTHREAD captures system threads, filtered below by owner process.
    # TH32CS_SNAPTHREAD 捕获系统线程，随后按所属进程过滤。
    snapshot = api.CreateToolhelp32Snapshot(0x00000004, 0)
    if snapshot == ctypes.c_void_p(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        # Keep the documented record size valid for every enumeration step.
        # 每次枚举前保持记录大小符合接口约定。
        entry = ThreadEntry()
        entry.dwSize = ctypes.sizeof(entry)
        active = api.Thread32First(snapshot, ctypes.byref(entry))
        threads = set()
        while active:
            if entry.th32OwnerProcessID == os.getpid():
                threads.add(entry.th32ThreadID)
            entry.dwSize = ctypes.sizeof(entry)
            active = api.Thread32Next(snapshot, ctypes.byref(entry))
        if ctypes.get_last_error() != 18:  # ERROR_NO_MORE_FILES / 枚举已结束。
            raise ctypes.WinError(ctypes.get_last_error())
        return threads
    finally:
        api.CloseHandle(snapshot)


def check_cycles(library_path):
    """Load, scan and unload the specified DLL three times; return only after all checks pass.
    对指定 DLL 执行三次加载、扫描和卸载，仅在全部检查通过后返回。
    """
    # Record the baseline before any native code can create persistent workers.
    # 在原生代码有机会创建常驻线程之前记录基线。
    api = windows_api()
    baseline = process_threads(api)
    with tempfile.TemporaryDirectory(prefix="codekit-unload-") as folder:
        # A real Rust fixture forces Tokei's nested Rayon parse and aggregate paths.
        # 真实 Rust 夹具触发 Tokei 嵌套的 Rayon 解析与汇总路径。
        root = Path(folder)
        (root / "fixture.rs").write_text("fn fixture() {}\n" * 1000, encoding="utf-8")
        for cycle in range(3):
            # Bind the public owned-string ABI on each new library generation.
            # 对每一代重新加载的库绑定公开的自有字符串接口。
            library = ctypes.CDLL(str(library_path))
            scan = library.vulcan_codekit_repo_stats_json
            scan.argtypes = [ctypes.c_char_p]
            scan.restype = ctypes.c_void_p
            release = library.vulcan_codekit_free_string
            release.argtypes = [ctypes.c_void_p]
            release.restype = None
            for _ in range(2):
                # Validate content as well as lifetime, freeing responses before unloading.
                # 同时验证内容与生命周期，在卸载前释放响应。
                response = scan(json.dumps({"root": str(root)}).encode("utf-8"))
                assert response, "FFI returned a null response"
                try:
                    result = json.loads(ctypes.string_at(response))
                    assert result["ok"], result
                    assert result["totals"]["recognizedFiles"] == 1, result
                    assert result["totals"]["code"] == 1000, result
                finally:
                    release(response)
                # Check before unload: never intentionally unmap live worker instructions.
                # 卸载前检查，避免主动解除仍有工作线程执行的代码映射。
                remaining = process_threads(api) - baseline
                assert not remaining, f"FFI returned with {len(remaining)} live worker threads: {sorted(remaining)}"
            if not api.FreeLibrary(library._handle):
                raise ctypes.WinError(ctypes.get_last_error())
            assert not api.GetModuleHandleW(str(library_path)), "DLL remained loaded; unload was not tested"
            assert process_threads(api) == baseline, "Thread baseline changed after DLL unload"
            del scan, release, library
            print(f"cycle {cycle + 1}: scanned twice, no workers remain, DLL unloaded", flush=True)


def main():
    """Run the Windows regression in a child process with a timeout; return its exit code.
    在有超时限制的子进程中运行 Windows 回归验证并返回其退出码；参数来自命令行。
    """
    # Use a separate process because a native access violation bypasses Python exceptions.
    # 原生访问异常会绕过 Python 异常处理，因此使用独立进程。
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library-path", required=True, type=Path)
    parser.add_argument("--child", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if sys.platform != "win32":
        parser.error("This regression requires Windows loader and thread APIs")
    if args.child:
        check_cycles(args.library_path.resolve(strict=True))
        return 0
    return subprocess.run(
        [sys.executable, str(Path(__file__).resolve()), "--library-path",
         str(args.library_path.resolve(strict=True)), "--child"],
        timeout=60, check=False,
    ).returncode


if __name__ == "__main__":
    raise SystemExit(main())
