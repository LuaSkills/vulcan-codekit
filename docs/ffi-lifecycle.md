# 原生库卸载契约

## 原因与修复

Windows 崩溃转储确认技能更新期间发生了对已卸载 `vulcan_codekit_ffi.dll` 的执行访问。
旧版调用 Tokei 后初始化 Rayon 全局线程池；FFI 请求完成不代表这些工作线程已经退出。
Lua VM 释放 `ffi.load` 引用时，仍然存在的线程可能继续执行已经取消映射的 DLL 代码。

从 0.2.3 起，仓库统计使用 `ThreadPoolBuilder::build_scoped`，并在池内执行整个
`Languages::get_statistics`。函数返回前等待全部工作线程退出，包括线程局部存储析构。
不得用全局线程池替代，也不得仅调用普通线程池的 `drop` 而不等待线程退出。
每次扫描的 Rayon 并发上限唯一声明在 `MAX_SCAN_WORKERS`。

宿主仍必须排空正在执行的 FFI 调用并释放返回字符串，才能销毁 Lua VM 或卸载动态库。
本修复不允许其他线程在调用未返回时强行卸载库。

## 回归入口

```powershell
cargo test --manifest-path codekit-ffi/Cargo.toml --locked -j 4 -- --test-threads=4
cargo build --manifest-path codekit-ffi/Cargo.toml --release --locked -j 4
python scripts/check_ffi_unload.py --library-path codekit-ffi/target/release/vulcan_codekit_ffi.dll
```

Windows 回归运行在有超时保护的独立子进程中。每轮加载 DLL、执行两次真实统计、检查线程
恢复到基线、释放 DLL，并确认模块已经卸载；连续运行三轮以验证重新加载。
旧版 0.2.1 在第一次扫描后残留 32 条线程，测试在卸载前明确失败，避免主动执行危险卸载。
该检查同时接入拉取请求验证与 Windows 发布产物验证。

## 升级边界

技能清单、依赖清单、Lua 加载器与原生 crate 统一升级到 0.2.3，避免以旧版本标识覆盖缓存。
已加载旧 DLL 的服务应先退出，再安装正式修复版；运行中直接更新旧库仍会经过旧线程生命周期。
仅重新编译 Vulcan Code 宿主不会替换独立发布的 CodeKit 原生依赖。
