package app.strata.vm;

import android.Manifest;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.MotionEvent;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;

public class MainActivity extends FlutterActivity {
    private StrataBridge bridge;

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        bridge = new StrataBridge(this, flutterEngine);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (Build.VERSION.SDK_INT >= 33) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 7);
        }
    }

    /** Oyun kumandası: ekran açıkken tuşlar VM'e gider (Flutter'a ulaşmaz). */
    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (bridge != null && bridge.gamepadKey(event)) return true;
        return super.dispatchKeyEvent(event);
    }

    @Override
    public boolean dispatchGenericMotionEvent(MotionEvent event) {
        if (bridge != null && bridge.gamepadMotion(event)) return true;
        return super.dispatchGenericMotionEvent(event);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (bridge != null) bridge.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    public void cleanUpFlutterEngine(FlutterEngine flutterEngine) {
        if (bridge != null) bridge.dispose();
        bridge = null;
        super.cleanUpFlutterEngine(flutterEngine);
    }
}
