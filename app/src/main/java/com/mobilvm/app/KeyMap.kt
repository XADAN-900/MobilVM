package com.mobilvm.app

import android.view.KeyCharacterMap
import android.view.KeyEvent

/** Android tuş kodları / karakterler -> X11 keysym (VNC'nin kullandığı). */
object KeyMap {
    const val SHIFT_L = 0xffe1
    const val CTRL_L = 0xffe3
    const val ALT_L = 0xffe9
    const val SUPER_L = 0xffeb
    const val ESC = 0xff1b
    const val TAB = 0xff09
    const val ENTER = 0xff0d
    const val BACKSPACE = 0xff08
    const val DELETE = 0xffff
    const val LEFT = 0xff51
    const val UP = 0xff52
    const val RIGHT = 0xff53
    const val DOWN = 0xff54
    const val HOME = 0xff50
    const val END = 0xff57
    const val PAGE_UP = 0xff55
    const val PAGE_DOWN = 0xff56
    const val F1 = 0xffbe

    private val special: Map<Int, Int> = buildMap {
        put(KeyEvent.KEYCODE_ENTER, ENTER)
        put(KeyEvent.KEYCODE_NUMPAD_ENTER, 0xff8d)
        put(KeyEvent.KEYCODE_DEL, BACKSPACE)
        put(KeyEvent.KEYCODE_FORWARD_DEL, DELETE)
        put(KeyEvent.KEYCODE_TAB, TAB)
        put(KeyEvent.KEYCODE_ESCAPE, ESC)
        put(KeyEvent.KEYCODE_SPACE, 0x20)
        put(KeyEvent.KEYCODE_DPAD_LEFT, LEFT)
        put(KeyEvent.KEYCODE_DPAD_UP, UP)
        put(KeyEvent.KEYCODE_DPAD_RIGHT, RIGHT)
        put(KeyEvent.KEYCODE_DPAD_DOWN, DOWN)
        put(KeyEvent.KEYCODE_MOVE_HOME, HOME)
        put(KeyEvent.KEYCODE_MOVE_END, END)
        put(KeyEvent.KEYCODE_PAGE_UP, PAGE_UP)
        put(KeyEvent.KEYCODE_PAGE_DOWN, PAGE_DOWN)
        put(KeyEvent.KEYCODE_INSERT, 0xff63)
        put(KeyEvent.KEYCODE_SHIFT_LEFT, SHIFT_L)
        put(KeyEvent.KEYCODE_SHIFT_RIGHT, 0xffe2)
        put(KeyEvent.KEYCODE_CTRL_LEFT, CTRL_L)
        put(KeyEvent.KEYCODE_CTRL_RIGHT, 0xffe4)
        put(KeyEvent.KEYCODE_ALT_LEFT, ALT_L)
        put(KeyEvent.KEYCODE_ALT_RIGHT, 0xfe03) // AltGr
        put(KeyEvent.KEYCODE_META_LEFT, SUPER_L)
        put(KeyEvent.KEYCODE_META_RIGHT, 0xffec)
        put(KeyEvent.KEYCODE_CAPS_LOCK, 0xffe5)
        put(KeyEvent.KEYCODE_NUM_LOCK, 0xff7f)
        put(KeyEvent.KEYCODE_SCROLL_LOCK, 0xff14)
        put(KeyEvent.KEYCODE_SYSRQ, 0xff61)
        put(KeyEvent.KEYCODE_BREAK, 0xff13)
        for (i in 0 until 12) put(KeyEvent.KEYCODE_F1 + i, F1 + i)
    }

    val modifierCodes = setOf(
        KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_SHIFT_RIGHT,
        KeyEvent.KEYCODE_CTRL_LEFT, KeyEvent.KEYCODE_CTRL_RIGHT,
        KeyEvent.KEYCODE_ALT_LEFT, KeyEvent.KEYCODE_ALT_RIGHT,
        KeyEvent.KEYCODE_META_LEFT, KeyEvent.KEYCODE_META_RIGHT,
    )

    fun specialKeysym(keyCode: Int): Int? = special[keyCode]

    /** Karakter üreten tuşun karakteri (Ctrl/Alt etkisi olmadan), yoksa null. */
    fun charOf(e: KeyEvent): Char? {
        val uc = e.getUnicodeChar(e.metaState and (KeyEvent.META_SHIFT_MASK or KeyEvent.META_CAPS_LOCK_ON))
        if (uc == 0 || (uc and KeyCharacterMap.COMBINING_ACCENT) != 0 || uc > 0xffff) return null
        return uc.toChar()
    }

    fun charToKeysym(c: Char): Int = when {
        c == '\n' -> ENTER
        c == '\b' -> BACKSPACE
        c == '\t' -> TAB
        c.code in 0x20..0x7e || c.code in 0xa0..0xff -> c.code   // Latin-1 doğrudan
        else -> 0x01000000 or c.code                             // Unicode keysym (ş, ğ, ı ...)
    }

    /** ABD klavyesinde Shift gerektiren karakterler. */
    fun needsShift(c: Char) = c.isUpperCase() || c in "~!@#$%^&*()_+{}|:\"<>?"
}
