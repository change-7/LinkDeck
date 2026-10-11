package com.pdg.galaxymicrolaunchpad

import android.content.Context
import android.media.AudioAttributes
import android.os.VibrationEffect
import android.os.Vibrator

internal enum class AlertVibrationPattern(val title: String, val timings: LongArray) {
    OFF("끄기", longArrayOf()),
    SHORT("짧게 한 번", longArrayOf(0, 100)),
    DOUBLE("짧게 두 번", longArrayOf(0, 100, 150, 100)),
    TRIPLE("짧게 세 번", longArrayOf(0, 100, 150, 100, 150, 100)),
    LONG("길게 한 번", longArrayOf(0, 600)),
    SHORT_LONG("짧게 · 길게", longArrayOf(0, 100, 200, 500)),
    LONG_DOUBLE("길게 두 번", longArrayOf(0, 450, 250, 450))
}

internal class PhoneAlertVibration(private val context: Context) {
    private val preferences = context.getSharedPreferences("phone_alert_vibration", Context.MODE_PRIVATE)

    fun selected(approval: Boolean): AlertVibrationPattern {
        val default = if (approval) AlertVibrationPattern.SHORT_LONG else AlertVibrationPattern.DOUBLE
        return AlertVibrationPattern.entries.firstOrNull {
            it.name == preferences.getString(key(approval), default.name)
        } ?: default
    }

    fun save(approval: Boolean, pattern: AlertVibrationPattern) {
        preferences.edit().putString(key(approval), pattern.name).apply()
    }

    fun play(pattern: AlertVibrationPattern) {
        if (pattern == AlertVibrationPattern.OFF) return
        val vibrator = context.getSystemService(Vibrator::class.java) ?: return
        if (!vibrator.hasVibrator()) return
        vibrator.vibrate(VibrationEffect.createWaveform(pattern.timings, -1), AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION).build())
    }

    fun notify(approval: Boolean) = play(selected(approval))

    private fun key(approval: Boolean) = if (approval) "approval" else "completion"
}
