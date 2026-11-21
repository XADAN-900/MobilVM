package app.strata.vm;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.zip.Inflater;

/**
 * Sıfır bağımlılıklı VNC (RFB 3.8) istemcisi.
 * Kodlamalar: Raw, CopyRect, DesktopSize. Sunucu aynı cihazda (127.0.0.1) olduğu için Raw yeterince hızlı.
 * QEMU uzantıları: ses akışı (-259) ve genişletilmiş pano (0xC0A1E5CE).
 * Android'e bağımlı değildir; CI'da gerçek QEMU'ya karşı test edilir.
 */
final class RfbClient {
    interface Listener {
        void onConnected(int width, int height);
        void onResize(int width, int height);
        void onFrame();
        void onDisconnected(String error);

        /** VM sesinden bir PCM parçası (S16LE, stereo, 44.1 kHz). */
        default void onAudio(byte[] pcm) { }

        /** Misafir panosu değişti (spice-vdagent çalışan Linux misafirler). */
        default void onClipboard(String text) { }
    }

    private interface Writer { void write(DataOutputStream out) throws IOException; }

    static final int AUDIO_RATE = 44100;
    private static final int ENC_AUDIO = -259;
    private static final int ENC_CLIPBOARD_EXT = 0xC0A1E5CE;
    private static final int CB_TEXT = 1;
    private static final int CB_CAPS = 1 << 24;
    private static final int CB_REQUEST = 1 << 25;
    private static final int CB_NOTIFY = 1 << 27;
    private static final int CB_PROVIDE = 1 << 28;

    /** Görüntü tamponu (ARGB). Okurken/yazarken {@link #lock} tutulmalı. */
    final Object lock = new Object();
    volatile int width;
    volatile int height;
    int[] pixels = new int[0];

    private final String host;
    private final int port;
    private final Listener listener;
    private final ExecutorService sender = Executors.newSingleThreadExecutor();
    private Socket socket;
    private DataInputStream in;
    private DataOutputStream out;
    private volatile boolean running;
    private volatile boolean needFull = true;
    private byte[] rowBytes = new byte[0];
    /** QEMU ses uzantısını iste (sunucu -vnc ...,audiodev=... ile açıldıysa onaylar). */
    volatile boolean audioWanted = true;
    /** Sunucu ses uzantısını onayladı. */
    volatile boolean audioEnabled;
    /** Sunucu genişletilmiş panoyu destekliyor (misafirden telefona kopyalama bununla gelir). */
    volatile boolean clipboardExt;
    private int[] rowInts = new int[0];
    // Son çizimden beri değişen bölge (lock altında)
    private int dx0 = Integer.MAX_VALUE, dy0 = Integer.MAX_VALUE, dx1, dy1;

    RfbClient(String host, int port, Listener listener) {
        this.host = host;
        this.port = port;
        this.listener = listener;
    }

    void start() {
        running = true;
        new Thread(this::loop, "rfb-reader").start();
    }

    void stop() {
        running = false;
        closeSocket();
        sender.shutdownNow();
    }

    // ------------------------------------------------------------ olaylar

    void sendKey(int keysym, boolean down) {
        send(o -> {
            o.writeByte(4);
            o.writeByte(down ? 1 : 0);
            o.writeShort(0);
            o.writeInt(keysym);
        });
    }

    /** buttons: bit0 sol, bit1 orta, bit2 sağ, bit3 tekerlek yukarı, bit4 tekerlek aşağı */
    void sendPointer(int x, int y, int buttons) {
        final int cx = Math.max(0, Math.min(x, Math.max(0, width - 1)));
        final int cy = Math.max(0, Math.min(y, Math.max(0, height - 1)));
        send(o -> {
            o.writeByte(5);
            o.writeByte(buttons);
            o.writeShort(cx);
            o.writeShort(cy);
        });
    }

    // ------------------------------------------------------------ protokol

