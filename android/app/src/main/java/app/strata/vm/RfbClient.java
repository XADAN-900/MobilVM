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

/**
 * Sıfır bağımlılıklı VNC (RFB 3.8) istemcisi.
 * Kodlamalar: Raw, CopyRect, DesktopSize. Sunucu aynı cihazda (127.0.0.1) olduğu için Raw yeterince hızlı.
 */
final class RfbClient {
    interface Listener {
        void onConnected(int width, int height);
        void onResize(int width, int height);
        void onFrame();
        void onDisconnected(String error);
    }

    private interface Writer { void write(DataOutputStream out) throws IOException; }

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
    private int[] rowInts = new int[0];

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

        // SetEncodings: CopyRect, Raw, DesktopSize
        int[] enc = {1, 0, -223};
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
            case 3: { // ServerCutText
                skipFully(3);
                skipFully(in.readInt());
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
            default:
                throw new IOException("Unsupported encoding " + enc);
        }
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
    }

    private void allocate(int w, int h) {
        synchronized (lock) {
            width = w;
            height = h;
            pixels = new int[w * h];
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
