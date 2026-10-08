<#
.SYNOPSIS
Create and push an annotated Git tag for the Vulcan CodeKit LuaSkill release.
创建并推送用于 Vulcan CodeKit LuaSkill 发布的带注释 Git 标签。
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

# Resolve the repository root so the script is independent of the caller's working directory.
# 解析仓库根目录，使脚本不依赖调用方工作目录。
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# Normalize the requested version into the repository-standard tag name.
# 将请求版本规范化为仓库标准标签名称。
$tag = if ($Version.StartsWith("v")) { $Version } else { "v$Version" }

# Validate the complete contract and read the canonical version from one implementation.
# 通过同一实现校验完整契约并读取规范版本。
$manifestVersion = python (Join-Path $repositoryRoot "scripts/validate_skill.py") --release --print-version
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
$manifestVersion = ($manifestVersion | Select-Object -Last 1).Trim()
if ($tag -ne "v$manifestVersion") {
    Write-Error "Release tag $tag must match the validated repository version v$manifestVersion"
    exit 1
}

# Read every non-ignored working-tree change so untracked release files cannot be omitted.
# 读取全部非忽略工作树变更，避免未跟踪发布文件被遗漏。
$workingTreeChanges = git -C $repositoryRoot status --porcelain
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
if (-not [string]::IsNullOrWhiteSpace(($workingTreeChanges -join ""))) {
    Write-Error "Working tree changes must be committed before tagging"
    exit 1
}

# Reject an existing tag instead of moving published version identity.
# 拒绝已存在标签，禁止移动已经发布的版本身份。
git -C $repositoryRoot rev-parse --quiet --verify "refs/tags/$tag" *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Error "Tag already exists: $tag"
    exit 1
}

# Resolve the reviewed local and tracked remote commit identities.
# 解析已审核本地提交与跟踪远端提交身份。
$headCommitOutput = git -C $repositoryRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
$headCommit = ($headCommitOutput | Select-Object -Last 1).Trim()
$originMainCommitOutput = git -C $repositoryRoot rev-parse origin/main
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
$originMainCommit = ($originMainCommitOutput | Select-Object -Last 1).Trim()
if ($headCommit -ne $originMainCommit) {
    Write-Error "HEAD must match origin/main before creating a release tag"
    exit 1
}

# Require the unpublished RG baseline to remain an ancestor of the joint release.
# 要求未单独发布的 RG 基线仍是联合版本的祖先提交。
git -C $repositoryRoot merge-base --is-ancestor 9227ab2ce5efb2381b4df26a347b897d7ee171fe HEAD
if ($LASTEXITCODE -ne 0) {
    Write-Error "Joint release must contain RG baseline commit 9227ab2"
    exit 1
}

Write-Host "Creating annotated tag: $tag"
git -C $repositoryRoot tag -a $tag -m "发布 ${tag}：统一 CodeKit FFI 与 Repo Map 联合版本"
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Pushing tag to origin: $tag"
git -C $repositoryRoot push origin $tag
exit $LASTEXITCODE
