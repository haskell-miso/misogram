package io.dmj.misogram;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import com.lynx.tasm.LynxView;
import com.lynx.tasm.LynxViewBuilder;
import com.lynx.tasm.ThreadStrategyForRendering;
import com.lynx.xelement.XElementBehaviors;

// The bundle to load. TemplateProvider looks it up in `assets/`. To load from a
// dev server instead, use e.g. "http://<your-mac-ip>:8080/main.lynx.bundle"
// (usesCleartextTraffic is already enabled in AndroidManifest.xml for this).
public class MainActivity extends Activity {

  private static final String TEMPLATE_URL = "main.lynx.bundle";

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    // The manifest starts us in SplashTheme (the launch-screen drawable, see
    // res/values/styles.xml); switch to the real theme before drawing.
    setTheme(R.style.AppTheme);
    super.onCreate(savedInstanceState);

    LynxViewBuilder builder = new LynxViewBuilder();
    builder.addBehaviors(new XElementBehaviors().create());
    builder.setTemplateProvider(new TemplateProvider(this));
    // miso runs a dual-thread (MTS/BTS) app; ALL_ON_UI is the explorer default
    // and the strategy the bundle was verified under — see
    // ios/App/ViewController.m's equivalent setThreadStrategyForRender: call.
    builder.setThreadStrategyForRendering(ThreadStrategyForRendering.ALL_ON_UI);

    LynxView lynxView = builder.build(this);
    lynxView.setBackgroundColor(Color.WHITE);
    setContentView(lynxView);

    lynxView.renderTemplateUrl(TEMPLATE_URL, "");
  }
}
