-keep @androidx.annotation.Keep class ** {
    @androidx.annotation.Keep <fields>;
    @androidx.annotation.Keep <methods>;
}
-keepclasseswithmembers,includedescriptorclasses class * {
    native <methods>;
}
-keep class com.lynx.tasm.behavior.ui.LynxBaseUI
-keep class com.lynx.tasm.behavior.shadow.ShadowNode
-keep class * extends com.lynx.tasm.behavior.ui.LynxBaseUI
-keep class * extends com.lynx.tasm.behavior.shadow.ShadowNode
-keep class * extends com.lynx.jsbridge.LynxModule { *; }
