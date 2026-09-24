import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'../download-site/dist');
const files={'/':'index.html','/index.html':'index.html','/release.json':'release.json','/my-memory.apk':'my-memory.apk'};
http.createServer((req,res)=>{const name=files[new URL(req.url,'http://localhost').pathname];if(!name){res.writeHead(404);res.end();return;}const file=path.join(root,name);if(!fs.existsSync(file)){res.writeHead(404);res.end();return;}res.setHeader('Content-Type',name.endsWith('.html')?'text/html; charset=utf-8':name.endsWith('.json')?'application/json':'application/vnd.android.package-archive');if(name.endsWith('.apk'))res.setHeader('Content-Disposition','attachment; filename="my-memory.apk"');res.setHeader('Content-Length',fs.statSync(file).size);if(req.method==='HEAD')return res.end();fs.createReadStream(file).pipe(res);}).listen(8788,'127.0.0.1',()=>console.log('http://127.0.0.1:8788'));
