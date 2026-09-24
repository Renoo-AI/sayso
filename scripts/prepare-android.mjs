import fs from 'node:fs';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
const assets = path.join(root, 'android/assets');
fs.mkdirSync(assets, {recursive: true});
let html = fs.readFileSync(path.join(root, 'app/index.html'), 'utf8');
function replace(before, after) {
  if (!html.includes(before)) throw new Error('Android integration anchor missing: '+before.slice(0,80));
  html = html.replace(before, after);
}
replace('<script>', '<script src="native-bridge.js"></script>\n<script>');
replace("const dsToken=localStorage.getItem('sm_ds_token')||'';", "const dsToken=localStorage.getItem('sm_ds_token')||'';\n  if(window.MemoryAndroid&&dsToken)return window.memoryChat(dsToken,messages);");
replace('async function requestMicPermission(showToast=true){', `async function requestMicPermission(showToast=true){
  if(window.MemoryAndroid){if(!MemoryAndroid.microphoneAllowed())MemoryAndroid.requestMicrophone();else if(showToast)toast('الميكروفون مفعّل');return MemoryAndroid.microphoneAllowed();}`);
replace('function syncTasksToSW(){', `function syncTasksToSW(){
  if(window.MemoryAndroid){MemoryAndroid.syncReminders(JSON.stringify(localStorage.getItem('sm_notif')==='off'?[]:tasks.filter(t=>!t.completed&&t.reminderDate).map(t=>({id:t.id,title:t.title,subject:t.subject,dueAt:localStamp(t.reminderDate,t.reminderTime),notified:!!t.notified}))));return;}`);
replace("const canUseSW = () => 'serviceWorker' in navigator", "const canUseSW = () => !window.MemoryAndroid && 'serviceWorker' in navigator");
replace('function checkReminders(){', 'function checkReminders(){\n  if(window.MemoryAndroid)return;');
replace('function scheduleIfSoon(t){', 'function scheduleIfSoon(t){\n  if(window.MemoryAndroid)return;');
replace('function notifState(){', "function notifState(){\n  if(window.MemoryAndroid)return localStorage.getItem('sm_notif')==='off'?'off':MemoryAndroid.notificationsAllowed()?'on':'ask';");
replace("$('notifSub2').textContent=NOTIF_COPY[s];", "$('notifSub2').textContent=window.MemoryAndroid?(s==='on'?'التذكيرات مفعّلة. قد تؤخرها إعدادات البطارية في الهاتف.':'فعّل الإشعارات لتلقي تذكيرات المهام.'):NOTIF_COPY[s];");
replace('async function enableNotifications(){', `async function enableNotifications(){
  if(window.MemoryAndroid){if(notifState()==='on')localStorage.setItem('sm_notif','off');else{localStorage.setItem('sm_notif','on');MemoryAndroid.requestNotifications();}syncTasksToSW();paintNotifRow();return;}`);
replace('async function pullNotified(){', 'async function pullNotified(){\n  if(window.MemoryAndroid)return JSON.parse(MemoryAndroid.firedIds());');
replace('/* ============ INIT ============ */', `window.memoryOpenTask=id=>{if(byId(id)){closeSheets();switchTab('homework');viewMode='all';activeFolderId=null;flashId=id;renderHomework();openEditSheet(id);}};
window.memoryResume=async()=>{paintNotifRow();const seen=await pullNotified();let changed=false;tasks.forEach(t=>{if(seen.includes(t.id)&&!t.notified){t.notified=true;changed=true;}});if(changed)saveTasks();};
/* ============ INIT ============ */`);
// Avoid falsely claiming that all reminders are "recently added"; retain the original UI otherwise.
replace('maximum-scale=1.0, user-scalable=no', 'viewport-fit=cover');
fs.writeFileSync(path.join(assets, 'index.html'), html);
for (const file of ['icon.svg','manifest.json']) fs.copyFileSync(path.join(root,'app',file),path.join(assets,file));
fs.copyFileSync(path.join(root,'android/native-bridge.js'),path.join(assets,'native-bridge.js'));
fs.cpSync(path.join(root,'lib'),path.join(assets,'lib'),{recursive:true});
console.log('Android assets prepared.');

