package io.dmj.misogram;

import android.app.Application;
import com.facebook.drawee.backends.pipeline.Fresco;
import com.lynx.service.http.LynxHttpService;
import com.lynx.service.image.LynxImageService;
import com.lynx.service.log.LynxLogService;
import com.lynx.tasm.LynxEnv;
import com.lynx.tasm.service.LynxServiceCenter;

// Lynx global setup: register the image/log/http services and initialise the
// environment once, at process start. Mirrors ios/App/AppDelegate.m.
public class MisoGramApplication extends Application {

  @Override
  public void onCreate() {
    super.onCreate();
    Fresco.initialize(this);
    LynxServiceCenter.inst().registerService(LynxImageService.getInstance());
    LynxServiceCenter.inst().registerService(LynxLogService.INSTANCE);
    LynxServiceCenter.inst().registerService(LynxHttpService.INSTANCE);
    LynxEnv.inst().init(this, null, null, null);
  }
}
