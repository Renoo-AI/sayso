# PowerShell port of prepare-android.mjs, used when Node.js is not installed.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$assets = Join-Path $root 'android/assets'
New-Item -ItemType Directory -Force $assets | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:html = [IO.File]::ReadAllText((Join-Path $root 'app/index.html'), $utf8)

function Replace-First([string]$before, [string]$after) {
  $i = $script:html.IndexOf($before, [StringComparison]::Ordinal)
  if ($i -lt 0) { throw "Android integration anchor missing: $($before.Substring(0, [Math]::Min(80, $before.Length)))" }
  $script:html = $script:html.Substring(0, $i) + $after + $script:html.Substring($i + $before.Length)
}

Replace-First '<script>' "<script src=`"native-bridge.js`"></script>`n<script>"
Replace-First "const dsToken=localStorage.getItem('sm_ds_token')||'';" @'
const dsToken=localStorage.getItem('sm_ds_token')||'';
  if(window.MemoryAndroid&&dsToken)return window.memoryChat(dsToken,messages);
'@.TrimEnd()
Replace-First 'async function requestMicPermission(showToast=true){' @'
async function requestMicPermission(showToast=true){
  if(window.MemoryAndroid){if(!MemoryAndroid.microphoneAllowed())MemoryAndroid.requestMicrophone();else if(showToast)toast('الميكروفون مفعّل');return MemoryAndroid.microphoneAllowed();}
'@.TrimEnd()
Replace-First 'function syncTasksToSW(){' @'
function syncTasksToSW(){
  if(window.MemoryAndroid){MemoryAndroid.syncReminders(JSON.stringify(localStorage.getItem('sm_notif')==='off'?[]:tasks.filter(t=>!t.completed&&t.reminderDate).map(t=>({id:t.id,title:t.title,subject:t.subject,dueAt:localStamp(t.reminderDate,t.reminderTime),notified:!!t.notified}))));return;}
'@.TrimEnd()
Replace-First "const canUseSW = () => 'serviceWorker' in navigator" "const canUseSW = () => !window.MemoryAndroid && 'serviceWorker' in navigator"
Replace-First 'function checkReminders(){' "function checkReminders(){`n  if(window.MemoryAndroid)return;"
Replace-First 'function scheduleIfSoon(t){' "function scheduleIfSoon(t){`n  if(window.MemoryAndroid)return;"
Replace-First 'function notifState(){' @'
function notifState(){
  if(window.MemoryAndroid)return localStorage.getItem('sm_notif')==='off'?'off':MemoryAndroid.notificationsAllowed()?'on':'ask';
'@.TrimEnd()
Replace-First "`$('notifSub2').textContent=NOTIF_COPY[s];" @'
$('notifSub2').textContent=window.MemoryAndroid?(s==='on'?'التذكيرات مفعّلة. قد تؤخرها إعدادات البطارية في الهاتف.':'فعّل الإشعارات لتلقي تذكيرات المهام.'):NOTIF_COPY[s];
'@.TrimEnd()
Replace-First 'async function enableNotifications(){' @'
async function enableNotifications(){
  if(window.MemoryAndroid){if(notifState()==='on')localStorage.setItem('sm_notif','off');else{localStorage.setItem('sm_notif','on');MemoryAndroid.requestNotifications();}syncTasksToSW();paintNotifRow();return;}
'@.TrimEnd()
Replace-First 'async function pullNotified(){' "async function pullNotified(){`n  if(window.MemoryAndroid)return JSON.parse(MemoryAndroid.firedIds());"
Replace-First '/* ============ INIT ============ */' @'
window.memoryOpenTask=id=>{if(byId(id)){closeSheets();switchTab('homework');viewMode='all';activeFolderId=null;flashId=id;renderHomework();openEditSheet(id);}};
window.memoryResume=async()=>{paintNotifRow();const seen=await pullNotified();let changed=false;tasks.forEach(t=>{if(seen.includes(t.id)&&!t.notified){t.notified=true;changed=true;}});if(changed)saveTasks();};
/* ============ INIT ============ */
'@.TrimEnd()
Replace-First 'maximum-scale=1.0, user-scalable=no' 'viewport-fit=cover'

[IO.File]::WriteAllText((Join-Path $assets 'index.html'), $script:html, $utf8)
foreach ($f in 'icon.svg', 'manifest.json') { Copy-Item (Join-Path $root "app/$f") (Join-Path $assets $f) -Force }
Copy-Item (Join-Path $root 'android/native-bridge.js') (Join-Path $assets 'native-bridge.js') -Force
Copy-Item (Join-Path $root 'lib') $assets -Recurse -Force
Write-Output 'Android assets prepared.'
