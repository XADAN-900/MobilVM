package com.mobilvm.app

import android.app.Activity
import android.app.AlertDialog
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** VM ekranı + alt tuş çubuğu (Esc, Ctrl, Alt, F tuşları, oklar...). */
class DisplayActivity : Activity(), RfbClient.Listener {

    private lateinit var vnc: VncView
    private lateinit var status: TextView
    private var client: RfbClient? = null
    private var ctrlBtn: Button? = null
    private var altBtn: Button? = null
    private var ctrlOn = false
    private var altOn = false
    private var keyboardShown = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        vnc = VncView(this)
        vnc.afterKey = { runOnUiThread { releaseStickyMods() } }
        status = TextView(this).apply {
            setTextColor(Color.WHITE); setPadding(24, 24, 24, 24); text = "VM başlatılıyor…"
        }
        val frame = FrameLayout(this).apply {
            addView(vnc, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
            addView(status, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.TOP or Gravity.START))
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
            addView(frame, LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
            addView(buildKeyBar(), LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
        setContentView(root)
        connect()
    }

    private fun connect() {
        client?.stop()
        status.text = "VM ekranına bağlanılıyor…"
        status.visibility = View.VISIBLE
        client = RfbClient("127.0.0.1", QemuCommand.VNC_PORT, this).also {
            vnc.client = it
            it.start()
        }
    }

    // ------------------------------------------------------------ tuş çubuğu

    private fun buildKeyBar(): HorizontalScrollView {
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        fun btn(label: String, action: (Button) -> Unit): Button = Button(this).apply {
            text = label
            isAllCaps = false
            minWidth = 0; minimumWidth = 0
            setPadding(28, 0, 28, 0)
            setOnClickListener { action(this) }
            row.addView(this, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        }
        fun key(label: String, sym: Int) = btn(label) { tap(sym) }

        btn("⌨") { toggleKeyboard() }
        key("Esc", KeyMap.ESC)
        key("Tab", KeyMap.TAB)
        ctrlBtn = btn("Ctrl") { ctrlOn = !ctrlOn; setMod(KeyMap.CTRL_L, ctrlOn, it) }
        altBtn = btn("Alt") { altOn = !altOn; setMod(KeyMap.ALT_L, altOn, it) }
        key("Win", KeyMap.SUPER_L)
        key("Del", KeyMap.DELETE)
        btn("Ctrl+Alt+Del") {
            client?.run {
                sendKey(KeyMap.CTRL_L, true); sendKey(KeyMap.ALT_L, true); tapKey(KeyMap.DELETE)
                sendKey(KeyMap.ALT_L, false); sendKey(KeyMap.CTRL_L, false)
            }
        }
        key("←", KeyMap.LEFT); key("↑", KeyMap.UP); key("↓", KeyMap.DOWN); key("→", KeyMap.RIGHT)
        key("Home", KeyMap.HOME); key("End", KeyMap.END)
        key("PgUp", KeyMap.PAGE_UP); key("PgDn", KeyMap.PAGE_DOWN)
        for (i in 0 until 12) key("F${i + 1}", KeyMap.F1 + i)
        btn("Günlük") { showLog() }
        btn("Kapat") { confirmStop() }

        return HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(row)
        }
    }

    private fun tap(sym: Int) {
        client?.tapKey(sym)
        releaseStickyMods()
    }

    /** Ctrl/Alt "yapışkan": bir sonraki tuştan sonra bırakılır. */
    private fun releaseStickyMods() {
        if (ctrlOn) { ctrlOn = false; ctrlBtn?.let { setMod(KeyMap.CTRL_L, false, it) } }
        if (altOn) { altOn = false; altBtn?.let { setMod(KeyMap.ALT_L, false, it) } }
    }

    private fun setMod(sym: Int, on: Boolean, b: Button) {
        client?.sendKey(sym, on)
        b.alpha = if (on) 1f else 0.85f
        b.setTextColor(if (on) Color.YELLOW else Color.WHITE)
    }

    private fun toggleKeyboard() {
        val imm = getSystemService(InputMethodManager::class.java)
        vnc.requestFocus()
        keyboardShown = if (keyboardShown) {
            imm.hideSoftInputFromWindow(vnc.windowToken, 0); false
        } else {
            imm.showSoftInput(vnc, InputMethodManager.SHOW_IMPLICIT); true
        }
    }

    // ------------------------------------------------------------ RFB olayları

    override fun onConnected(width: Int, height: Int) = runOnUiThread {
        status.visibility = View.GONE
        vnc.requestFocus()
        vnc.refresh()
    }

    override fun onFrame() {
        vnc.refresh()
    }

    override fun onDisconnected(error: String?) = runOnUiThread {
        if (isFinishing || isDestroyed) return@runOnUiThread
        val running = VmService.isRunning
        val msg = buildString {
            append(if (running) "Ekran bağlantısı koptu." else "Sanal makine kapandı.")
            error?.let { append("\n\n").append(it) }
            append("\n\nSon günlük:\n").append(VmService.log().takeLast(1500))
        }
        AlertDialog.Builder(this)
            .setTitle("MobilVM")
            .setMessage(msg)
            .setCancelable(false)
            .apply { if (running) setPositiveButton("Tekrar bağlan") { _, _ -> connect() } }
            .setNegativeButton("Çık") { _, _ -> finish() }
            .show()
    }

    // ------------------------------------------------------------ diğer

    private fun showLog() {
        val tv = TextView(this).apply {
            text = VmService.log().ifEmpty { "(boş)" }
            setTextIsSelectable(true); textSize = 11f; setPadding(32, 32, 32, 32)
        }
        AlertDialog.Builder(this)
            .setTitle("QEMU günlüğü")
            .setView(ScrollView(this).apply { addView(tv) })
            .setPositiveButton("Tamam", null)
            .show()
    }

    private fun confirmStop() {
        AlertDialog.Builder(this)
            .setTitle("Sanal makineyi kapat?")
            .setMessage("Kaydedilmemiş veriler kaybolabilir. Önce misafir sistemi içinden kapatman daha güvenli.")
            .setPositiveButton("Kapat") { _, _ -> VmService.stop(); finish() }
            .setNegativeButton("Vazgeç", null)
            .show()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        AlertDialog.Builder(this)
            .setItems(arrayOf("Arka plana al (VM çalışmaya devam eder)", "Sanal makineyi kapat", "Vazgeç")) { _, which ->
                when (which) {
                    0 -> finish()
                    1 -> confirmStop()
                }
            }
            .show()
    }

    override fun onDestroy() {
        client?.stop()
        client = null
        super.onDestroy()
    }
}
