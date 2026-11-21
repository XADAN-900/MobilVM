package com.mobilvm.app

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.text.InputType
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import java.io.File
import kotlin.concurrent.thread

/** VM oluşturma / düzenleme formu. */
class VmEditActivity : Activity() {

    companion object {
        const val EXTRA_ID = "vm_id"
        private const val REQ_ISO = 1
        private const val REQ_DISK = 2
        private const val REQ_FLOPPY = 3
    }

    private lateinit var vm: VmConfig
    private var isNew = true

    private lateinit var nameEt: EditText
    private lateinit var archSp: Spinner
    private lateinit var ramEt: EditText
    private lateinit var cpuEt: EditText
    private lateinit var isoTv: TextView
    private lateinit var diskTv: TextView
    private lateinit var floppyTv: TextView
    private lateinit var bootSp: Spinner
    private lateinit var kbdEt: EditText
    private lateinit var extraEt: EditText

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val existing = intent.getStringExtra(EXTRA_ID)?.let { VmRepository.get(this, it) }
        isNew = existing == null
        vm = existing ?: VmConfig()
        title = if (isNew) "Yeni sanal makine" else "Düzenle: ${vm.name}"

        val form = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(32, 24, 32, 48) }
        fun label(t: String) = form.addView(TextView(this).apply { text = t; setPadding(0, 28, 0, 4) })
        fun edit(value: String, numeric: Boolean = false) = EditText(this).apply {
            setText(value)
            inputType = if (numeric) InputType.TYPE_CLASS_NUMBER else InputType.TYPE_CLASS_TEXT
            form.addView(this, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
        fun spinner(items: List<String>, sel: Int) = Spinner(this).apply {
            adapter = ArrayAdapter(this@VmEditActivity, android.R.layout.simple_spinner_dropdown_item, items)
            setSelection(sel)
            form.addView(this, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
        fun pathRow(vararg buttons: Pair<String, () -> Unit>): TextView {
            val tv = TextView(this).apply { textSize = 13f }
            form.addView(tv)
            val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            buttons.forEach { (t, a) ->
                row.addView(Button(this).apply { text = t; isAllCaps = false; setOnClickListener { a() } },
                    LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
            }
            form.addView(row)
            return tv
        }

        label("Ad"); nameEt = edit(vm.name)
        label("Sistem türü"); archSp = spinner(Arch.entries.map { it.label }, vm.arch.ordinal)
        label("RAM (MB)"); ramEt = edit(vm.ramMb.toString(), numeric = true)
        label("İşlemci çekirdeği"); cpuEt = edit(vm.cpus.toString(), numeric = true)

        label("CD / ISO")
        isoTv = pathRow("ISO seç" to { pick(REQ_ISO) }, "Kaldır" to { vm.isoPath = null; updatePaths() })
        label("Sabit disk (img / qcow2 / vdi / vmdk / vhd)")
        diskTv = pathRow("Disk seç" to { pick(REQ_DISK) }, "Yeni disk" to { createDiskDialog() },
            "Kaldır" to { vm.diskPath = null; updatePaths() })
        label("Disket (img / ima) — DOS önyükleme disketleri için")
        floppyTv = pathRow("Disket seç" to { pick(REQ_FLOPPY) }, "Kaldır" to { vm.floppyPath = null; updatePaths() })

        label("Önyükleme"); bootSp = spinner(BootDevice.entries.map { it.label }, vm.boot.ordinal)
        label("Klavye düzeni (QEMU -k): en-us, tr, de ..."); kbdEt = edit(vm.keyboard)
        label("Ek QEMU parametreleri (ileri düzey)"); extraEt = edit(vm.extraArgs)

        form.addView(Button(this).apply { text = "Kaydet"; setOnClickListener { save() } },
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = 40 })

        // Yeni VM'de mimari değişince RAM/CPU/önyükleme önerilerini doldur
        archSp.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(p: AdapterView<*>?, v: View?, pos: Int, id: Long) {
                if (!isNew) return
                val arch = Arch.entries[pos]
                val (ram, cpu, _) = VmConfig.defaultsFor(arch)
                ramEt.setText(ram.toString()); cpuEt.setText(cpu.toString())
                if (arch == Arch.X86_16 && vm.isoPath == null) bootSp.setSelection(BootDevice.FLOPPY.ordinal)
            }
            override fun onNothingSelected(p: AdapterView<*>?) {}
        }

        setContentView(ScrollView(this).apply { addView(form) })
        updatePaths()
    }

    private fun updatePaths() {
        fun show(p: String?) = p?.let { File(it).name } ?: "— yok —"
        isoTv.text = show(vm.isoPath)
        diskTv.text = show(vm.diskPath)
        floppyTv.text = show(vm.floppyPath)
    }

    private fun readForm() {
        vm.name = nameEt.text.toString().trim().ifEmpty { "VM" }
        vm.arch = Arch.entries[archSp.selectedItemPosition]
        vm.ramMb = ramEt.text.toString().toIntOrNull()?.coerceIn(4, 16384) ?: 512
        vm.cpus = cpuEt.text.toString().toIntOrNull()?.coerceIn(1, 8) ?: 1
        vm.boot = BootDevice.entries[bootSp.selectedItemPosition]
        vm.keyboard = kbdEt.text.toString().trim()
        vm.extraArgs = extraEt.text.toString().trim()
    }

    private fun save() {
        readForm()
        VmRepository.upsert(this, vm)
        Toast.makeText(this, "Kaydedildi", Toast.LENGTH_SHORT).show()
        finish()
    }

    // ------------------------------------------------------------ dosya seçme

    @Suppress("DEPRECATION")
    private fun pick(req: Int) {
        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*")
        startActivityForResult(i, req)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val uri = data?.data ?: return
        if (resultCode != RESULT_OK) return
        importFile(uri) { path ->
            when (requestCode) {
                REQ_ISO -> { vm.isoPath = path; if (vm.diskPath == null || isNew) bootSp.setSelection(BootDevice.CDROM.ordinal) }
                REQ_DISK -> vm.diskPath = path
                REQ_FLOPPY -> vm.floppyPath = path
            }
            updatePaths()
        }
    }

    /**
     * QEMU içerik URI'lerini (content://) açamaz; dosya gerçek bir yola kopyalanır.
     * Aynı ad ve boyutta dosya zaten varsa tekrar kopyalanmaz.
     */
    private fun importFile(uri: Uri, done: (String) -> Unit) {
        var name = "dosya-${System.currentTimeMillis()}.img"
        var size = -1L
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                c.getString(0)?.let { name = it.replace('/', '_') }
                if (!c.isNull(1)) size = c.getLong(1)
            }
        }
        val target = File(QemuEnv.imagesDir(this), name)
        if (target.exists() && size > 0 && target.length() == size) { done(target.path); return }

        val bar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply { max = 1000 }
        val dlg = AlertDialog.Builder(this)
            .setTitle("Kopyalanıyor: $name")
            .setView(LinearLayout(this).apply { setPadding(48, 24, 48, 24); addView(bar, MATCH_PARENT, WRAP_CONTENT) })
            .setCancelable(false)
            .show()

        thread {
            val result = runCatching {
                val tmp = File(target.path + ".part")
                contentResolver.openInputStream(uri)!!.use { inp ->
                    tmp.outputStream().use { out ->
                        val buf = ByteArray(1 shl 20)
                        var total = 0L
                        var lastUi = 0L
                        while (true) {
                            val n = inp.read(buf)
                            if (n < 0) break
                            out.write(buf, 0, n)
                            total += n
                            if (size > 0 && total - lastUi > (8 shl 20)) {
                                lastUi = total
                                val p = (total * 1000 / size).toInt()
                                runOnUiThread { bar.progress = p }
                            }
                        }
                    }
                }
                if (!tmp.renameTo(target)) error("Dosya taşınamadı")
                target.path
            }
            runOnUiThread {
                dlg.dismiss()
                result.onSuccess(done).onFailure {
                    Toast.makeText(this, "Kopyalama hatası: ${it.message}", Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    // ------------------------------------------------------------ yeni disk

    private fun createDiskDialog() {
        val img = QemuEnv.qemuImg(this)
        if (img == null) {
            Toast.makeText(this, "qemu-img bu APK'da yok.", Toast.LENGTH_LONG).show(); return
        }
        readForm()
        val (_, _, defMb) = VmConfig.defaultsFor(vm.arch)
        val sizeEt = EditText(this).apply { inputType = InputType.TYPE_CLASS_NUMBER; setText(defMb.toString()) }
        AlertDialog.Builder(this)
            .setTitle("Yeni qcow2 disk (MB)")
            .setMessage("qcow2 dosyası yer kapladıkça büyür; başta birkaç yüz KB'tır.")
            .setView(LinearLayout(this).apply { setPadding(48, 0, 48, 0); addView(sizeEt, MATCH_PARENT, WRAP_CONTENT) })
            .setPositiveButton("Oluştur") { _, _ ->
                val mb = sizeEt.text.toString().toLongOrNull()?.coerceIn(1, 2_000_000) ?: defMb.toLong()
                val safe = vm.name.replace(Regex("[^A-Za-z0-9_-]"), "_")
                var f = File(QemuEnv.imagesDir(this), "$safe.qcow2")
                if (f.exists()) f = File(f.parentFile, "$safe-${System.currentTimeMillis()}.qcow2")
                thread {
                    val r = runCatching { QemuEnv.runTool(this, listOf(img.path, "create", "-f", "qcow2", f.path, "${mb}M")) }
                    runOnUiThread {
                        val (code, out) = r.getOrElse { -1 to (it.message ?: it.toString()) }
                        if (code == 0) {
                            vm.diskPath = f.path; updatePaths()
                            Toast.makeText(this, "Disk oluşturuldu", Toast.LENGTH_SHORT).show()
                        } else {
                            AlertDialog.Builder(this).setTitle("qemu-img hatası").setMessage(out)
                                .setPositiveButton("Tamam", null).show()
                        }
                    }
                }
            }
            .setNegativeButton("Vazgeç", null)
            .show()
    }
}
