import android.content.Context;
import java.util.*;
public class SmsRoleProbe {
 public static void main(String[] args)throws Exception{
 android.os.Looper.prepareMainLooper();Class<?> c=Class.forName("android.app.ActivityThread");Object t=c.getMethod("systemMain").invoke(null);Context ctx=(Context)c.getMethod("getSystemContext").invoke(t);Object r=ctx.getSystemService("role");
 List<String> names=new ArrayList<>(Arrays.asList("android.app.role.CALL_SCREENING","android.app.role.SYSTEM_GALLERY","android.app.role.SYSTEM_ACTIVITY_RECOGNIZER","android.app.role.HOME","android.app.role.ASSISTANT","android.app.role.CALL_REDIRECTION","android.app.role.BROWSER"));
 if(args.length>0 && args[0].equals("enable"))names.add("android.app.role.SMS");
 r.getClass().getMethod("setRoleNamesFromController",List.class).invoke(r,names);
 System.out.println("role names updated");System.exit(0);
 }
}