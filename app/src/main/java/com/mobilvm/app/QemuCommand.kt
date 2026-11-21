package com.mobilvm.app

import android.content.Context
import java.io.File

/** VmConfig'ten QEMU komut satırı üretir. */
object QemuCommand {
    const val VNC_DISPLAY = 1
    const val VNC_PORT = 5900 + VNC_DISPLAY

    fun build(ctx: Context, vm: VmConfig): List<String> {
        val bin = QemuEnv.systemBinary(ctx, vm.arch)
            ?: error("QEMU ikilisi bulunamadı. README'deki 'QEMU'yu ekle' adımını yap.")

        val a = mutableListOf(bin.path, "-L", QemuEnv.shareDir(ctx).path, "-name", vm.name)

        when (vm.arch) {
            // 16-bit: 486 işlemci, Cirrus VGA, PS/2 fare (DOS'ta USB sürücüsü yok)
            Arch.X86_16 -> a += listOf("-M", "pc", "-cpu", "486", "-vga", "cirrus")
            // 32-bit: Win 9x/XP'nin kendi sürücüsü olan Cirrus VGA + dokunmatik için USB tablet
            Arch.X86_32 -> a += listOf("-M", "pc", "-cpu", "pentium3", "-vga", "cirrus",
                "-usb", "-device", "usb-tablet")
            // 64-bit: tüm CPU özellikleri (modern dağıtımlar x86-64-v2 ister)
            Arch.X86_64 -> a += listOf("-M", "pc", "-cpu", "max", "-vga", "std",
                "-usb", "-device", "usb-tablet")
        }

        // Telefonda KVM yok: TCG (yazılım emülasyonu). Büyük çeviri önbelleği hızı artırır.
        a += listOf("-m", "${vm.ramMb}", "-smp", "${vm.cpus}", "-accel", "tcg,tb-size=256")

        vm.diskPath?.let {
            a += listOf("-drive", "file=${esc(it)},format=${diskFormat(it)},if=ide,index=0,media=disk")
        }
        vm.isoPath?.let {
            a += listOf("-drive", "file=${esc(it)},format=raw,if=ide,index=2,media=cdrom")
        }
        vm.floppyPath?.let {
            a += listOf("-drive", "file=${esc(it)},format=raw,if=floppy,index=0")
        }
        a += listOf("-boot", "order=${vm.boot.qemuFlag},menu=on")
        a += listOf("-rtc", "base=localtime")

        // Görüntü: QEMU yerel VNC sunucusu açar, DisplayActivity'deki istemci bağlanır.
        a += listOf("-display", "none", "-vnc", "127.0.0.1:$VNC_DISPLAY")
        if (vm.keyboard.isNotBlank()) a += listOf("-k", vm.keyboard.trim())

        a += splitArgs(vm.extraArgs)
        return a
    }

    fun diskFormat(path: String): String = when (File(path).extension.lowercase()) {
        "qcow2", "qcow" -> "qcow2"
        "vdi" -> "vdi"
        "vmdk" -> "vmdk"
        "vhd" -> "vpc"
        "vhdx" -> "vhdx"
        else -> "raw" // .img, .ima, .bin ...
    }

    /** QEMU -drive içinde virgül ",," ile kaçırılır. */
    private fun esc(path: String) = path.replace(",", ",,")

    /** Basit argüman bölücü: boşluklara göre böler, "tırnak içini" tek argüman sayar. */
    fun splitArgs(s: String): List<String> {
        val out = mutableListOf<String>()
        val cur = StringBuilder()
        var quote: Char? = null
        var has = false
        for (c in s) {
            when {
                quote != null && c == quote -> quote = null
                quote == null && (c == '"' || c == '\'') -> { quote = c; has = true }
                quote == null && c.isWhitespace() -> {
                    if (has) { out += cur.toString(); cur.clear(); has = false }
                }
                else -> { cur.append(c); has = true }
            }
        }
        if (has) out += cur.toString()
        return out
    }
}
