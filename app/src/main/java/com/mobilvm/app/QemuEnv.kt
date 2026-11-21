package com.mobilvm.app

import android.content.Context
import java.io.File
import java.io.IOException
import java.util.zip.ZipInputStream

/**
 * QEMU çalışma ortamı.
 *
 * - Çalıştırılabilirler APK içinde jniLibs/arm64-v8a/lib*.so olarak durur; Android bunları
 *   nativeLibraryDir'e çıkarır ve oradan exec() serbesttir.
 * - Bağımlı kütüphaneler (glib, pixman, ...) ve BIOS dosyaları assets/qemu-runtime.zip içindedir;
 *   ilk açılışta filesDir/qemu altına açılır.
 *
 * Her ikisini de scripts/fetch_qemu_termux.py üretir.
 */
object QemuEnv {
    private const val RUNTIME_ASSET = "qemu-runtime.zip"

    const val BIN_X86_64 = "libqemu-system-x86_64.so"
    const val BIN_I386 = "libqemu-system-i386.so"
    const val BIN_IMG = "libqemu-img.so"

    fun nativeDir(ctx: Context) = File(ctx.applicationInfo.nativeLibraryDir)
    fun runtimeDir(ctx: Context) = File(ctx.filesDir, "qemu")
    fun libDir(ctx: Context) = File(runtimeDir(ctx), "lib")
    fun shareDir(ctx: Context) = File(runtimeDir(ctx), "share/qemu")

    /** ISO / disk imajlarının durduğu klasör (Android/data/com.mobilvm.app/files/images). */
    fun imagesDir(ctx: Context): File =
        File(ctx.getExternalFilesDir(null) ?: ctx.filesDir, "images").apply { mkdirs() }

    private fun bin(ctx: Context, name: String) = File(nativeDir(ctx), name).takeIf { it.exists() }

    /** 16/32-bit için i386 tercih edilir; yoksa x86_64 de gerçek modu/32-biti çalıştırabilir. */
    fun systemBinary(ctx: Context, arch: Arch): File? = when (arch) {
        Arch.X86_64 -> bin(ctx, BIN_X86_64)
        Arch.X86_16, Arch.X86_32 -> bin(ctx, BIN_I386) ?: bin(ctx, BIN_X86_64)
    }

    fun qemuImg(ctx: Context) = bin(ctx, BIN_IMG)

    fun isAvailable(ctx: Context) = systemBinary(ctx, Arch.X86_64) != null || systemBinary(ctx, Arch.X86_32) != null

    fun hasRuntimeAsset(ctx: Context) = runCatching { ctx.assets.open(RUNTIME_ASSET).close(); true }.getOrDefault(false)

    /** qemu-runtime.zip'i gerekirse (ilk kurulum / güncelleme) açar. */
    @Synchronized
    fun ensureRuntime(ctx: Context) {
        val root = runtimeDir(ctx)
        val stamp = File(root, ".stamp")
        @Suppress("DEPRECATION")
        val want = ctx.packageManager.getPackageInfo(ctx.packageName, 0).lastUpdateTime.toString()
        if (stamp.exists() && stamp.readText() == want) return

        root.deleteRecursively()
        root.mkdirs()
        val rootCanon = root.canonicalPath + File.separator
        val input = try {
            ctx.assets.open(RUNTIME_ASSET)
        } catch (e: IOException) {
            throw IllegalStateException("assets/$RUNTIME_ASSET yok. Önce scripts/fetch_qemu_termux.py çalıştır.")
        }
        ZipInputStream(input.buffered()).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                val out = File(root, entry.name)
                if (!out.canonicalPath.startsWith(rootCanon)) throw IOException("Geçersiz zip girdisi: ${entry.name}")
                if (entry.isDirectory) out.mkdirs() else {
                    out.parentFile?.mkdirs()
                    out.outputStream().use { zis.copyTo(it) }
                }
                entry = zis.nextEntry
            }
        }
        stamp.writeText(want)
    }

    fun environment(ctx: Context): Map<String, String> = mapOf(
        "LD_LIBRARY_PATH" to "${libDir(ctx).path}:${nativeDir(ctx).path}",
        "QEMU_MODULE_DIR" to File(libDir(ctx), "qemu").path,
        "TMPDIR" to ctx.cacheDir.path,
        "HOME" to ctx.filesDir.path,
    )

    /** qemu-img gibi kısa süreli bir aracı çalıştırıp (çıkış kodu, çıktı) döndürür. */
    fun runTool(ctx: Context, args: List<String>): Pair<Int, String> {
        ensureRuntime(ctx)
        val pb = ProcessBuilder(args).redirectErrorStream(true).directory(ctx.filesDir)
        pb.environment().putAll(environment(ctx))
        val p = pb.start()
        val out = p.inputStream.bufferedReader().readText()
        return p.waitFor() to out
    }
}
