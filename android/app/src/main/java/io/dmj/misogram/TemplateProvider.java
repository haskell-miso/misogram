package io.dmj.misogram;

import android.content.Context;
import com.lynx.tasm.provider.AbsTemplateProvider;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import okhttp3.Call;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;

// Loads a Lynx template (.lynx.bundle) for the app: first from the bundled
// `assets/` dir, then falling back to a network URL (dev server). Mirrors
// ios/App/TemplateProvider.m.
public class TemplateProvider extends AbsTemplateProvider {

  private static final OkHttpClient client = new OkHttpClient();

  private final Context context;

  public TemplateProvider(Context context) {
    this.context = context.getApplicationContext();
  }

  @Override
  public void loadTemplate(String uri, Callback callback) {
    if (uri.startsWith("http://") || uri.startsWith("https://")) {
      loadFromNetwork(uri, callback);
    } else {
      loadFromAssets(uri, callback);
    }
  }

  private void loadFromAssets(String uri, Callback callback) {
    new Thread(
            () -> {
              try (InputStream in = context.getAssets().open(uri);
                  ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[4096];
                int length;
                while ((length = in.read(buffer)) != -1) {
                  out.write(buffer, 0, length);
                }
                callback.onSuccess(out.toByteArray());
              } catch (IOException e) {
                callback.onFailed(e.getMessage());
              }
            })
        .start();
  }

  private void loadFromNetwork(String uri, Callback callback) {
    Request request = new Request.Builder().url(uri).build();
    client
        .newCall(request)
        .enqueue(
            new okhttp3.Callback() {
              @Override
              public void onFailure(Call call, IOException e) {
                callback.onFailed(e.getMessage());
              }

              @Override
              public void onResponse(Call call, Response response) throws IOException {
                if (response.body() != null) {
                  callback.onSuccess(response.body().bytes());
                } else {
                  callback.onFailed("Empty response body for " + uri);
                }
              }
            });
  }
}
