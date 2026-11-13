package local.pocketplayer;

import com.google.gson.*;
import com.mojang.blaze3d.platform.NativeImage;
import java.nio.file.*;
import java.io.*;
import java.util.UUID;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicLong;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.texture.DynamicTexture;
import net.minecraft.resources.Identifier;
import org.slf4j.LoggerFactory;

final class MusicLink {
    static final Identifier LCD=PocketPlayer.id("live_lcd");
    static volatile String status="Open the iPod, then select Connect Music.";
    static volatile String title="Pocket Player";
    private static final String SESSION=UUID.randomUUID().toString();
    private static final AtomicLong SEQUENCE=new AtomicLong();
    private static final ThreadPoolExecutor IO=new ThreadPoolExecutor(1,1,0,TimeUnit.MILLISECONDS,
        new ArrayBlockingQueue<>(24),r->{Thread t=new Thread(r,"Pocket Player Music");t.setDaemon(true);return t;},new ThreadPoolExecutor.DiscardPolicy());
    private static volatile boolean launched,pending,closed;
    private static volatile long lastLaunch;
    private static long nextUpdate,nextHeartbeat;
    private static boolean wasVisible;
    static boolean hasFrame;
    private static DynamicTexture texture;
    static Path directory(){return Minecraft.getInstance().gameDirectory.toPath().resolve("pocketplayer");}
    private static Path live(){return directory().resolve("live");}
    private static void atomic(Path destination,String content)throws IOException{
        PrivateFiles.write(destination,content);
    }
    private static void heartbeat()throws IOException{
        PrivateFiles.directory(live());
        PrivateFiles.directory(live().resolve("commands"));
        JsonObject client=new JsonObject();
        client.addProperty("session",SESSION);
        client.addProperty("heartbeat",System.currentTimeMillis()/1000.0);
        atomic(live().resolve("client.json"),client.toString());
    }
    private static void failure(String phase,Exception error){
        String reason=error.getMessage()==null?error.getClass().getSimpleName():error.getMessage();
        status="Pocket Player "+phase+": "+reason;
        LoggerFactory.getLogger("pocketplayer").warn(status);
    }
    static void send(String command){
        if(closed)return;
        IO.execute(()->{
            if(closed)return;
            try {
                heartbeat();
                boolean stale=!Files.exists(live().resolve("state.json")) ||
                    System.currentTimeMillis()-Files.getLastModifiedTime(live().resolve("state.json")).toMillis()>8000;
                if(!launched || stale && System.currentTimeMillis()-lastLaunch>10000){
                    Path app=directory().resolve("Pocket Player Bridge.app");
                    if(!Files.isExecutable(app.resolve("Contents/MacOS/PocketPlayerBridge")))throw new IOException("Music bridge is missing.");
                    Process launch=new ProcessBuilder("/usr/bin/open","-g","-a",app.toString(),"--args",live().toString())
                        .redirectError(ProcessBuilder.Redirect.DISCARD).redirectOutput(ProcessBuilder.Redirect.DISCARD).start();
                    if(!launch.waitFor(5,TimeUnit.SECONDS)){launch.destroy();throw new IOException("macOS took too long to open the bridge.");}
                    if(launch.exitValue()!=0)throw new IOException("macOS could not open the Music bridge.");
                    launched=true;lastLaunch=System.currentTimeMillis();
                }
                JsonObject request=new JsonObject();
                request.addProperty("session",SESSION);request.addProperty("command",command);
                String name=String.format("%013d-%08d.json",System.currentTimeMillis(),SEQUENCE.incrementAndGet());
                atomic(live().resolve("commands").resolve(name),request.toString());
            }catch(Exception e){failure("connection",e);}
        });
    }
    static void tick(Minecraft mc,boolean visible){
        if(visible!=wasVisible){wasVisible=visible;if(launched)send("visible "+(visible?"1":"0"));}
        long now=System.currentTimeMillis();
        if(launched && now>=nextHeartbeat){
            nextHeartbeat=now+5000;
            IO.execute(()->{try{if(!closed)heartbeat();}catch(Exception e){failure("heartbeat",e);}});
        }
        if(!visible || !launched || pending || now<nextUpdate)return;
        nextUpdate=now+750;pending=true;
        IO.execute(()->{
            NativeImage image=null;
            try {
                Path statePath=live().resolve("state.json");
                if(!Files.exists(statePath)){
                    status="Starting Pocket Player Bridge…";pending=false;return;
                }
                JsonObject state=JsonParser.parseString(Files.readString(statePath)).getAsJsonObject();
                if(!state.has("session") || !SESSION.equals(state.get("session").getAsString())){
                    status="Starting Pocket Player Bridge…";pending=false;return;
                }
                if(System.currentTimeMillis()-Files.getLastModifiedTime(statePath).toMillis()>10000){
                    status="Pocket Player Bridge stopped responding. Click Connect Music to retry.";pending=false;return;
                }
                status=state.get("status").getAsString();
                title=state.get("title").getAsString();
                try(InputStream input=Files.newInputStream(live().resolve("lcd.png"))){image=NativeImage.read(input);}
                NativeImage ready=image;image=null;
                mc.execute(()->{
                    try {
                        if(closed){ready.close();return;}
                        if(texture==null){
                            texture=new DynamicTexture(()->"Pocket Player LCD",ready);
                            mc.getTextureManager().register(LCD,texture);
                        }else {texture.setPixels(ready);texture.upload();}
                        hasFrame=true;
                    }catch(Exception e){failure("display",e);}
                    finally{pending=false;}
                });
            }catch(Exception e){if(image!=null)image.close();pending=false;failure("display",e);}
        });
    }
    static void close(){
        if(launched){
            try{
                JsonObject request=new JsonObject();request.addProperty("session",SESSION);request.addProperty("command","quit");
                atomic(live().resolve("commands").resolve(String.format("%013d-quit.json",System.currentTimeMillis())),request.toString());
            }catch(IOException ignored){}
        }
        closed=true;IO.shutdownNow();
    }
}