    private void loop() {
        String err = null;
        try {
            connectWithRetry();
            handshake();
            listener.onConnected(width, height);
            requestUpdate();
            while (running) readMessage();
        } catch (Exception e) {
            if (running) err = e.getMessage() != null ? e.getMessage() : e.toString();
        }
        running = false;
        closeSocket();
        listener.onDisconnected(err);
    }

    /** QEMU'nun VNC sunucusunu açması birkaç saniye sürebilir: 45 sn dene. */
    private void connectWithRetry() throws IOException, InterruptedException {
        long deadline = System.currentTimeMillis() + 45_000;
        while (true) {
            try {
                Socket s = new Socket();
                s.setTcpNoDelay(true);
                s.setReceiveBufferSize(1 << 20);
                s.connect(new InetSocketAddress(host, port), 2000);
                socket = s;
                break;
            } catch (IOException e) {
                if (!running || System.currentTimeMillis() > deadline) throw new IOException("VNC connect failed: " + e.getMessage());
                Thread.sleep(400);
            }
        }
        in = new DataInputStream(new BufferedInputStream(socket.getInputStream(), 1 << 18));
        out = new DataOutputStream(new BufferedOutputStream(socket.getOutputStream(), 1 << 12));
    }

    private void handshake() throws IOException {
        byte[] ver = new byte[12];
        in.readFully(ver);
        if (!new String(ver, StandardCharsets.US_ASCII).startsWith("RFB ")) throw new IOException("Not a VNC server");
        out.write("RFB 003.008\n".getBytes(StandardCharsets.US_ASCII));
        out.flush();

        int n = in.readUnsignedByte();
        if (n == 0) throw new IOException("Server refused: " + readString());
        byte[] types = new byte[n];
        in.readFully(types);
        boolean none = false;
        for (byte t : types) if (t == 1) none = true;
        if (!none) throw new IOException("Unsupported VNC security type");
        out.writeByte(1);
        out.flush();
        if (in.readInt() != 0) throw new IOException("VNC auth failed: " + readString());

        out.writeByte(1); // ClientInit: paylaşımlı
        out.flush();
        int w = in.readUnsignedShort();
        int h = in.readUnsignedShort();
        skipFully(16);
        readString();
        allocate(w, h);

        // SetPixelFormat: 32bpp little-endian, 0x00RRGGBB
        out.writeByte(0); out.write(new byte[3]);
        out.writeByte(32); out.writeByte(24); out.writeByte(0); out.writeByte(1);
        out.writeShort(255); out.writeShort(255); out.writeShort(255);
        out.writeByte(16); out.writeByte(8); out.writeByte(0); out.write(new byte[3]);

        // SetEncodings: CopyRect, Raw, DesktopSize, genişletilmiş pano, QEMU ses (-259)
        int[] enc = audioWanted ? new int[]{1, 0, -223, ENC_CLIPBOARD_EXT, ENC_AUDIO} : new int[]{1, 0, -223, ENC_CLIPBOARD_EXT};
        out.writeByte(2); out.writeByte(0); out.writeShort(enc.length);
        for (int e : enc) out.writeInt(e);
        out.flush();
    }

    private void readMessage() throws IOException {
        int type = in.readUnsignedByte();
        switch (type) {
            case 0: { // FramebufferUpdate
                in.readUnsignedByte();
                int rects = in.readUnsignedShort();
                for (int i = 0; i < rects; i++) readRect();
                listener.onFrame();
                requestUpdate();
                break;
            }
            case 1: { // SetColourMapEntries
                in.readUnsignedByte();
                in.readUnsignedShort();
                skipFully(in.readUnsignedShort() * 6);
                break;
            }
            case 2: // Bell
                break;
            case 3: { // ServerCutText: misafirin panosu
                skipFully(3);
                int len = in.readInt();
                if (len < 0) { // genişletilmiş pano: bayraklar + (zlib) veri
                    len = -len;
                    if (len < 4 || len > (8 << 20)) throw new IOException("Bad clipboard length");
                    int flags = in.readInt();
                    byte[] b = new byte[len - 4];
                    in.readFully(b);
                    extendedClipboard(flags, b);
                } else {
                    if (len > (8 << 20)) throw new IOException("Bad clipboard length");
                    byte[] b = new byte[len];
                    in.readFully(b);
                    listener.onClipboard(new String(b, StandardCharsets.ISO_8859_1));
                }
                break;
            }
            case 255: { // QEMU sunucu mesajı
                int sub = in.readUnsignedByte();
                if (sub != 1) throw new IOException("Unknown QEMU server message " + sub);
                int op = in.readUnsignedShort();
                if (op == 2) { // ses verisi
                    int len = in.readInt();
                    if (len < 0 || len > (4 << 20)) throw new IOException("Bad audio length " + len);
                    byte[] pcm = new byte[len];
                    in.readFully(pcm);
                    listener.onAudio(pcm);
                }
                break;
            }
            default:
                throw new IOException("Unknown RFB message " + type);
        }
    }

