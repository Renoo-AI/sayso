$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$jdk = (Get-ChildItem "$root/.build-tools/jdk" -Directory | Select-Object -First 1).FullName
$buildTools = (Get-ChildItem "$root/.build-tools/build-tools" -Directory | Select-Object -First 1).FullName
$platform = Join-Path $root '.build-tools/platform/android-35/android.jar'
if (!$jdk -or !$buildTools -or !(Test-Path $platform)) { throw 'Missing JDK or Android build tools. See android/README.md.' }
$env:JAVA_HOME = $jdk
$env:PATH = "$jdk/bin;" + $env:PATH
$build = Join-Path $root 'android/build'
$signing = Join-Path $root 'android/signing'
New-Item -ItemType Directory -Force "$build/gen", "$build/classes", "$build/dex", $signing | Out-Null
function Invoke-Checked([string]$exe, [string[]]$arguments) {
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $exe (exit $LASTEXITCODE)" }
}
if (Get-Command node -ErrorAction SilentlyContinue) { Invoke-Checked 'node' @('scripts/prepare-android.mjs') }
else { & "$PSScriptRoot/prepare-android.ps1" }
Invoke-Checked "$buildTools/aapt2.exe" @('compile','--dir',"$root/android/res",'-o',"$build/resources.zip")
Invoke-Checked "$buildTools/aapt2.exe" @('link','-I',$platform,'--manifest',"$root/android/AndroidManifest.xml",'-R',"$build/resources.zip",'-A',"$root/android/assets",'--java',"$build/gen",'-o',"$build/resources.apk",'--auto-add-overlay')
$sources = @(Get-ChildItem "$root/android/src", "$build/gen" -Filter '*.java' -Recurse | ForEach-Object FullName)
Invoke-Checked "$jdk/bin/javac.exe" (@('-encoding','UTF-8','-source','8','-target','8','-classpath',$platform,'-d',"$build/classes") + $sources)
Invoke-Checked "$jdk/bin/jar.exe" @('cf',"$build/classes.jar",'-C',"$build/classes",'.')
Invoke-Checked "$jdk/bin/java.exe" @('-cp',"$buildTools/lib/d8.jar",'com.android.tools.r8.D8','--release','--min-api','26','--lib',$platform,'--output',"$build/dex","$build/classes.jar")
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
Copy-Item -LiteralPath "$build/resources.apk" -Destination "$build/unsigned.apk" -Force
$zip = [System.IO.Compression.ZipFile]::Open("$build/unsigned.apk",[System.IO.Compression.ZipArchiveMode]::Update)
try {
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,"$build/dex/classes.dex",'classes.dex') | Out-Null
    # aapt2 on Windows stores nested assets as "assets/lib\x.js"; Android only finds "assets/lib/x.js".
    foreach ($entry in @($zip.Entries | Where-Object { $_.FullName.Contains('\') })) {
        $data = New-Object System.IO.MemoryStream
        $in = $entry.Open(); $in.CopyTo($data); $in.Dispose()
        $name = $entry.FullName.Replace('\','/'); $entry.Delete()
        $out = $zip.CreateEntry($name).Open(); $data.Position = 0; $data.CopyTo($out); $out.Dispose()
    }
} finally { $zip.Dispose() }
Invoke-Checked "$buildTools/zipalign.exe" @('-f','-p','4',"$build/unsigned.apk","$build/aligned.apk")
if (!(Test-Path "$signing/release.jks")) {
    if (!(Test-Path "$signing/password.txt")) { [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(36)) | Set-Content "$signing/password.txt" }
    $env:MEMORY_SIGN_PASSWORD = (Get-Content "$signing/password.txt" -Raw).Trim()
    Invoke-Checked "$jdk/bin/keytool.exe" @('-genkeypair','-keystore',"$signing/release.jks",'-alias','memory-release','-keyalg','RSA','-keysize','3072','-validity','10000','-storepass:env','MEMORY_SIGN_PASSWORD','-keypass:env','MEMORY_SIGN_PASSWORD','-dname','CN=My Memory, OU=Android, O=My Memory','-noprompt')
}
$env:MEMORY_SIGN_PASSWORD = (Get-Content "$signing/password.txt" -Raw).Trim()
try {
    Invoke-Checked "$jdk/bin/java.exe" @('-jar',"$buildTools/lib/apksigner.jar",'sign','--ks',"$signing/release.jks",'--ks-key-alias','memory-release','--ks-pass','env:MEMORY_SIGN_PASSWORD','--key-pass','env:MEMORY_SIGN_PASSWORD','--out',"$build/my-memory.apk","$build/aligned.apk")
} finally { Remove-Item Env:MEMORY_SIGN_PASSWORD -ErrorAction SilentlyContinue }
Invoke-Checked "$jdk/bin/java.exe" @('-jar',"$buildTools/lib/apksigner.jar",'verify','--verbose',"$build/my-memory.apk")
Invoke-Checked "$buildTools/zipalign.exe" @('-c','4',"$build/my-memory.apk")
$apk = Get-Item "$build/my-memory.apk"
Write-Output "Signed APK ready: $($apk.FullName) ($($apk.Length) bytes)"
