package app.strata.vm;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.SurfaceTexture;
import android.view.Surface;

import io.flutter.view.TextureRegistry;

/**
 * VNC çerçevelerini bir Flutter Texture'ına çizer.
 * RfbClient piksel tamponunu doldurur, ayrı bir çizim iş parçacığı (≤60 fps) Surface'a basar.
 * Yalnızca değişen bölge kopyalanır; ses AudioPlayer'a, misafir panosu Flutter'a iletilir.
 */
final class DisplaySession implements RfbClient.Listener {
    private final TextureRegistry.SurfaceTextureEntry entry;
    private final SurfaceTexture surfaceTexture;
    private final Surface surface;
    private final RfbClient rfb;
    private final Thread renderThread;
    private final Object signal = new Object();

    private boolean dirty;
    private boolean sizeChanged;
    private int pendingW, pendingH;
    private volatile boolean alive = true;
    private boolean hardwareCanvas = true;
    private Bitmap bitmap;
    private final AudioPlayer audio;

    DisplaySession(TextureRegistry registry, boolean soundOn, boolean muted) {
        entry = registry.createSurfaceTexture();
        surfaceTexture = entry.surfaceTexture();
        surfaceTexture.setDefaultBufferSize(640, 480);
        surface = new Surface(surfaceTexture);
        rfb = new RfbClient("127.0.0.1", QemuCommand.VNC_PORT, this);
        rfb.audioWanted = soundOn;
        audio = soundOn ? new AudioPlayer() : null;
        if (audio != null) {
            audio.setMuted(muted);
            try { audio.start(); } catch (Exception e) { Events.emit(Events.of("type", "log", "line", "audio: " + e)); }
        }
        renderThread = new Thread(this::renderLoop, "display-render");
        renderThread.start();
        rfb.start();
    }

    long textureId() { return entry.id(); }

    RfbClient rfb() { return rfb; }

    // ------------------------------------------------------------ RFB olayları

    @Override
    public void onConnected(int width, int height) {
        resize(width, height);
        Events.emit(Events.of("type", "display", "state", "connected", "width", width, "height", height));
    }

    @Override
    public void onResize(int width, int height) {
        resize(width, height);
        Events.emit(Events.of("type", "display", "state", "resize", "width", width, "height", height));
    }

    @Override
    public void onFrame() {
        synchronized (signal) {
            dirty = true;
            signal.notifyAll();
        }
    }

    @Override
    public void onAudio(byte[] pcm) {
        if (audio != null) audio.write(pcm);
    }

    @Override
    public void onClipboard(String text) {
        if (text == null || text.isEmpty()) return;
        Events.emit(Events.of("type", "clipboard", "text", text));
    }

    void setMuted(boolean m) {
        if (audio != null) audio.setMuted(m);
    }

    @Override
    public void onDisconnected(String error) {
        if (!alive) return;
        Events.emit(Events.of("type", "display", "state", "disconnected", "error", error == null ? "" : error));
    }

    private void resize(int w, int h) {
        synchronized (signal) {
            pendingW = w;
            pendingH = h;
            sizeChanged = true;
            dirty = true;
            signal.notifyAll();
        }
    }

    // ------------------------------------------------------------ çizim

    private void renderLoop() {
        long lastFrame = 0;
        while (alive) {
            boolean resized;
            int w, h;
            synchronized (signal) {
                while (!dirty && alive) {
                    try { signal.wait(); } catch (InterruptedException e) { return; }
                }
                if (!alive) return;
                dirty = false;
                resized = sizeChanged;
                sizeChanged = false;
                w = pendingW;
                h = pendingH;
            }
            long wait = 16 - (System.currentTimeMillis() - lastFrame);
            if (wait > 0) {
                try { Thread.sleep(wait); } catch (InterruptedException e) { return; }
            }
            if (resized && w > 0 && h > 0) {
                surfaceTexture.setDefaultBufferSize(w, h);
                bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            }
            Bitmap bmp = bitmap;
            if (bmp == null) continue;
            synchronized (rfb.lock) {
                int bw = bmp.getWidth();
                if (rfb.width != bw || rfb.height != bmp.getHeight()) continue;
                // Yeni bitmap tamamen, sonrakiler yalnızca değişen dikdörtgen kadar kopyalanır
                int[] d = resized ? new int[]{0, 0, bw, bmp.getHeight()} : rfb.takeDirtyLocked();
                if (resized) rfb.takeDirtyLocked();
                if (d != null) bmp.setPixels(rfb.pixels, d[1] * bw + d[0], bw, d[0], d[1], d[2], d[3]);
            }
            draw(bmp);
            lastFrame = System.currentTimeMillis();
        }
    }

    private void draw(Bitmap bmp) {
        if (!alive || !surface.isValid()) return;
        Canvas c = null;
        try {
            c = hardwareCanvas ? surface.lockHardwareCanvas() : surface.lockCanvas(null);
            c.drawBitmap(bmp, 0, 0, null);
        } catch (Exception e) {
            hardwareCanvas = false;
        } finally {
            if (c != null) {
                try { surface.unlockCanvasAndPost(c); } catch (Exception ignored) { }
            }
        }
    }

    /** Ekran görüntüsü için anlık kopya. */
    Bitmap snapshot() {
        synchronized (rfb.lock) {
            if (rfb.width <= 0 || rfb.height <= 0) return null;
            Bitmap b = Bitmap.createBitmap(rfb.width, rfb.height, Bitmap.Config.ARGB_8888);
            b.setPixels(rfb.pixels, 0, rfb.width, 0, 0, rfb.width, rfb.height);
            return b;
        }
    }

    void dispose() {
        alive = false;
        synchronized (signal) { signal.notifyAll(); }
        rfb.stop();
        if (audio != null) audio.stop();
        try { renderThread.join(500); } catch (InterruptedException ignored) { }
        surface.release();
        entry.release();
    }
}
