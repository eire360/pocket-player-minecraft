package local.pocketplayer;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.serialization.MapCodec;
import java.io.*;
import java.util.*;
import java.util.function.Consumer;
import net.minecraft.client.renderer.SubmitNodeCollector;
import net.minecraft.client.renderer.rendertype.RenderTypes;
import net.minecraft.client.renderer.special.SpecialModelRenderer;
import net.minecraft.resources.Identifier;
import net.minecraft.util.LightCoordsUtil;
import net.minecraft.world.item.ItemStack;
import org.joml.*;
import org.jspecify.annotations.Nullable;

public final class PodRenderer implements SpecialModelRenderer<Void> {
    public static final Identifier ID=PocketPlayer.id("ipod");
    record Vertex(float x,float y,float z,float u,float v,int color){}
    record Part(Identifier texture,Vertex[] vertices,int[] indices){}
    private static final List<Part> PARTS=load();
    private static List<Part> load(){
        try(DataInputStream input=new DataInputStream(Objects.requireNonNull(PodRenderer.class.getResourceAsStream("/assets/pocketplayer/mesh/ipod.bin")))){
            int count=input.readInt();List<Part> parts=new ArrayList<>(count);
            for(int n=0;n<count;n++){
                Identifier texture=Identifier.parse(input.readUTF());
                Vertex[] vertices=new Vertex[input.readInt()];
                for(int i=0;i<vertices.length;i++)vertices[i]=new Vertex(input.readFloat(),input.readFloat(),input.readFloat(),input.readFloat(),input.readFloat(),input.readInt());
                int[] indices=new int[input.readInt()];
                for(int i=0;i<indices.length;i++)indices[i]=input.readInt();
                parts.add(new Part(texture,vertices,indices));
            }
            return List.copyOf(parts);
        }catch(Exception e){throw new IllegalStateException("Pocket Player mesh could not be loaded",e);}
    }
    @Override public @Nullable Void extractArgument(ItemStack stack){return null;}
    @Override public void submit(@Nullable Void unused,PoseStack matrices,SubmitNodeCollector collector,int light,int overlay,boolean foil,int outline){
        for(Part part:PARTS){
            collector.submitCustomGeometry(matrices,RenderTypes.text(part.texture),(pose,buffer)->{
                for(int i=0;i<part.indices.length;i+=3){
                    // Minecraft's text pipeline consumes quads. A duplicate last
                    // vertex represents one triangle without changing the mesh.
                    for(int corner=0;corner<4;corner++){
                        Vertex v=part.vertices[part.indices[i+java.lang.Math.min(corner,2)]];
                        buffer.addVertex(pose,v.x,v.y,v.z).setColor(v.color).setUv(v.u,v.v).setLight(light);
                    }
                }
            });
        }
        Identifier picture=MusicLink.hasFrame?MusicLink.LCD:PocketPlayer.id("textures/lcd_off.png");
        collector.submitCustomGeometry(matrices,RenderTypes.text(picture),(pose,buffer)->{
            float x=.176f,y0=.1128f,y1=.4008f,z=.0205f;
            int glow=LightCoordsUtil.FULL_BRIGHT;
            buffer.addVertex(pose,-x,y0,z).setColor(-1).setUv(0,1).setLight(glow);
            buffer.addVertex(pose,x,y0,z).setColor(-1).setUv(1,1).setLight(glow);
            buffer.addVertex(pose,x,y1,z).setColor(-1).setUv(1,0).setLight(glow);
            buffer.addVertex(pose,-x,y1,z).setColor(-1).setUv(0,0).setLight(glow);
        });
    }
    @Override public void getExtents(Consumer<Vector3fc> out){
        for(float x:new float[]{-.273f,.273f})for(float y:new float[]{-.454f,.457f})for(float z:new float[]{-.04f,.041f})out.accept(new Vector3f(x,y,z));
    }
    public record Unbaked() implements SpecialModelRenderer.Unbaked<Void>{
        public static final MapCodec<Unbaked> MAP_CODEC=MapCodec.unit(new Unbaked());
        @Override public SpecialModelRenderer<Void> bake(SpecialModelRenderer.BakingContext context){return new PodRenderer();}
        @Override public MapCodec<Unbaked> type(){return MAP_CODEC;}
    }
}
