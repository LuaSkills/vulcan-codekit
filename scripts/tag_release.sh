#!/usr/bin/env bash
#
# Create and push an annotated Git tag for the Vulcan CodeKit LuaSkill release.
# 创建并推送用于 Vulcan CodeKit LuaSkill 发布的带注释 Git 标签。

set -euo pipefail

# Resolve and enter the repository root so the script is independent of the caller's working directory.
# 解析并进入仓库根目录，使脚本不依赖调用方工作目录。
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
cd "$repository_root"

if [ $# -ne 1 ]; then
  echo "Usage: ./scripts/tag_release.sh <version>"
  echo "用法：./scripts/tag_release.sh <版本号>"
  exit 1
fi

# Read the exact requested release version.
# 读取精确的请求发布版本。
version="$1"
if [[ "$version" == v* ]]; then
  # Reuse an explicitly prefixed semantic-version tag.
  # 复用显式带前缀的语义化版本标签。
  tag="$version"
else
  # Add the repository-standard version prefix.
  # 添加仓库标准版本前缀。
  tag="v$version"
fi

# Validate the complete contract and read the canonical version from one implementation.
# 通过同一实现校验完整契约并读取规范版本。
manifest_version="$(python scripts/validate_skill.py --print-version)"
if [[ "$tag" != "v$manifest_version" ]]; then
  echo "Release tag $tag must match the validated repository version v$manifest_version"
  exit 1
fi

# Reject every non-ignored change so untracked release files cannot be omitted.
# 拒绝全部非忽略变更，避免未跟踪发布文件被遗漏。
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree changes must be committed before tagging"
  exit 1
fi

# Reject an existing tag instead of moving published version identity.
# 拒绝已存在标签，禁止移动已经发布的版本身份。
if git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null; then
  echo "Tag already exists: $tag"
  exit 1
fi

# Require the reviewed commit to be present on the tracked remote main branch.
# 要求已审核提交已经存在于跟踪的远端 main 分支。
head_commit="$(git rev-parse HEAD)"
origin_main_commit="$(git rev-parse origin/main)"
if [[ "$head_commit" != "$origin_main_commit" ]]; then
  echo "HEAD must match origin/main before creating a release tag"
  exit 1
fi

# Require the unpublished RG baseline to remain an ancestor of the joint release.
# 要求未单独发布的 RG 基线仍是联合版本的祖先提交。
if ! git merge-base --is-ancestor 9227ab2ce5efb2381b4df26a347b897d7ee171fe HEAD; then
  echo "Joint release must contain RG baseline commit 9227ab2"
  exit 1
fi

echo "Creating annotated tag: $tag"
git tag -a "$tag" -m "发布 $tag：统一 CodeKit FFI 与 Repo Map 联合版本"

echo "Pushing tag to origin: $tag"
git push origin "$tag"
