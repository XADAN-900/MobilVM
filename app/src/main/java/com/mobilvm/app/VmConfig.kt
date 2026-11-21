package com.mobilvm.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** Misafir sistemin bit genişliği. 16 ve 32-bit qemu-system-i386 ile, 64-bit qemu-system-x86_64 ile çalışır. */
enum class Arch(val label: String) {
    X86_16("16-bit  (DOS, Win 3.x)"),
    X86_32("32-bit  (Win 9x/XP, 32-bit Linux)"),
    X86_64("64-bit  (modern Linux, Windows)");
}

enum class BootDevice(val label: String, val qemuFlag: String) {
    CDROM("CD / ISO", "d"),
    DISK("Sabit disk", "c"),
    FLOPPY("Disket", "a"),
}

data class VmConfig(
    val id: String = UUID.randomUUID().toString(),
    var name: String = "Yeni VM",
    var arch: Arch = Arch.X86_64,
    var ramMb: Int = 1024,
    var cpus: Int = 2,
    var isoPath: String? = null,
    var diskPath: String? = null,
    var floppyPath: String? = null,
    var boot: BootDevice = BootDevice.CDROM,
    var keyboard: String = "en-us",
    var extraArgs: String = "",
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("name", name)
        .put("arch", arch.name)
        .put("ram", ramMb)
        .put("cpus", cpus)
        .put("iso", isoPath ?: "")
        .put("disk", diskPath ?: "")
        .put("floppy", floppyPath ?: "")
        .put("boot", boot.name)
        .put("keyboard", keyboard)
        .put("extra", extraArgs)

    companion object {
        fun fromJson(o: JSONObject) = VmConfig(
            id = o.getString("id"),
            name = o.optString("name", "VM"),
            arch = runCatching { Arch.valueOf(o.getString("arch")) }.getOrDefault(Arch.X86_64),
            ramMb = o.optInt("ram", 512),
            cpus = o.optInt("cpus", 1),
            isoPath = o.optString("iso").ifEmpty { null },
            diskPath = o.optString("disk").ifEmpty { null },
            floppyPath = o.optString("floppy").ifEmpty { null },
            boot = runCatching { BootDevice.valueOf(o.getString("boot")) }.getOrDefault(BootDevice.CDROM),
            keyboard = o.optString("keyboard", "en-us"),
            extraArgs = o.optString("extra", ""),
        )

        /** Mimariye göre makul varsayılanlar (yeni VM oluştururken). */
        fun defaultsFor(arch: Arch) = when (arch) {
            Arch.X86_16 -> Triple(16, 1, 512)     // RAM MB, CPU, disk MB
            Arch.X86_32 -> Triple(512, 1, 4096)
            Arch.X86_64 -> Triple(2048, 2, 16384)
        }
    }
}

/** VM listesini filesDir/vms.json içinde saklar. */
object VmRepository {
    private fun file(ctx: Context) = File(ctx.filesDir, "vms.json")

    @Synchronized
    fun load(ctx: Context): MutableList<VmConfig> {
        val f = file(ctx)
        if (!f.exists()) return mutableListOf()
        return runCatching {
            val arr = JSONArray(f.readText())
            MutableList(arr.length()) { VmConfig.fromJson(arr.getJSONObject(it)) }
        }.getOrElse { mutableListOf() }
    }

    @Synchronized
    fun save(ctx: Context, list: List<VmConfig>) {
        val arr = JSONArray()
        list.forEach { arr.put(it.toJson()) }
        val tmp = File(ctx.filesDir, "vms.json.tmp")
        tmp.writeText(arr.toString(2))
        tmp.renameTo(file(ctx))
    }

    fun get(ctx: Context, id: String) = load(ctx).firstOrNull { it.id == id }

    fun upsert(ctx: Context, vm: VmConfig) {
        val list = load(ctx)
        val i = list.indexOfFirst { it.id == vm.id }
        if (i >= 0) list[i] = vm else list += vm
        save(ctx, list)
    }

    fun delete(ctx: Context, id: String) = save(ctx, load(ctx).filterNot { it.id == id })
}