    private void readRect() throws IOException {
        int x = in.readUnsignedShort();
        int y = in.readUnsignedShort();
        int w = in.readUnsignedShort();
        int h = in.readUnsignedShort();
        int enc = in.readInt();
        switch (enc) {
            case 0: readRaw(x, y, w, h); break;
            case 1: {
                int sx = in.readUnsignedShort();
                int sy = in.readUnsignedShort();
                copyRect(sx, sy, x, y, w, h);
                break;
            }
            case -223:
                allocate(w, h);
                needFull = true;
                listener.onResize(w, h);
                break;
            case ENC_AUDIO: // sunucu ses uzantısını onayladı: biçimi ayarla ve sesi aç
                if (!audioEnabled && audioWanted) enableAudio();
                break;
            default:
                throw new IOException("Unsupported encoding " + enc);
        }
    }

    /** QEMU'nun genişletilmiş pano mesajları: yetenekler, "panoda metin var", metnin kendisi. */
    private void extendedClipboard(int flags, byte[] data) {
        if ((flags & CB_CAPS) != 0) {
            clipboardExt = true;
            return;
        }
        if ((flags & CB_NOTIFY) != 0 && (flags & CB_TEXT) != 0) {
            // Misafir yeni metin kopyaladı: iste
            send(o -> {
                o.writeByte(6); o.write(new byte[3]); o.writeInt(-4); o.writeInt(CB_REQUEST | CB_TEXT);
            });
            return;
        }
        if ((flags & CB_PROVIDE) != 0 && (flags & CB_TEXT) != 0) {
            try {
                Inflater inf = new Inflater();
                inf.setInput(data);
                byte[] buf = new byte[Math.max(256, data.length * 4)];
                int n = 0;
                while (!inf.finished()) {
                    if (n == buf.length) {
                        if (buf.length >= (16 << 20)) break;
                        buf = java.util.Arrays.copyOf(buf, buf.length * 2);
                    }
                    int k = inf.inflate(buf, n, buf.length - n);
                    if (k == 0 && (inf.needsInput() || inf.needsDictionary())) break;
                    n += k;
                }
                inf.end();
                if (n < 4) return;
                int size = ((buf[0] & 0xff) << 24) | ((buf[1] & 0xff) << 16) | ((buf[2] & 0xff) << 8) | (buf[3] & 0xff);
                size = Math.max(0, Math.min(size, n - 4));
                // Metin UTF-8 ve genelde NUL ile biter
                while (size > 0 && buf[4 + size - 1] == 0) size--;
                listener.onClipboard(new String(buf, 4, size, StandardCharsets.UTF_8));
            } catch (Exception ignored) { }
        }
    }

    /** 16-bit işaretli, stereo, 44.1 kHz ses iste ve akışı başlat. */
    private void enableAudio() {
        audioEnabled = true;
        send(o -> {
            o.writeByte(255); o.writeByte(1); o.writeShort(2); // biçim ayarla
            o.writeByte(3);   // S16
            o.writeByte(2);   // stereo
            o.writeInt(AUDIO_RATE);
            o.writeByte(255); o.writeByte(1); o.writeShort(0); // sesi aç
        });
    }

