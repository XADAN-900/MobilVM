package com.mobilvm.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.text.InputType
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.min

/**
 * VM ekranını çizer, dokunma ve klavyeyi VNC olaylarına çevirir.
 *
 * Dokunma:
 *  - Tek dokunuş        -> sol tık
 *  - Uzun bas (0.5 sn)  -> sağ tık
 *  - Dokun + sürükle    -> sol tuş basılı sürükleme
 *  - İki parmak dokunuş -> sağ tık
 *  - İki parmak kaydır  -> fare tekerleği
 */
class VncView(context: Context) : View(context) {

    var client: RfbClient? = null

    /** Bir tuş vuruşu gönderildikten sonra çağrılır (yapışkan Ctrl/Alt'ı bırakmak için). */
    var afterKey: (() -> Unit)? = null

    /** Ekran tuş çubuğundan basılı tutulan Shift var mı (yumuşak klavye için). */
    private var physShiftDown = false

    private var bitmap: Bitmap? = null
    private val dst = RectF()
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val slop = ViewConfiguration.get(context).scaledTouchSlop

    private var downTime = 0L
    private var downX = 0f
    private var downY = 0f
    private var dragging = false
    private var multi = false
    private var scrolled = false
    private var lastScrollY = 0f

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        setBackgroundColor(Color.BLACK)
    }

    fun refresh() = postInvalidate()

    // ------------------------------------------------------------------ çizim

    override fun onDraw(canvas: Canvas) {
        val cl = client ?: return
        val bmp: Bitmap = synchronized(cl.lock) {
            val w = cl.width
            val h = cl.height
            if (w <= 0 || h <= 0 || cl.pixels.size < w * h) {
                null
            } else {
                val b = bitmap?.takeIf { it.width == w && it.height == h }
                    ?: Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also { bitmap = it }
                b.setPixels(cl.pixels, 0, w, 0, 0, w, h)
                b
            }
        } ?: return
        val scale = min(width.toFloat() / bmp.width, height.toFloat() / bmp.height)
        val dw = bmp.width * scale
        val dh = bmp.height * scale
        dst.set((width - dw) / 2f, (height - dh) / 2f, (width + dw) / 2f, (height + dh) / 2f)
        canvas.drawBitmap(bmp, null, dst, paint)
    }

    // ------------------------------------------------------------------ dokunma

    private fun fbX(x: Float) = ((x - dst.left) / dst.width() * (client?.width ?: 0)).toInt()
    private fun fbY(y: Float) = ((y - dst.top) / dst.height() * (client?.height ?: 0)).toInt()

    private fun pointer(x: Float, y: Float, buttons: Int) = client?.sendPointer(fbX(x), fbY(y), buttons)

    private fun click(x: Float, y: Float, button: Int) {
        pointer(x, y, 0); pointer(x, y, button); pointer(x, y, 0)
    }

    private fun avgY(e: MotionEvent): Float {
        var s = 0f
        for (i in 0 until e.pointerCount) s += e.getY(i)
        return s / e.pointerCount
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (client == null || dst.width() <= 0f) return true
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                requestFocus()
                downTime = e.eventTime; downX = e.x; downY = e.y
                dragging = false; multi = false; scrolled = false
                pointer(e.x, e.y, 0)
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                if (dragging) pointer(e.x, e.y, 0)
                multi = true; dragging = false
                lastScrollY = avgY(e)
            }
            MotionEvent.ACTION_MOVE -> {
                if (multi) {
                    val y = avgY(e)
                    val dy = y - lastScrollY
                    if (abs(dy) > 40f) {
                        val wheel = if (dy < 0) 16 else 8   // parmak yukarı -> aşağı kaydır
                        pointer(downX, downY, wheel); pointer(downX, downY, 0)
                        lastScrollY = y; scrolled = true
                    }
                } else {
                    if (!dragging && hypot(e.x - downX, e.y - downY) > slop) {
                        dragging = true
                        pointer(downX, downY, 1)
                    }
                    if (dragging) pointer(e.x, e.y, 1)
                }
            }
            MotionEvent.ACTION_UP -> {
                val dur = e.eventTime - downTime
                when {
                    multi -> if (!scrolled && dur < 400) click(downX, downY, 4)
                    dragging -> pointer(e.x, e.y, 0)
                    dur > 500 -> click(e.x, e.y, 4)
                    else -> click(e.x, e.y, 1)
                }
                dragging = false
            }
            MotionEvent.ACTION_CANCEL -> {
                if (dragging) pointer(e.x, e.y, 0)
                dragging = false
            }
        }
        return true
    }

    // ------------------------------------------------------------------ klavye

    /** Tek bir karakteri yazar (gerekirse Shift ile sarar). */
    fun typeChar(c: Char) {
        val cl = client ?: return
        val ks = KeyMap.charToKeysym(c)
        val wrap = KeyMap.needsShift(c) && !physShiftDown
        if (wrap) cl.sendKey(KeyMap.SHIFT_L, true)
        cl.tapKey(ks)
        if (wrap) cl.sendKey(KeyMap.SHIFT_L, false)
        afterKey?.invoke()
    }

    override fun onCheckIsTextEditor() = true

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        // TYPE_NULL: klavye harfleri tek tek KeyEvent olarak gönderir (otomatik düzeltme yok)
        outAttrs.inputType = InputType.TYPE_NULL
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_FLAG_NO_FULLSCREEN
        return object : BaseInputConnection(this, false) {
            override fun commitText(text: CharSequence, newCursorPosition: Int): Boolean {
                text.forEach { typeChar(it) }
                return true
            }

            override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
                repeat(beforeLength) { client?.tapKey(KeyMap.BACKSPACE) }
                repeat(afterLength) { client?.tapKey(KeyMap.DELETE) }
                return true
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent) = handleKey(event, true) || super.onKeyDown(keyCode, event)

    override fun onKeyUp(keyCode: Int, event: KeyEvent) = handleKey(event, false) || super.onKeyUp(keyCode, event)

    override fun onKeyMultiple(keyCode: Int, repeatCount: Int, event: KeyEvent): Boolean {
        val chars = event.characters ?: return super.onKeyMultiple(keyCode, repeatCount, event)
        chars.forEach { typeChar(it) }
        return true
    }

    private fun handleKey(e: KeyEvent, down: Boolean): Boolean {
        val cl = client ?: return false
        when (e.keyCode) {
            KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_VOLUME_UP,
            KeyEvent.KEYCODE_VOLUME_DOWN, KeyEvent.KEYCODE_POWER -> return false
        }
        if (e.keyCode == KeyEvent.KEYCODE_SHIFT_LEFT || e.keyCode == KeyEvent.KEYCODE_SHIFT_RIGHT) {
            physShiftDown = down
        }
        KeyMap.specialKeysym(e.keyCode)?.let {
            cl.sendKey(it, down)
            if (!down && e.keyCode !in KeyMap.modifierCodes) afterKey?.invoke()
            return true
        }

        // Karakter tuşları: basışta tam vuruş gönder (yumuşak klavyeler up olayını güvenilir göndermez)
        val c = KeyMap.charOf(e) ?: return false
        if (down) typeChar(c)
        return true
    }
}
