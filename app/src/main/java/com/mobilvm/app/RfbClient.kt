package com.mobilvm.app

import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import kotlin.concurrent.thread

/**
 * Minimal VNC (RFB 3.8) istemcisi — dış kütüphane yok.
 * Kodlamalar: Raw, CopyRect, DesktopSize. Sunucu yerel olduğu için Raw yeterince hızlı.
 */
class RfbClient(
    private val host: String,
    private val port: Int,
    private val listener: Listener,
) {
    interface Listener {
        fun onConnected(width: Int, height: Int)
        fun onFrame()
        fun onDisconnected(error: String?)
    }

    /** Görüntü tamponu (ARGB). Okurken/yazarken [lock] tutulmalı. */
    val lock = Any()
    @Volatile var width = 0
        private set
    @Volatile var height = 0
        private set
    var pixels = IntArray(0)
        private set

    private var socket: Socket? = null
    private lateinit var input: DataInputStream
    private lateinit var output: DataOutputStream
    private val sender = Executors.newSingleThreadExecutor()
    @Volatile private var running = false
    @Volatile private var needFullUpdate = true
    private var rowBytes = ByteArray(0)

    fun start() {
        running = true
        thread(name = "rfb-reader") { runLoop() }
    }

    fun stop() {
        running = false
        closeSocket()
        sender.shutdownNow()
    }

    // ---------------------------------------------------------------- olaylar

    fun sendKey(keysym: Int, down: Boolean) = send {
        it.writeByte(4); it.writeByte(if (down) 1 else 0); it.writeShort(0); it.writeInt(keysym)
    }

    fun tapKey(keysym: Int) { sendKey(keysym, true); sendKey(keysym, false) }

    /** buttons: bit0 sol, bit1 orta, bit2 sağ, bit3 tekerlek yukarı, bit4 tekerlek aşağı */
    fun sendPointer(x: Int, y: Int, buttons: Int) = send {
        it.writeByte(5); it.writeByte(buttons)
        it.writeShort(x.coerceIn(0, maxOf(0, width - 1)))
        it.writeShort(y.coerceIn(0, maxOf(0, height - 1)))
    }

    // ---------------------------------------------------------------- protokol

    private fun runLoop() {
        var err: String? = null
        try {
            connectWithRetry()
            handshake()
            listener.onConnected(width, height)
            requestUpdate()
            while (running) readMessage()
        } catch (e: Exception) {
            if (running) err = e.message ?: e.toString()
        }
        running = false
        closeSocket()
        listener.onDisconnected(err)
    }

    /** QEMU'nun VNC sunucusunu açması birkaç saniye sürebilir; 30 sn dene. */
    private fun connectWithRetry() {
        val deadline = System.currentTimeMillis() + 30_000
        while (true) {
            try {
                val s = Socket()
                s.tcpNoDelay = true
                s.connect(InetSocketAddress(host, port), 2000)
                socket = s
                break
            } catch (e: IOException) {
                if (!running || System.currentTimeMillis() > deadline) throw IOException("VNC'ye bağlanılamadı ($port): ${e.message}")
                Thread.sleep(500)
            }
        }
        input = DataInputStream(BufferedInputStream(socket!!.getInputStream(), 1 shl 16))
        output = DataOutputStream(BufferedOutputStream(socket!!.getOutputStream(), 1 shl 12))
    }

    private fun handshake() {
        val ver = ByteArray(12).also { input.readFully(it) }
        if (!String(ver, Charsets.US_ASCII).startsWith("RFB ")) throw IOException("VNC sunucusu değil")
        output.write("RFB 003.008\n".toByteArray(Charsets.US_ASCII)); output.flush()

        val n = input.readUnsignedByte()
        if (n == 0) throw IOException("Sunucu reddetti: ${readString()}")
        val types = ByteArray(n).also { input.readFully(it) }
        if (types.none { it.toInt() == 1 }) throw IOException("Şifresiz VNC gerekli (güvenlik türü 1)")
        output.writeByte(1); output.flush()
        if (input.readInt() != 0) throw IOException("VNC doğrulama başarısız: ${readString()}")

        output.writeByte(1); output.flush()            // ClientInit: paylaşımlı
        val w = input.readUnsignedShort()
        val h = input.readUnsignedShort()
        skipFully(16)                                   // sunucunun piksel formatı
        readString()                                    // masaüstü adı
        allocate(w, h)

        // SetPixelFormat: 32 bpp, little-endian, 0x00RRGGBB
        output.writeByte(0); output.write(ByteArray(3))
        output.writeByte(32); output.writeByte(24); output.writeByte(0); output.writeByte(1)
        output.writeShort(255); output.writeShort(255); output.writeShort(255)
        output.writeByte(16); output.writeByte(8); output.writeByte(0); output.write(ByteArray(3))

        // SetEncodings
        val enc = intArrayOf(1 /*CopyRect*/, 0 /*Raw*/, -223 /*DesktopSize*/)
        output.writeByte(2); output.writeByte(0); output.writeShort(enc.size)
        enc.forEach { output.writeInt(it) }
        output.flush()
    }

    private fun readMessage() {
        when (val type = input.readUnsignedByte()) {
            0 -> { // FramebufferUpdate
                input.readUnsignedByte()
                repeat(input.readUnsignedShort()) { readRect() }
                listener.onFrame()
                requestUpdate()
            }
            1 -> { // SetColourMapEntries (true-color'da kullanılmaz)
                input.readUnsignedByte(); input.readUnsignedShort()
                skipFully(input.readUnsignedShort() * 6)
            }
            2 -> Unit // Bell
            3 -> { skipFully(3); skipFully(input.readInt()) } // ServerCutText
            else -> throw IOException("Bilinmeyen RFB mesajı: $type")
        }
    }

    private fun readRect() {
        val x = input.readUnsignedShort()
        val y = input.readUnsignedShort()
        val w = input.readUnsignedShort()
        val h = input.readUnsignedShort()
        when (val enc = input.readInt()) {
            0 -> readRaw(x, y, w, h)
            1 -> copyRect(input.readUnsignedShort(), input.readUnsignedShort(), x, y, w, h)
            -223 -> { allocate(w, h); needFullUpdate = true }
            else -> throw IOException("Desteklenmeyen kodlama: $enc")
        }
    }

    private fun readRaw(x: Int, y: Int, w: Int, h: Int) {
        val n = w * 4
        if (rowBytes.size < n) rowBytes = ByteArray(n)
        val row = IntArray(w)
        for (r in 0 until h) {
            input.readFully(rowBytes, 0, n)
            ByteBuffer.wrap(rowBytes, 0, n).order(ByteOrder.LITTLE_ENDIAN).asIntBuffer().get(row)
            synchronized(lock) {
                if (y + r < height && x + w <= width) {
                    val off = (y + r) * width + x
                    for (i in 0 until w) pixels[off + i] = row[i] or -0x1000000
                }
            }
        }
    }

    private fun copyRect(sx: Int, sy: Int, dx: Int, dy: Int, w: Int, h: Int) {
        synchronized(lock) {
            if (sx + w > width || sy + h > height || dx + w > width || dy + h > height) return
            val rows: IntProgression = if (sy < dy) (h - 1 downTo 0) else (0 until h)
            for (r in rows) System.arraycopy(pixels, (sy + r) * width + sx, pixels, (dy + r) * width + dx, w)
        }
    }

    private fun allocate(w: Int, h: Int) = synchronized(lock) {
        width = w; height = h
        pixels = IntArray(w * h)
    }

    private fun requestUpdate() {
        val incremental = !needFullUpdate
        needFullUpdate = false
        send {
            it.writeByte(3); it.writeByte(if (incremental) 1 else 0)
            it.writeShort(0); it.writeShort(0); it.writeShort(width); it.writeShort(height)
        }
    }

    private fun send(block: (DataOutputStream) -> Unit) {
        if (!running) return
        try {
            sender.execute {
                try { block(output); output.flush() } catch (_: IOException) {}
            }
        } catch (_: RejectedExecutionException) {}
    }

    private fun readString(): String {
        val len = input.readInt()
        if (len !in 0..65536) throw IOException("Geçersiz uzunluk $len")
        return String(ByteArray(len).also { input.readFully(it) }, Charsets.UTF_8)
    }

    private fun skipFully(n: Int) {
        var left = n
        val tmp = ByteArray(4096)
        while (left > 0) {
            val k = minOf(left, tmp.size)
            input.readFully(tmp, 0, k)
            left -= k
        }
    }

    private fun closeSocket() = try { socket?.close() } catch (_: IOException) {}
}
