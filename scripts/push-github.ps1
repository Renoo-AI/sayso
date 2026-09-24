# Pushes this folder to its GitHub repo as one commit, using the GitHub API (no Git install needed).
# Token: https://github.com/settings/personal-access-tokens/new  ->  this repo only, "Contents: Read and write".
param([string]$Message = 'Update SaySo', [switch]$DryRun)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$config = Get-Content (Join-Path $root '.git/config') -Raw
if ($config -notmatch 'url = https://github\.com/([^/\s]+/[^\s]+?)(\.git)?\s') { throw 'No GitHub origin found in .git/config.' }
$repo = $Matches[1]
$branch = 'main'

# Mirrors .gitignore plus local-only folders.
$ignoredDirs = @('.git', '.build-tools', 'android/build', 'android/assets', 'android/signing', 'download-site', '.claude', 'node_modules', '.vercel')
$ignoredExt = @('.zip', '.apk', '.jks', '.idsig')
function Test-Ignored([string]$rel) {
  foreach ($d in $ignoredDirs) { if ($rel -eq $d -or $rel.StartsWith("$d/")) { return $true } }
  if ($rel -match '(^|/)\.env(\.|$)' -and $rel -notmatch '\.env\.example$') { return $true }
  return $ignoredExt -contains [IO.Path]::GetExtension($rel).ToLower()
}
function Get-BlobSha([byte[]]$bytes) {
  $header = [Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
  $sha1 = [Security.Cryptography.SHA1]::Create()
  return -join ($sha1.ComputeHash([byte[]]($header + $bytes)) | ForEach-Object { $_.ToString('x2') })
}

$local = @{}
Get-ChildItem $root -Recurse -File -Force | ForEach-Object {
  $rel = $_.FullName.Substring($root.Length + 1).Replace('\', '/')
  if (-not (Test-Ignored $rel)) { $local[$rel] = $_.FullName }
}
if ($DryRun) { $local.Keys | Sort-Object; Write-Host "$($local.Count) files would be pushed to $repo ($branch)."; return }

$token = $env:GITHUB_TOKEN
if (-not $token) {
  $secure = Read-Host "GitHub token for $repo (hidden)" -AsSecureString
  $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}
if (-not $token) { throw 'No token given.' }
$api = "https://api.github.com/repos/$repo"
$headers = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28'; 'User-Agent' = 'sayso-push' }
function Invoke-Gh([string]$method, [string]$path, $body) {
  $req = @{ Method = $method; Uri = "$api$path"; Headers = $headers }
  if ($body) { $req.ContentType = 'application/json'; $req.Body = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 6 -Compress)) }
  Invoke-RestMethod @req
}

try { $ref = Invoke-Gh GET "/git/ref/heads/$branch" }
catch {
  # A brand-new repo has no commits, and the Git Data API rejects it until one exists.
  if ($_.Exception.Response.StatusCode.value__ -notin 404, 409) { throw }
  Write-Host "Empty repository: creating the first commit on $branch..."
  $readme = [IO.File]::ReadAllBytes((Join-Path $root 'README.md'))
  Invoke-Gh PUT '/contents/README.md' @{ message = 'Initial commit'; content = [Convert]::ToBase64String($readme); branch = $branch } | Out-Null
  $ref = Invoke-Gh GET "/git/ref/heads/$branch"
}
$parent = $ref.object.sha
$baseTree = (Invoke-Gh GET "/git/commits/$parent").tree.sha
$remote = @{}
(Invoke-Gh GET "/git/trees/$baseTree`?recursive=1").tree | Where-Object { $_.type -eq 'blob' } | ForEach-Object { $remote[$_.path] = $_.sha }

$entries = @()
foreach ($rel in ($local.Keys | Sort-Object)) {
  $bytes = [IO.File]::ReadAllBytes($local[$rel])
  if ($remote[$rel] -eq (Get-BlobSha $bytes)) { continue }
  Write-Host "  upload  $rel"
  $blob = Invoke-Gh POST '/git/blobs' @{ content = [Convert]::ToBase64String($bytes); encoding = 'base64' }
  $entries += @{ path = $rel; mode = '100644'; type = 'blob'; sha = $blob.sha }
}
foreach ($rel in $remote.Keys) {
  if (-not $local.ContainsKey($rel) -and -not (Test-Ignored $rel)) {
    Write-Host "  delete  $rel"
    $entries += @{ path = $rel; mode = '100644'; type = 'blob'; sha = $null }
  }
}
if (-not $entries.Count) { Write-Host 'Nothing to push; GitHub already matches this folder.'; return }

$tree = Invoke-Gh POST '/git/trees' @{ base_tree = $baseTree; tree = $entries }
$commit = Invoke-Gh POST '/git/commits' @{ message = $Message; tree = $tree.sha; parents = @($parent) }
Invoke-Gh PATCH "/git/refs/heads/$branch" @{ sha = $commit.sha; force = $false } | Out-Null
Write-Host ''
Write-Host "Pushed $($entries.Count) changes: https://github.com/$repo/commit/$($commit.sha)"
Write-Host 'Vercel will deploy it automatically in about a minute.'
