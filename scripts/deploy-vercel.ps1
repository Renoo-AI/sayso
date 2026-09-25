# Deploys the website (/) and the app (/app/) to Vercel through its REST API.
# No Node.js, Git, or Vercel CLI needed. Create a token at https://vercel.com/account/tokens
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$token = $env:VERCEL_TOKEN
if (-not $token) {
  $secure = Read-Host 'Paste your Vercel token (hidden)' -AsSecureString
  $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}
if (-not $token) { throw 'No token given.' }
$headers = @{ Authorization = "Bearer $token" }

$paths = @('index.html', 'vercel.json', 'package.json', 'downloads/sayso.apk') +
  (Get-ChildItem app, api, lib -Recurse -File | ForEach-Object { $_.FullName.Substring($root.Length + 1) })
$files = foreach ($p in $paths) {
  @{ file = $p.Replace('\', '/'); data = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root $p))); encoding = 'base64' }
}
Write-Host "Uploading $($files.Count) files..."

$body = @{
  name = 'sayso'
  target = 'production'
  files = @($files)
  projectSettings = @{ framework = $null; buildCommand = $null; installCommand = $null; outputDirectory = $null }
} | ConvertTo-Json -Depth 6

$deploy = Invoke-RestMethod -Method Post -Uri 'https://api.vercel.com/v13/deployments?skipAutoDetectionConfirmation=1' `
  -Headers $headers -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body))
Write-Host "Building https://$($deploy.url)"

do {
  Start-Sleep -Seconds 3
  $state = Invoke-RestMethod -Uri "https://api.vercel.com/v13/deployments/$($deploy.id)" -Headers $headers
  Write-Host "  $($state.readyState)"
} while ($state.readyState -in 'QUEUED', 'INITIALIZING', 'BUILDING')

if ($state.readyState -ne 'READY') { throw "Deployment ended as $($state.readyState). Details: https://vercel.com/dashboard" }
$domain = @($state.alias) | Where-Object { $_ } | Select-Object -First 1
if (-not $domain) { $domain = $deploy.url }
Write-Host ''
Write-Host "Website: https://$domain/"
Write-Host "App:     https://$domain/app/"
