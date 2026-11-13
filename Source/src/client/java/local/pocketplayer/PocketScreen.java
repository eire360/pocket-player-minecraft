package local.pocketplayer;

import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.input.*;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.Identifier;
import com.mojang.blaze3d.platform.InputConstants;

final class PocketScreen extends Screen {
    private static final Identifier FRONT=PocketPlayer.id("textures/front.png");
    private float scale,x,y;
    private Double wheelAngle;
    PocketScreen(){super(Component.literal("Pocket Player"));}
    @Override protected void init(){
        scale=Math.min((height-36)/1620f,(width-140)/1000f);
        x=(width-1000*scale)/2;y=(height-1620*scale)/2;
        addRenderableWidget(Button.builder(Component.literal("Connect Music"),b->MusicLink.send("connect")).bounds(6,6,100,20).build());
        addRenderableWidget(Button.builder(Component.literal("Now Playing"),b->MusicLink.send("now")).bounds(6,29,100,20).build());
        addRenderableWidget(Button.builder(Component.literal("Done"),b->onClose()).bounds(width-50,6,44,20).build());
        MusicLink.send("visible 1");
    }
    private int px(double modelX){return Math.round(x+(498+(float)modelX*242)*scale);}
    private int py(double modelY){return Math.round(y+(810-(float)modelY*242)*scale);}
    private double mx(double pixel){return ((pixel-x)/scale-498)/242;}
    private double my(double pixel){return (810-(pixel-y)/scale)/242;}
    @Override public void extractRenderState(GuiGraphicsExtractor g,int mouseX,int mouseY,float dt){
        g.fill(0,0,width,height,0xBA111318);
        g.blit(FRONT,Math.round(x),Math.round(y),Math.round(x+1000*scale),Math.round(y+1620*scale),0,1,0,1);
        if(MusicLink.hasFrame)g.blit(MusicLink.LCD,px(-1.1),py(2.505),px(1.1),py(.705),0,1,0,1);
        g.text(font,"Wheel / scroll: navigate   Enter: select   Space: play/pause   Esc: return",8,height-20,0xFFE0E0E0);
        if(!MusicLink.status.isEmpty()) {
            String s=MusicLink.status;
            g.text(font,font.plainSubstrByWidth(s,width-16),8,height-10,0xFFFFD88C);
        }
        super.extractRenderState(g,mouseX,mouseY,dt);
    }
    @Override public void extractBackground(GuiGraphicsExtractor g,int mx,int my,float dt){}
    @Override public boolean isPauseScreen(){return false;}
    @Override public boolean mouseClicked(MouseButtonEvent e,boolean doubleClick){
        if(super.mouseClicked(e,doubleClick))return true;
        if(e.button()!=0)return false;
        double a=mx(e.x()),b=my(e.y()),wy=b+1.055,r=Math.hypot(a,wy);
        if(a>=-1.1 && a<=1.1 && b>=.705 && b<=2.505){
            double lcdY=(2.505-b)/1.8*392;
            if(lcdY>=74 && lcdY<362)MusicLink.send("row "+(int)((lcdY-74)/48));
            return true;
        }
        if(r<.42){MusicLink.send("select");return true;}
        if(r>=1.14 && r<=1.47){
            if(Math.abs(a)>Math.abs(wy))MusicLink.send(a>0?"next":"previous");
            else MusicLink.send(wy>0?"menu":"play");
            return true;
        }
        if(r<1.14){wheelAngle=Math.atan2(wy,a);return true;}
        return false;
    }
    @Override public boolean mouseDragged(MouseButtonEvent e,double dx,double dy){
        if(wheelAngle!=null){
            double angle=Math.atan2(my(e.y())+1.055,mx(e.x()));
            double delta=angle-wheelAngle;
            while(delta>Math.PI)delta-=Math.PI*2;
            while(delta<-Math.PI)delta+=Math.PI*2;
            if(Math.abs(delta)>.18){MusicLink.send("step "+(delta<0?1:-1));wheelAngle=angle;}
            return true;
        }
        return super.mouseDragged(e,dx,dy);
    }
    @Override public boolean mouseReleased(MouseButtonEvent e){wheelAngle=null;return super.mouseReleased(e);}
    @Override public boolean mouseScrolled(double x,double y,double horizontal,double vertical){
        if(vertical!=0)MusicLink.send("step "+(vertical>0?-1:1));
        return true;
    }
    @Override public boolean keyPressed(KeyEvent e){
        switch(e.key()){
            case InputConstants.KEY_UP -> MusicLink.send("step -1");
            case InputConstants.KEY_DOWN -> MusicLink.send("step 1");
            case InputConstants.KEY_RETURN,InputConstants.KEY_NUMPADENTER -> MusicLink.send("select");
            case InputConstants.KEY_SPACE -> MusicLink.send("play");
            case InputConstants.KEY_LEFT -> MusicLink.send("previous");
            case InputConstants.KEY_RIGHT -> MusicLink.send("next");
            case InputConstants.KEY_BACKSPACE -> MusicLink.send("menu");
            default -> {return super.keyPressed(e);}
        }
        return true;
    }
}
