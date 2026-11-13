package local.pocketplayer;

import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.*;
import net.fabricmc.fabric.api.client.keymapping.v1.KeyMappingHelper;
import net.minecraft.client.*;
import net.minecraft.client.renderer.special.SpecialModelRenderers;
import com.mojang.blaze3d.platform.InputConstants;

public final class PocketClient implements ClientModInitializer {
    private static KeyMapping inspect;
    public static boolean holding(Minecraft mc) {
        return mc.player != null && (mc.player.getMainHandItem().is(PocketPlayer.IPOD) || mc.player.getOffhandItem().is(PocketPlayer.IPOD));
    }
    @Override public void onInitializeClient() {
        PocketPlayer.open = () -> Minecraft.getInstance().gui.setScreen(new PocketScreen());
        SpecialModelRenderers.ID_MAPPER.put(PodRenderer.ID,PodRenderer.Unbaked.MAP_CODEC);
        inspect = KeyMappingHelper.registerKeyMapping(new KeyMapping("key.pocketplayer.inspect", InputConstants.Type.KEYBOARD,InputConstants.KEY_R,KeyMapping.Category.MISC));
        ClientTickEvents.END_CLIENT_TICK.register(mc -> {
            while(inspect.consumeClick()) if(holding(mc) && mc.gui.screen()==null) PocketPlayer.open.run();
            MusicLink.tick(mc,holding(mc) || mc.gui.screen() instanceof PocketScreen);
        });
        ClientLifecycleEvents.CLIENT_STOPPING.register(mc -> MusicLink.close());
    }
}