    /** Telefon panosundaki metni misafire gönderir (ClientCutText; QEMU metni olduğu gibi, UTF-8 iletir). */
    void sendClipboard(String text) {
        byte[] raw = text.getBytes(StandardCharsets.UTF_8);
        final byte[] b = raw.length > (1 << 20) - 1 ? java.util.Arrays.copyOf(raw, (1 << 20) - 1) : raw;
        send(o -> {
            o.writeByte(6); o.write(new byte[3]); o.writeInt(b.length); o.write(b);
        });
    }

    private void readRaw(int x, int y, int w, int h) throws IOException {
        int n = w * 4;
        if (rowBytes.length < n) rowBytes = new byte[n];
        if (rowInts.length < w) rowInts = new int[w];
        for (int r = 0; r < h; r++) {
            in.readFully(rowBytes, 0, n);
            ByteBuffer.wrap(rowBytes, 0, n).order(ByteOrder.LITTLE_ENDIAN).asIntBuffer().get(rowInts, 0, w);
            synchronized (lock) {
                if (y + r < height && x + w <= width) {
                    int off = (y + r) * width + x;
                    for (int i = 0; i < w; i++) pixels[off + i] = rowInts[i] | 0xFF000000;
                }
            }
        }
        markDirty(x, y, w, h);
    }

    private void markDirty(int x, int y, int w, int h) {
        synchronized (lock) {
            dx0 = Math.min(dx0, x);
            dy0 = Math.min(dy0, y);
            dx1 = Math.max(dx1, Math.min(width, x + w));
            dy1 = Math.max(dy1, Math.min(height, y + h));
        }
    }

    /** Son çağrıdan beri değişen bölge {x, y, w, h}; değişiklik yoksa null. lock altında çağrılmalı. */
    int[] takeDirtyLocked() {
        if (dx0 >= dx1 || dy0 >= dy1) return null;
        int[] r = {dx0, dy0, dx1 - dx0, dy1 - dy0};
        dx0 = dy0 = Integer.MAX_VALUE;
        dx1 = dy1 = 0;
        return r;
    }

    private void copyRect(int sx, int sy, int dx, int dy, int w, int h) {
        synchronized (lock) {
            if (sx + w > width || sy + h > height || dx + w > width || dy + h > height) return;
            if (sy < dy) {
                for (int r = h - 1; r >= 0; r--) System.arraycopy(pixels, (sy + r) * width + sx, pixels, (dy + r) * width + dx, w);
            } else {
                for (int r = 0; r < h; r++) System.arraycopy(pixels, (sy + r) * width + sx, pixels, (dy + r) * width + dx, w);
            }
        }
        markDirty(dx, dy, w, h);
    }

    private void allocate(int w, int h) {
        synchronized (lock) {
            width = w;
            height = h;
            pixels = new int[w * h];
            dx0 = dy0 = 0;
            dx1 = w;
            dy1 = h;
        }
    }

    private void requestUpdate() {
        final boolean incremental = !needFull;
        needFull = false;
        send(o -> {
            o.writeByte(3);
            o.writeByte(incremental ? 1 : 0);
            o.writeShort(0);
            o.writeShort(0);
            o.writeShort(width);
            o.writeShort(height);
        });
    }

    private void send(Writer wr) {
        if (!running) return;
        try {
            sender.execute(() -> {
                try {
                    wr.write(out);
                    out.flush();
                } catch (IOException ignored) { }
            });
        } catch (RejectedExecutionException ignored) { }
    }

    private String readString() throws IOException {
        int len = in.readInt();
        if (len < 0 || len > 65536) throw new IOException("Bad length " + len);
        byte[] b = new byte[len];
        in.readFully(b);
        return new String(b, StandardCharsets.UTF_8);
    }

    private void skipFully(int n) throws IOException {
        byte[] tmp = new byte[4096];
        while (n > 0) {
            int k = Math.min(n, tmp.length);
            in.readFully(tmp, 0, k);
            n -= k;
        }
    }

    private void closeSocket() {
        try {
            if (socket != null) socket.close();
        } catch (IOException ignored) { }
    }
}
