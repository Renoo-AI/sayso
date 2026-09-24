package com.mymemory.app;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.*;
import android.speech.*;
import android.webkit.*;
import org.json.*;
import java.io.*;
import java.net.*;
import javax.net.ssl.HttpsURLConnection;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

public class MainActivity extends Activity {
    private static final String ORIGIN = "https://memory.local";
    private WebView web;
    private SpeechRecognizer recognizer;
    private String pendingLanguage;
    private final ExecutorService network = Executors.newFixedThreadPool(2);
    private final Handler main = new Handler(Looper.getMainLooper());

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        ReminderReceiver.channel(this);
        web = new WebView(this);
        setContentView(web);
        applyBars((getResources().getConfiguration().uiMode & android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES);
        web.setOnApplyWindowInsetsListener((v, insets) -> {
            if (Build.VERSION.SDK_INT >= 30) {
                android.graphics.Insets b = insets.getInsets(android.view.WindowInsets.Type.systemBars() | android.view.WindowInsets.Type.ime());
                v.setPadding(b.left, b.top, b.right, b.bottom);
            }
            return insets;
        });
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        s.setMediaPlaybackRequiresUserGesture(true);
        web.addJavascriptInterface(new Bridge(), "MemoryAndroid");
        web.setWebViewClient(new WebViewClient() {
            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest req) {
                Uri u = req.getUrl();
                if (!"https".equals(u.getScheme()) || !"memory.local".equals(u.getHost())) return null;
                String p = u.getPath();
                if (p == null || p.equals("/")) p = "/index.html";
                if (p.contains("..") || p.contains("\\")) return missing();
                try {
                    String mime = p.endsWith(".html") ? "text/html" : p.endsWith(".js") ? "application/javascript" : p.endsWith(".json") ? "application/json" : p.endsWith(".svg") ? "image/svg+xml" : "application/octet-stream";
                    return new WebResourceResponse(mime, "UTF-8", 200, "OK", Collections.singletonMap("Cache-Control", "no-cache"), getAssets().open(p.substring(1)));
                } catch (IOException e) { return missing(); }
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                if (ORIGIN.equals(req.getUrl().getScheme()+"://"+req.getUrl().getHost())) return false;
                if (req.isForMainFrame() && "https".equals(req.getUrl().getScheme())) {
                    try { startActivity(new Intent(Intent.ACTION_VIEW, req.getUrl())); } catch (Exception ignored) {}
                }
                return true;
            }
            @Override public void onPageFinished(WebView v, String url) { openTask(getIntent()); }
        });
        web.setWebChromeClient(new WebChromeClient());
        web.loadUrl(ORIGIN+"/index.html");
    }
    /* Matches the system bars to the in-app theme, which can differ from the phone's own setting. */
    @SuppressWarnings("deprecation")
    private void applyBars(boolean dark) {
        int bg = dark ? 0xFF0E0E10 : 0xFFFDFBF7;
        getWindow().setStatusBarColor(bg);
        getWindow().setNavigationBarColor(bg);
        web.setBackgroundColor(bg);
        if (Build.VERSION.SDK_INT >= 30) {
            android.view.WindowInsetsController c = getWindow().getInsetsController();
            int light = android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS | android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
            if (c != null) c.setSystemBarsAppearance(dark ? 0 : light, light);
        } else {
            android.view.View d = getWindow().getDecorView();
            int light = android.view.View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | android.view.View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
            d.setSystemUiVisibility(dark ? d.getSystemUiVisibility() & ~light : d.getSystemUiVisibility() | light);
        }
    }
    private WebResourceResponse missing() { return new WebResourceResponse("text/plain", "UTF-8", 404, "Not Found", null, new ByteArrayInputStream(new byte[0])); }
    private void js(String code) { main.post(() -> { if (!isFinishing()) web.evaluateJavascript(code, null); }); }
    private void event(String type, String value) { js("window.memoryVoiceEvent&&window.memoryVoiceEvent("+JSONObject.quote(type)+","+JSONObject.quote(value)+")"); }
    private void openTask(Intent intent) {
        String id = intent.getStringExtra("taskId");
        if (id != null) { js("window.memoryOpenTask&&window.memoryOpenTask("+JSONObject.quote(id)+")"); intent.removeExtra("taskId"); }
    }
    @Override protected void onNewIntent(Intent intent) { super.onNewIntent(intent); setIntent(intent); openTask(intent); }
    @Override protected void onResume() { super.onResume(); if(web!=null) js("window.memoryResume&&window.memoryResume()"); }
    @Override public void onBackPressed() { js("if(typeof closeSheets==='function')closeSheets();if(typeof switchTab==='function')switchTab('homework')"); }
    @Override protected void onDestroy() { if(recognizer!=null)recognizer.destroy(); network.shutdownNow(); web.removeJavascriptInterface("MemoryAndroid"); web.destroy(); super.onDestroy(); }

    private void startSpeech(String language) {
        if(checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED){pendingLanguage=language;requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO},10);return;}
        if(!SpeechRecognizer.isRecognitionAvailable(this)){event("error","service-not-allowed");event("end","");return;}
        if(recognizer!=null)recognizer.destroy();
        recognizer=SpeechRecognizer.createSpeechRecognizer(this);
        recognizer.setRecognitionListener(new RecognitionListener(){
            public void onReadyForSpeech(Bundle b){event("start","");}
            public void onBeginningOfSpeech(){} public void onRmsChanged(float v){} public void onBufferReceived(byte[] b){} public void onEndOfSpeech(){}
            public void onError(int code){event("error",code==SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS?"not-allowed":code==SpeechRecognizer.ERROR_NO_MATCH||code==SpeechRecognizer.ERROR_SPEECH_TIMEOUT?"no-speech":code==SpeechRecognizer.ERROR_NETWORK?"network":"aborted");event("end","");}
            public void onResults(Bundle b){ArrayList<String> words=b.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);if(words!=null&&!words.isEmpty())event("result",words.get(0));event("end","");}
            public void onPartialResults(Bundle b){ArrayList<String> words=b.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);if(words!=null&&!words.isEmpty())event("partial",words.get(0));}
            public void onEvent(int t,Bundle b){}
        });
        Intent intent=new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE,language);
        intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS,true);
        recognizer.startListening(intent);
    }
    @Override public void onRequestPermissionsResult(int code,String[] permissions,int[] results){
        super.onRequestPermissionsResult(code,permissions,results);
        if(code==10){if(results.length>0&&results[0]==PackageManager.PERMISSION_GRANTED&&pendingLanguage!=null)startSpeech(pendingLanguage);else{event("error","not-allowed");event("end","");}pendingLanguage=null;}
        js("window.memoryResume&&window.memoryResume()");
    }
    public class Bridge {
        @JavascriptInterface public void startVoice(String language){main.post(()->startSpeech(language));}
        @JavascriptInterface public void stopVoice(){main.post(()->{if(recognizer!=null)recognizer.stopListening();});}
        @JavascriptInterface public void requestMicrophone(){main.post(()->requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO},11));}
        @JavascriptInterface public boolean microphoneAllowed(){return checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED;}
        @JavascriptInterface public boolean notificationsAllowed(){return getSystemService(NotificationManager.class).areNotificationsEnabled();}
        @JavascriptInterface public void requestNotifications(){main.post(()->{if(Build.VERSION.SDK_INT>=33&&checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS},12);else if(!notificationsAllowed())startActivity(new Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE,getPackageName()));});}
        @JavascriptInterface public void setSystemBars(boolean dark){main.post(()->applyBars(dark));}
        @JavascriptInterface public void syncReminders(String json){ReminderReceiver.sync(MainActivity.this,json);}
        @JavascriptInterface public String firedIds(){return ReminderReceiver.firedIds(MainActivity.this);}
        @JavascriptInterface public void request(String id,String url,String options){
            if(id==null||!id.matches("[0-9]+"))return;
            network.execute(()->{
                HttpsURLConnection connection=null;
                try {
                    URI uri=URI.create(url);
                    Set<String> paths=new HashSet<>(Arrays.asList("/api/v0/chat_session/create","/api/v0/chat/create_pow_challenge","/api/v0/chat/completion"));
                    if(!"https".equals(uri.getScheme())||!"chat.deepseek.com".equals(uri.getHost())||uri.getPort()!=-1||uri.getUserInfo()!=null||!paths.contains(uri.getPath())||uri.getQuery()!=null)throw new IOException("Request not allowed");
                    JSONObject o=new JSONObject(options);
                    connection=(HttpsURLConnection)uri.toURL().openConnection();
                    connection.setInstanceFollowRedirects(false);connection.setConnectTimeout(20000);connection.setReadTimeout(120000);connection.setRequestMethod("POST");connection.setDoOutput(true);
                    JSONObject headers=o.optJSONObject("headers");
                    for(String h:Arrays.asList("Content-Type","Authorization","X-App-Version","X-DS-PoW-Response"))if(headers!=null&&headers.has(h))connection.setRequestProperty(h,headers.getString(h));
                    byte[] body=o.optString("body","{}").getBytes(StandardCharsets.UTF_8);
                    if(body.length>1000000)throw new IOException("Request too large");
                    try(OutputStream out=connection.getOutputStream()){out.write(body);}
                    int status=connection.getResponseCode();
                    ByteArrayOutputStream bytes=new ByteArrayOutputStream();
                    InputStream stream=status>=400?connection.getErrorStream():connection.getInputStream();
                    if(stream!=null)try(InputStream in=stream){byte[] buf=new byte[8192];int n;while((n=in.read(buf))!=-1){if(bytes.size()+n>4000000)throw new IOException("Response too large");bytes.write(buf,0,n);}}
                    JSONObject response=new JSONObject();response.put("status",status);response.put("body",android.util.Base64.encodeToString(bytes.toByteArray(),android.util.Base64.NO_WRAP));
                    js("window.memoryNetworkResult("+JSONObject.quote(id)+","+response.toString()+")");
                }catch(Exception e){js("window.memoryNetworkResult("+JSONObject.quote(id)+",{error:'تعذر الاتصال بالخدمة. تحقق من الإنترنت ورمز الاتصال.'})");}
                finally{if(connection!=null)connection.disconnect();}
            });
        }
    }
}

