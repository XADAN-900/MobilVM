package app.strata.vm;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;

import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.TimeUnit;

/**
 * VM'den gelen PCM sesini (44.1 kHz, 16-bit, stereo) çalar.
 * Görüntü iş parçacığını bekletmemek için ayrı bir iş parçacığı ve kısa bir kuyruk kullanır;
 * kuyruk dolarsa en eski parça atılır (gecikme birikmesin).
 */
final class AudioPlayer {
    static final int RATE = RfbClient.AUDIO_RATE;
    private final BlockingQueue<byte[]> queue = new ArrayBlockingQueue<>(24);
    private volatile boolean running;
    private volatile boolean muted;
    private Thread thread;
    private AudioTrack track;

    synchronized void start() {
        if (running) return;
        running = true;
        int min = AudioTrack.getMinBufferSize(RATE, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT);
        track = new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_GAME)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build())
                .setAudioFormat(new AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(RATE)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                        .build())
                .setBufferSizeInBytes(Math.max(min * 2, RATE)) // ~250 ms
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build();
        track.play();
        thread = new Thread(this::loop, "vm-audio");
        thread.start();
    }

    void write(byte[] pcm) {
        if (!running || muted) return;
        if (!queue.offer(pcm)) {
            queue.poll();
            queue.offer(pcm);
        }
    }

    void setMuted(boolean m) {
        muted = m;
        if (m) queue.clear();
    }

    private void loop() {
        while (running) {
            try {
                byte[] b = queue.poll(200, TimeUnit.MILLISECONDS);
                if (b != null && track != null) track.write(b, 0, b.length);
            } catch (InterruptedException e) {
                return;
            } catch (Exception ignored) { }
        }
    }

    synchronized void stop() {
        running = false;
        if (thread != null) thread.interrupt();
        queue.clear();
        if (track != null) {
            try { track.stop(); } catch (Exception ignored) { }
            track.release();
            track = null;
        }
    }
}
