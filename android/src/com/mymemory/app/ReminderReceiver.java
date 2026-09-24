package com.mymemory.app;
import android.app.*;
import android.content.*;
import android.net.Uri;
import org.json.*;
import java.util.*;

public class ReminderReceiver extends BroadcastReceiver {
    static final String CHANNEL="memory-reminders";
    static android.content.SharedPreferences prefs(Context c){return c.getSharedPreferences("reminders",Context.MODE_PRIVATE);}
    static void channel(Context c){c.getSystemService(NotificationManager.class).createNotificationChannel(new NotificationChannel(CHANNEL,"تذكيرات المهام",NotificationManager.IMPORTANCE_DEFAULT));}
    private static PendingIntent alarm(Context c,String id){
        Intent i=new Intent(c,ReminderReceiver.class).setData(new Uri.Builder().scheme("memory").authority("reminder").appendPath(id).build()).putExtra("taskId",id);
        return PendingIntent.getBroadcast(c,0,i,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
    }
    static synchronized void sync(Context c,String json){
        try{
            JSONArray next=new JSONArray(json);
            if(next.length()>5000)return;
            JSONArray previous=new JSONArray(prefs(c).getString("tasks","[]"));
            AlarmManager manager=c.getSystemService(AlarmManager.class);
            for(int i=0;i<previous.length();i++)manager.cancel(alarm(c,previous.getJSONObject(i).getString("id")));
            prefs(c).edit().putString("tasks",json).apply();
            Set<String> fired=new HashSet<>(prefs(c).getStringSet("fired",Collections.emptySet()));
            Set<String> retained=new HashSet<>();
            for(int i=0;i<next.length();i++){
                JSONObject task=next.getJSONObject(i);String id=task.getString("id");long when=task.optLong("dueAt",0);String key=id+"@"+when;
                if(fired.contains(key)){retained.add(key);continue;}
                if(when<=0||task.optBoolean("notified"))continue;
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,Math.max(when,System.currentTimeMillis()+1000),alarm(c,id));
            }
            prefs(c).edit().putStringSet("fired",retained).apply();
        }catch(JSONException ignored){}
    }
    static synchronized String firedIds(Context c){
        JSONArray result=new JSONArray();
        try{
            Set<String> fired=prefs(c).getStringSet("fired",Collections.emptySet());
            JSONArray tasks=new JSONArray(prefs(c).getString("tasks","[]"));
            for(int i=0;i<tasks.length();i++){JSONObject t=tasks.getJSONObject(i);if(fired.contains(t.getString("id")+"@"+t.optLong("dueAt")))result.put(t.getString("id"));}
        }catch(JSONException ignored){}
        return result.toString();
    }
    @Override public void onReceive(Context c,Intent intent){
        synchronized(ReminderReceiver.class){
            String id=intent.getStringExtra("taskId");if(id==null)return;
            try{
                JSONArray tasks=new JSONArray(prefs(c).getString("tasks","[]"));
                for(int i=0;i<tasks.length();i++){
                    JSONObject t=tasks.getJSONObject(i);if(!id.equals(t.getString("id")))continue;
                    long when=t.optLong("dueAt");String key=id+"@"+when;
                    Set<String> fired=new HashSet<>(prefs(c).getStringSet("fired",Collections.emptySet()));
                    if(when>System.currentTimeMillis()||t.optBoolean("notified")||fired.contains(key))return;
                    NotificationManager nm=c.getSystemService(NotificationManager.class);if(!nm.areNotificationsEnabled())return;
                    channel(c);
                    Intent open=new Intent(c,MainActivity.class).putExtra("taskId",id).setData(new Uri.Builder().scheme("memory").authority("task").appendPath(id).build()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TOP);
                    PendingIntent tap=PendingIntent.getActivity(c,0,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
                    Notification n=new Notification.Builder(c,CHANNEL).setSmallIcon(com.mymemory.app.R.drawable.notification).setContentTitle(t.optString("title","تذكير")).setContentText("حان وقت المهمة · "+t.optString("subject","")).setContentIntent(tap).setAutoCancel(true).setShowWhen(true).build();
                    nm.notify(id,0,n);fired.add(key);prefs(c).edit().putStringSet("fired",fired).apply();return;
                }
            }catch(JSONException|SecurityException ignored){}
        }
    }
}
