# 第三方 Rust 依赖许可证报告

本文件由 `python scripts/generate_cargo_deny_notices.py` 通过 `cargo deny list --format json --layout crate` 自动生成。

适用范围：`codekit-ffi` Rust 动态库构建时进入非 dev 依赖图的第三方 crates。

说明：

- 本报告不替代各上游项目的原始许可证文本。
- 发布 FFI 动态库时，应随包保留本报告、`THIRD_PARTY_NOTICES.md` 与仓库 `LICENSE`。
- 本报告排除了当前仓库自身的 workspace crate，仅列出第三方依赖。

## 许可证统计

| License | Crates |
| --- | ---: |
| `Apache-2.0` | 122 |
| `BSD-2-Clause` | 1 |
| `BSD-3-Clause` | 2 |
| `BSL-1.0` | 1 |
| `ISC` | 1 |
| `MIT` | 172 |
| `MPL-2.0` | 1 |
| `Unicode-3.0` | 1 |
| `Unlicense` | 9 |

## 依赖清单

| Crate | Version | Declared License | cargo-deny Licenses | Source | Repository |
| --- | --- | --- | --- | --- | --- |
| `aho-corasick` | 1.1.4 | `Unlicense OR MIT` | `MIT`, `Unlicense` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/BurntSushi/aho-corasick |
| `anstyle` | 1.0.14 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-cli/anstyle.git |
| `arbitrary` | 1.4.2 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-fuzz/arbitrary/ |
| `ast-grep-config` | 0.42.1 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/ast-grep/ast-grep |
| `ast-grep-core` | 0.42.1 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/ast-grep/ast-grep |
| `ast-grep-language` | 0.42.1 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/ast-grep/ast-grep |
| `autocfg` | 1.5.1 | `Apache-2.0 OR MIT` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/cuviper/autocfg |
| `bit-set` | 0.10.0 | `Apache-2.0 OR MIT` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/contain-rs/bit-set |
| `bit-vec` | 0.9.1 | `Apache-2.0 OR MIT` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/contain-rs/bit-vec |
| `bitflags` | 2.11.1 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/bitflags/bitflags |
| `bstr` | 1.12.1 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/BurntSushi/bstr |
| `cc` | 1.2.61 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-lang/cc-rs |
| `cfg-if` | 1.0.4 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-lang/cfg-if |
| `chrono` | 0.4.45 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/chronotope/chrono |
| `chrono-tz` | 0.9.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/chronotope/chrono-tz |
| `chrono-tz-build` | 0.3.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/chronotope/chrono-tz |
| `clap` | 4.6.7 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/clap-rs/clap |
| `clap-cargo` | 0.18.3 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/crate-ci/clap-cargo |
| `clap_builder` | 4.6.7 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/clap-rs/clap |
| `clap_derive` | 4.6.7 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/clap-rs/clap |
| `clap_lex` | 1.1.1 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/clap-rs/clap |
| `colored` | 2.2.0 | `MPL-2.0` | `MPL-2.0` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/mackwic/colored |
| `core-foundation-sys` | 0.8.7 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/servo/core-foundation-rs |
| `core_detect` | 1.0.0 | `MIT/Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/thomcc/core_detect |
| `crossbeam-channel` | 0.5.17 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/crossbeam-rs/crossbeam |
| `crossbeam-deque` | 0.8.6 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/crossbeam-rs/crossbeam |
| `crossbeam-epoch` | 0.9.18 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/crossbeam-rs/crossbeam |
| `crossbeam-utils` | 0.8.21 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/crossbeam-rs/crossbeam |
| `dashmap` | 6.2.1 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/xacrimon/dashmap |
| `derive_arbitrary` | 1.4.2 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-fuzz/arbitrary |
| `deunicode` | 1.6.2 | `BSD-3-Clause` | `BSD-3-Clause` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/kornelski/deunicode/ |
| `dyn-clone` | 1.0.20 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/dyn-clone |
| `either` | 1.18.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rayon-rs/either |
| `encoding_rs` | 0.8.41 | `(Apache-2.0 OR MIT) AND BSD-3-Clause` | `Apache-2.0`, `BSD-3-Clause`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/hsivonen/encoding_rs |
| `encoding_rs_io` | 0.1.8 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/BurntSushi/encoding_rs_io |
| `equivalent` | 1.0.2 | `Apache-2.0 OR MIT` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/indexmap-rs/equivalent |
| `etcetera` | 0.8.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/lunacookies/etcetera |
| `find-msvc-tools` | 0.1.9 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-lang/cc-rs |
| `getrandom` | 0.2.17 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-random/getrandom |
| `globset` | 0.4.18 | `Unlicense OR MIT` | `MIT`, `Unlicense` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/BurntSushi/ripgrep/tree/master/crates/globset |
| `globwalk` | 0.9.1 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/gilnaa/globwalk |
| `grep-matcher` | 0.1.9 | `Unlicense OR MIT` | `MIT`, `Unlicense` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/BurntSushi/ripgrep/tree/master/crates/matcher |
| `grep-searcher` | 0.1.17 | `Unlicense OR MIT` | `MIT`, `Unlicense` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/BurntSushi/ripgrep/tree/master/crates/searcher |
| `hashbrown` | 0.14.5 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-lang/hashbrown |
| `hashbrown` | 0.17.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-lang/hashbrown |
| `heck` | 0.5.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/withoutboats/heck |
| `home` | 0.5.12 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-lang/cargo |
| `humansize` | 2.1.3 | `MIT/Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/LeopoldArkham/humansize |
| `iana-time-zone` | 0.1.65 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/strawlab/iana-time-zone |
| `ignore` | 0.4.22 | `Unlicense OR MIT` | `MIT`, `Unlicense` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/BurntSushi/ripgrep/tree/master/crates/ignore |
| `indexmap` | 2.14.0 | `Apache-2.0 OR MIT` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/indexmap-rs/indexmap |
| `itertools` | 0.11.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-itertools/itertools |
| `itoa` | 1.0.18 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/itoa |
| `json5` | 0.4.1 | `ISC` | `ISC` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/callum-oakley/json5-rs |
| `lazy_static` | 1.5.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-lang-nursery/lazy-static.rs |
| `libc` | 0.2.186 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-lang/libc |
| `libm` | 0.2.16 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-lang/compiler-builtins |
| `lock_api` | 0.4.14 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/Amanieu/parking_lot |
| `log` | 0.4.29 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-lang/log |
| `memchr` | 2.8.0 | `Unlicense OR MIT` | `MIT`, `Unlicense` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/BurntSushi/memchr |
| `memmap2` | 0.9.11 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/RazrFalcon/memmap2-rs |
| `multiversion` | 0.9.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/calebzulawski/multiversion |
| `multiversion-macros` | 0.9.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/calebzulawski/multiversion |
| `multiversion_no_op` | 1.0.0 | `Apache-2.0 OR MIT` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/hsivonen/multiversion_no_op |
| `num-traits` | 0.2.19 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-num/num-traits |
| `once_cell` | 1.21.4 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/matklad/once_cell |
| `parking_lot` | 0.12.5 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/Amanieu/parking_lot |
| `parking_lot_core` | 0.9.12 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/Amanieu/parking_lot |
| `parse-zoneinfo` | 0.3.1 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/chronotope/chrono-tz |
| `percent-encoding` | 2.3.2 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/servo/rust-url/ |
| `pest` | 2.9.1 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/pest-parser/pest |
| `pest_derive` | 2.9.1 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/pest-parser/pest |
| `pest_generator` | 2.9.1 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/pest-parser/pest |
| `pest_meta` | 2.9.1 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/pest-parser/pest |
| `phf` | 0.11.3 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-phf/rust-phf |
| `phf_codegen` | 0.11.3 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-phf/rust-phf |
| `phf_generator` | 0.11.3 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-phf/rust-phf |
| `phf_shared` | 0.11.3 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-phf/rust-phf |
| `ppv-lite86` | 0.2.21 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/cryptocorrosion/cryptocorrosion |
| `proc-macro2` | 1.0.106 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/proc-macro2 |
| `quote` | 1.0.45 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/quote |
| `rand` | 0.8.8 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-random/rand |
| `rand_chacha` | 0.3.1 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-random/rand |
| `rand_core` | 0.6.4 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-random/rand |
| `rayon` | 1.12.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rayon-rs/rayon |
| `rayon-core` | 1.13.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rayon-rs/rayon |
| `ref-cast` | 1.0.25 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/ref-cast |
| `ref-cast-impl` | 1.0.25 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/ref-cast |
| `regex` | 1.12.3 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-lang/regex |
| `regex-automata` | 0.4.14 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-lang/regex |
| `regex-syntax` | 0.8.10 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rust-lang/regex |
| `rustversion` | 1.0.23 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/rustversion |
| `ryu` | 1.0.23 | `Apache-2.0 OR BSL-1.0` | `Apache-2.0`, `BSL-1.0` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/ryu |
| `same-file` | 1.0.6 | `Unlicense/MIT` | `MIT`, `Unlicense` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/BurntSushi/same-file |
| `schemars` | 1.2.1 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/GREsau/schemars |
| `schemars_derive` | 1.2.1 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/GREsau/schemars |
| `scopeguard` | 1.2.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/bluss/scopeguard |
| `serde` | 1.0.228 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/serde-rs/serde |
| `serde_core` | 1.0.228 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/serde-rs/serde |
| `serde_derive` | 1.0.228 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/serde-rs/serde |
| `serde_derive_internals` | 0.29.1 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/serde-rs/serde |
| `serde_json` | 1.0.149 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/serde-rs/json |
| `serde_spanned` | 1.1.1 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/toml-rs/toml |
| `serde_yaml` | 0.9.34+deprecated | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/serde-yaml |
| `shlex` | 1.3.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/comex/rust-shlex |
| `simdutf8` | 0.1.5 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/rusticstuff/simdutf8 |
| `siphasher` | 1.0.3 | `MIT/Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/jedisct1/rust-siphash |
| `slug` | 0.1.6 | `MIT/Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/Stebalien/slug-rs |
| `smallvec` | 1.16.1 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/servo/rust-smallvec |
| `streaming-iterator` | 0.1.9 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/sfackler/streaming-iterator |
| `syn` | 2.0.117 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/syn |
| `syn` | 3.0.5 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/syn |
| `table_formatter` | 0.6.1 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/Embers-of-the-Fire/rust-table-formatter.git |
| `tera` | 1.20.1 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/Keats/tera |
| `term_size` | 0.3.2 | `MIT/Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/kbknapp/term_size-rs.git |
| `thiserror` | 1.0.69 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/thiserror |
| `thiserror` | 2.0.18 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/thiserror |
| `thiserror-impl` | 1.0.69 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/thiserror |
| `thiserror-impl` | 2.0.18 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/thiserror |
| `tokei` | 15.0.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/XAMPPRocky/tokei.git |
| `toml` | 0.9.12+spec-1.1.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/toml-rs/toml |
| `toml_datetime` | 0.7.5+spec-1.1.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/toml-rs/toml |
| `toml_parser` | 1.1.3+spec-1.1.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/toml-rs/toml |
| `toml_writer` | 1.1.2+spec-1.1.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/toml-rs/toml |
| `tree-sitter` | 0.26.8 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter |
| `tree-sitter-bash` | 0.25.1 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-bash |
| `tree-sitter-c` | 0.24.2 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-c |
| `tree-sitter-c-sharp` | 0.23.5 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-c-sharp |
| `tree-sitter-cpp` | 0.23.4 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-cpp |
| `tree-sitter-css` | 0.25.0 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-css |
| `tree-sitter-dart` | 0.1.0 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/nielsenko/tree-sitter-dart |
| `tree-sitter-elixir` | 0.3.5 | `Apache-2.0` | `Apache-2.0` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/elixir-lang/tree-sitter-elixir |
| `tree-sitter-go` | 0.25.0 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-go |
| `tree-sitter-haskell` | 0.23.1 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-haskell |
| `tree-sitter-hcl` | 1.1.0 | `Apache-2.0` | `Apache-2.0` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter-grammars/tree-sitter-hcl |
| `tree-sitter-html` | 0.23.2 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-html |
| `tree-sitter-java` | 0.23.5 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-java |
| `tree-sitter-javascript` | 0.25.0 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-javascript |
| `tree-sitter-json` | 0.23.0 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-json |
| `tree-sitter-kotlin-sg` | 0.4.0 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/fwcd/tree-sitter-kotlin |
| `tree-sitter-language` | 0.1.7 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter |
| `tree-sitter-lua` | 0.5.0 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter-grammars/tree-sitter-lua |
| `tree-sitter-nix` | 0.3.0 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/nix-community/tree-sitter-nix |
| `tree-sitter-php` | 0.24.2 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-php |
| `tree-sitter-python` | 0.25.0 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-python |
| `tree-sitter-ruby` | 0.23.1 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-ruby |
| `tree-sitter-rust` | 0.24.2 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-rust |
| `tree-sitter-scala` | 0.25.1 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-scala |
| `tree-sitter-solidity` | 1.2.13 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/JoranHonig/tree-sitter-solidity |
| `tree-sitter-swift` | 0.7.1 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/alex-pinkus/tree-sitter-swift |
| `tree-sitter-typescript` | 0.23.2 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter/tree-sitter-typescript |
| `tree-sitter-yaml` | 0.7.2 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/tree-sitter-grammars/tree-sitter-yaml |
| `ucd-trie` | 0.1.7 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/BurntSushi/ucd-generate |
| `unicode-ident` | 1.0.24 | `(MIT OR Apache-2.0) AND Unicode-3.0` | `Apache-2.0`, `MIT`, `Unicode-3.0` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/unicode-ident |
| `unicode-segmentation` | 1.13.3 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/unicode-rs/unicode-segmentation |
| `unsafe-libyaml` | 0.2.11 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/unsafe-libyaml |
| `walkdir` | 2.5.0 | `Unlicense/MIT` | `MIT`, `Unlicense` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/BurntSushi/walkdir |
| `winapi` | 0.3.9 | `MIT/Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/retep998/winapi-rs |
| `winapi-util` | 0.1.11 | `Unlicense OR MIT` | `MIT`, `Unlicense` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/BurntSushi/winapi-util |
| `windows-core` | 0.62.2 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/microsoft/windows-rs |
| `windows-implement` | 0.60.2 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/microsoft/windows-rs |
| `windows-interface` | 0.59.3 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/microsoft/windows-rs |
| `windows-link` | 0.2.1 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/microsoft/windows-rs |
| `windows-result` | 0.4.1 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/microsoft/windows-rs |
| `windows-strings` | 0.5.1 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/microsoft/windows-rs |
| `windows-sys` | 0.48.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/microsoft/windows-rs |
| `windows-sys` | 0.59.0 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/microsoft/windows-rs |
| `windows-sys` | 0.61.2 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/microsoft/windows-rs |
| `windows-targets` | 0.48.5 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/microsoft/windows-rs |
| `windows-targets` | 0.52.6 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/microsoft/windows-rs |
| `windows_x86_64_gnu` | 0.48.5 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/microsoft/windows-rs |
| `windows_x86_64_gnu` | 0.52.6 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/microsoft/windows-rs |
| `windows_x86_64_msvc` | 0.48.5 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/microsoft/windows-rs |
| `windows_x86_64_msvc` | 0.52.6 | `MIT OR Apache-2.0` | `Apache-2.0`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/microsoft/windows-rs |
| `winnow` | 0.7.15 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/winnow-rs/winnow |
| `winnow` | 1.0.4 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/winnow-rs/winnow |
| `zerocopy` | 0.8.57 | `BSD-2-Clause OR Apache-2.0 OR MIT` | `Apache-2.0`, `BSD-2-Clause`, `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/google/zerocopy |
| `zmij` | 1.0.21 | `MIT` | `MIT` | registry+https://github.com/rust-lang/crates.io-index | https://github.com/dtolnay/zmij |
