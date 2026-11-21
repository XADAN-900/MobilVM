package com.mobilvm.app

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import android.widget.Toast

/** VM listesi: oluştur, düzenle, başlat, sil. */
class MainActivity : Activity() {

    private lateinit var adapter: ArrayAdapter<String>
    private lateinit var banner: TextView
    private lateinit var resumeBtn: Button
    private var vms: List<VmConfig> = emptyList()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        banner = TextView(this).apply {
            setPadding(32, 24, 32, 24)
            setBackgroundColor(Color.parseColor("#7a2e00"))
            setTextColor(Color.WHITE)
        }
        val newBtn = Button(this).apply {
            text = "+  Yeni sanal makine"
            setOnClickListener { startActivity(Intent(this@MainActivity, VmEditActivity::class.java)) }
        }
        resumeBtn = Button(this).apply {
            text = "▶  Çalışan VM ekranına dön"
            setOnClickListener { startActivity(Intent(this@MainActivity, DisplayActivity::class.java)) }
        }
        adapter = ArrayAdapter(this, android.R.layout.simple_list_item_1, mutableListOf<String>())
        val list = ListView(this).apply {
            adapter = this@MainActivity.adapter
            setOnItemClickListener { _, _, pos, _ -> showVmMenu(vms.getOrNull(pos)) }
        }

        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(16, 16, 16, 16)
            addView(banner, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(newBtn, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(resumeBtn, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(list, LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
        })

        if (Build.VERSION.SDK_INT >= 33) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    private fun refresh() {
        vms = VmRepository.load(this)
        adapter.clear()
        adapter.addAll(vms.map { vm ->
            val run = if (VmService.runningVmId == vm.id) "  ● çalışıyor" else ""
            "${vm.name}$run\n${vm.arch.label} • ${vm.ramMb} MB • ${vm.cpus} CPU"
        })
        if (vms.isEmpty()) adapter.add("Henüz sanal makine yok.\n'+ Yeni sanal makine' ile başla.")

        resumeBtn.visibility = if (VmService.isRunning) View.VISIBLE else View.GONE

        val missing = buildList {
            if (!QemuEnv.isAvailable(this@MainActivity)) add("QEMU ikilileri (jniLibs)")
            if (!QemuEnv.hasRuntimeAsset(this@MainActivity)) add("assets/qemu-runtime.zip")
        }
        banner.visibility = if (missing.isEmpty()) View.GONE else View.VISIBLE
        banner.text = "Eksik: ${missing.joinToString(", ")}\n" +
            "APK'yı derlemeden önce scripts/fetch_qemu_termux.py çalıştırılmalı (README)."
    }

    private fun showVmMenu(vm: VmConfig?) {
        vm ?: return
        AlertDialog.Builder(this)
            .setTitle(vm.name)
            .setItems(arrayOf("Başlat", "Düzenle", "Sil")) { _, which ->
                when (which) {
                    0 -> startVm(vm)
                    1 -> startActivity(Intent(this, VmEditActivity::class.java).putExtra(VmEditActivity.EXTRA_ID, vm.id))
                    2 -> confirmDelete(vm)
                }
            }
            .show()
    }

    private fun startVm(vm: VmConfig) {
        if (!QemuEnv.isAvailable(this)) {
            Toast.makeText(this, "QEMU bu APK'da yok. README'ye bak.", Toast.LENGTH_LONG).show()
            return
        }
        if (vm.isoPath == null && vm.diskPath == null && vm.floppyPath == null) {
            Toast.makeText(this, "Önce bir ISO, disk ya da disket seç.", Toast.LENGTH_LONG).show()
            return
        }
        if (VmService.isRunning) {
            if (VmService.runningVmId == vm.id) startActivity(Intent(this, DisplayActivity::class.java))
            else Toast.makeText(this, "Aynı anda tek VM çalışabilir.", Toast.LENGTH_LONG).show()
            return
        }
        VmService.start(this, vm.id)
        startActivity(Intent(this, DisplayActivity::class.java))
    }

    private fun confirmDelete(vm: VmConfig) {
        AlertDialog.Builder(this)
            .setTitle("${vm.name} silinsin mi?")
            .setMessage("Sadece VM ayarı silinir; ISO ve disk dosyaları images klasöründe kalır.")
            .setPositiveButton("Sil") { _, _ -> VmRepository.delete(this, vm.id); refresh() }
            .setNegativeButton("Vazgeç", null)
            .show()
    }
}
