package local.pocketplayer;

import net.fabricmc.api.ModInitializer;
import net.fabricmc.fabric.api.creativetab.v1.CreativeModeTabEvents;
import net.minecraft.core.Registry;
import net.minecraft.core.registries.*;
import net.minecraft.resources.*;
import net.minecraft.world.*;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.*;
import net.minecraft.world.item.context.UseOnContext;
import net.minecraft.world.level.Level;

public final class PocketPlayer implements ModInitializer {
    public static Identifier id(String path){return Identifier.fromNamespaceAndPath("pocketplayer",path);}
    public static Runnable open = () -> {};
    public static final Item IPOD = Registry.register(BuiltInRegistries.ITEM,id("ipod"),
        new Item(new Item.Properties().setId(ResourceKey.create(Registries.ITEM,id("ipod"))).stacksTo(1)) {
            @Override public InteractionResult use(Level level, Player player, InteractionHand hand) {
                if(level.isClientSide()) open.run();
                return InteractionResult.SUCCESS;
            }
            @Override public InteractionResult useOn(UseOnContext context) {
                if(context.getLevel().isClientSide()) open.run();
                return InteractionResult.SUCCESS;
            }
        });
    @Override public void onInitialize() {
        CreativeModeTabEvents.modifyOutputEvent(ResourceKey.create(Registries.CREATIVE_MODE_TAB, Identifier.withDefaultNamespace("tools_and_utilities")))
          .register(out -> out.accept(IPOD));
    }
}
