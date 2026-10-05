package com.pdg.galaxymicrolaunchpad

import android.content.Context

internal data class ScreenOffConnectionOption(
    val key: String,
    val label: String,
    val timeoutMillis: Long
)

internal const val MinScreenOffTimeoutMinutes = 10
internal const val MaxScreenOffTimeoutMinutes = 12 * 60
internal const val ScreenOffTimeoutStepMinutes = 10
internal const val DefaultScreenOffConnectionOptionKey = "30m"
internal const val IdleBlackoutTimeoutMillis = 2 * 60 * 1_000L
internal const val DefaultIdleBlackoutEnabled = false
internal const val MinDisplayKeepAwakeMinutes = 10
internal const val MaxDisplayKeepAwakeMinutes = 60
internal const val DisplayKeepAwakeStepMinutes = 10
internal const val DefaultDisplayKeepAwakeMinutes = 30
internal const val MinCompletionBlinkDurationSeconds = 1
internal const val MaxCompletionBlinkDurationSeconds = 10
internal const val DefaultCompletionBlinkDurationSeconds = 2
internal const val MinBlackoutClockSizePercent = 50
internal const val MaxBlackoutClockSizePercent = 100
internal const val BlackoutClockSizeStepPercent = 10
internal const val DefaultBlackoutClockSizePercent = 100
internal const val DefaultCodexPhoneTheme = "classic"
internal const val PixelSpaceCodexPhoneTheme = "pixelSpace"
internal const val DotMatrixCodexPhoneTheme = "dotMatrix"
internal const val PixelQuestCodexPhoneTheme = "pixelQuest"
internal const val ControlCabinetCodexPhoneTheme = "controlCabinet"

internal fun normalizeCodexPhoneTheme(theme: String): String = when (theme) {
    PixelSpaceCodexPhoneTheme -> PixelSpaceCodexPhoneTheme
    DotMatrixCodexPhoneTheme -> DotMatrixCodexPhoneTheme
    PixelQuestCodexPhoneTheme -> PixelQuestCodexPhoneTheme
    ControlCabinetCodexPhoneTheme -> ControlCabinetCodexPhoneTheme
    else -> DefaultCodexPhoneTheme
}

internal val screenOffConnectionOptions =
    (MinScreenOffTimeoutMinutes..MaxScreenOffTimeoutMinutes step ScreenOffTimeoutStepMinutes)
        .map { minutes -> ScreenOffConnectionOption("${minutes}m", "${minutes}분", minutes * 60 * 1_000L) } +
        ScreenOffConnectionOption("always", "계속 유지", Long.MAX_VALUE)

internal enum class ScreenOffConnectionAction {
    Resume,
    ScheduleDisconnect
}

internal fun screenOffConnectionAction(isInteractive: Boolean): ScreenOffConnectionAction {
    return if (isInteractive) ScreenOffConnectionAction.Resume else ScreenOffConnectionAction.ScheduleDisconnect
}

internal fun clampCompletionBlinkDurationSeconds(seconds: Int): Int {
    return seconds.coerceIn(MinCompletionBlinkDurationSeconds, MaxCompletionBlinkDurationSeconds)
}

internal fun completionBlinkDurationMillis(seconds: Int): Long {
    return clampCompletionBlinkDurationSeconds(seconds) * 1_000L
}

internal fun clampBlackoutClockSizePercent(percent: Int): Int {
    return percent.coerceIn(MinBlackoutClockSizePercent, MaxBlackoutClockSizePercent)
}

internal class RemoteBridgePreferences(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    var screenOffOptionKey: String
        get() = preferences.getString(KEY_SCREEN_OFF_OPTION, DefaultScreenOffConnectionOptionKey)
            ?.takeIf(::isValidScreenOffOptionKey)
            ?: DefaultScreenOffConnectionOptionKey
        set(value) {
            if (isValidScreenOffOptionKey(value)) {
                preferences.edit().putString(KEY_SCREEN_OFF_OPTION, value).apply()
            }
        }

    var keepRunningInBackground: Boolean
        get() = preferences.getBoolean(KEY_KEEP_RUNNING_IN_BACKGROUND, true)
        set(value) { preferences.edit().putBoolean(KEY_KEEP_RUNNING_IN_BACKGROUND, value).apply() }

    var codexPhoneTheme: String
        get() = normalizeCodexPhoneTheme(
            preferences.getString(KEY_CODEX_PHONE_THEME, DefaultCodexPhoneTheme) ?: DefaultCodexPhoneTheme
        )
        set(value) {
            preferences.edit().putString(KEY_CODEX_PHONE_THEME, normalizeCodexPhoneTheme(value)).apply()
        }

    var macBridgeHost: String
        get() = preferences.getString(KEY_MAC_BRIDGE_HOST, "")?.trim().orEmpty()
        set(value) {
            preferences.edit().putString(KEY_MAC_BRIDGE_HOST, value.trim()).apply()
        }

    var approvalSoundName: String?
        get() = preferences.getString(KEY_APPROVAL_SOUND_NAME, null)
        set(value) {
            preferences.edit().apply {
                if (value.isNullOrBlank()) remove(KEY_APPROVAL_SOUND_NAME)
                else putString(KEY_APPROVAL_SOUND_NAME, value)
            }.apply()
        }

    var approvalSoundOutputTarget: String
        get() = preferences.getString(KEY_APPROVAL_SOUND_OUTPUT_TARGET, "phone")
            ?.takeIf { it in setOf("phone", "mac") } ?: "phone"
        set(value) {
            preferences.edit()
                .putString(KEY_APPROVAL_SOUND_OUTPUT_TARGET, value.takeIf { it in setOf("phone", "mac") } ?: "phone")
                .apply()
        }

    val screenOffTimeoutMillis: Long
        get() = screenOffConnectionOption(screenOffOptionKey).timeoutMillis

    var sleepWindowEnabled: Boolean
        get() = preferences.getBoolean(KEY_SLEEP_WINDOW_ENABLED, false)
        set(value) { preferences.edit().putBoolean(KEY_SLEEP_WINDOW_ENABLED, value).apply() }

    var idleBlackoutEnabled: Boolean
        get() = preferences.getBoolean(KEY_IDLE_BLACKOUT_ENABLED, DefaultIdleBlackoutEnabled)
        set(value) { preferences.edit().putBoolean(KEY_IDLE_BLACKOUT_ENABLED, value).apply() }

    var displayKeepAwakeMinutes: Int
        get() = clampDisplayKeepAwakeMinutes(
            preferences.getInt(KEY_DISPLAY_KEEP_AWAKE_MINUTES, DefaultDisplayKeepAwakeMinutes)
        )
        set(value) {
            preferences.edit()
                .putInt(KEY_DISPLAY_KEEP_AWAKE_MINUTES, clampDisplayKeepAwakeMinutes(value))
                .apply()
        }

    var completionBlinkDurationSeconds: Int
        get() = clampCompletionBlinkDurationSeconds(
            preferences.getInt(KEY_COMPLETION_BLINK_DURATION_SECONDS, DefaultCompletionBlinkDurationSeconds)
        )
        set(value) {
            preferences.edit()
                .putInt(KEY_COMPLETION_BLINK_DURATION_SECONDS, clampCompletionBlinkDurationSeconds(value))
                .apply()
        }

    var blackoutClockSizePercent: Int
        get() = clampBlackoutClockSizePercent(
            preferences.getInt(KEY_BLACKOUT_CLOCK_SIZE_PERCENT, DefaultBlackoutClockSizePercent)
        )
        set(value) {
            preferences.edit()
                .putInt(KEY_BLACKOUT_CLOCK_SIZE_PERCENT, clampBlackoutClockSizePercent(value))
                .apply()
        }

    var sleepWindowStartMinutes: Int
        get() = preferences.getInt(KEY_SLEEP_WINDOW_START, 23 * 60)
        set(value) { preferences.edit().putInt(KEY_SLEEP_WINDOW_START, value.coerceIn(0, 23 * 60 + 59)).apply() }

    var sleepWindowEndMinutes: Int
        get() = preferences.getInt(KEY_SLEEP_WINDOW_END, 7 * 60)
        set(value) { preferences.edit().putInt(KEY_SLEEP_WINDOW_END, value.coerceIn(0, 23 * 60 + 59)).apply() }

    var screenOffStartedAtMillis: Long?
        get() = preferences.getLong(KEY_SCREEN_OFF_STARTED_AT, -1L).takeIf { it >= 0L }
        set(value) {
            preferences.edit().putLong(KEY_SCREEN_OFF_STARTED_AT, value ?: -1L).apply()
        }

    fun isWithinSleepWindow(nowMinutes: Int): Boolean {
        return isWithinSleepWindow(
            enabled = sleepWindowEnabled,
            startMinutes = sleepWindowStartMinutes,
            endMinutes = sleepWindowEndMinutes,
            nowMinutes = nowMinutes
        )
    }

    companion object {
        private const val PREFERENCES_NAME = "remote_bridge_preferences"
        private const val KEY_SCREEN_OFF_OPTION = "screen_off_option"
        private const val KEY_KEEP_RUNNING_IN_BACKGROUND = "keep_running_in_background"
        private const val KEY_CODEX_PHONE_THEME = "codex_phone_theme"
        private const val KEY_MAC_BRIDGE_HOST = "mac_bridge_host"
        private const val KEY_APPROVAL_SOUND_NAME = "approval_sound_name"
        private const val KEY_APPROVAL_SOUND_OUTPUT_TARGET = "approval_sound_output_target"
        private const val KEY_SLEEP_WINDOW_ENABLED = "sleep_window_enabled"
        private const val KEY_IDLE_BLACKOUT_ENABLED = "idle_blackout_enabled"
        private const val KEY_DISPLAY_KEEP_AWAKE_MINUTES = "display_keep_awake_minutes"
        private const val KEY_COMPLETION_BLINK_DURATION_SECONDS = "completion_blink_duration_seconds"
        private const val KEY_BLACKOUT_CLOCK_SIZE_PERCENT = "blackout_clock_size_percent"
        private const val KEY_SLEEP_WINDOW_START = "sleep_window_start"
        private const val KEY_SLEEP_WINDOW_END = "sleep_window_end"
        private const val KEY_SCREEN_OFF_STARTED_AT = "screen_off_started_at"
    }
}

internal fun clampDisplayKeepAwakeMinutes(minutes: Int): Int {
    val clamped = minutes.coerceIn(MinDisplayKeepAwakeMinutes, MaxDisplayKeepAwakeMinutes)
    val stepsFromMinimum = (clamped - MinDisplayKeepAwakeMinutes) / DisplayKeepAwakeStepMinutes
    return MinDisplayKeepAwakeMinutes + stepsFromMinimum * DisplayKeepAwakeStepMinutes
}

internal fun displayKeepAwakeDurationMillis(minutes: Int): Long {
    return clampDisplayKeepAwakeMinutes(minutes) * 60 * 1_000L
}

internal fun shouldKeepScreenAwake(
    nowElapsedMillis: Long,
    lastInteractionElapsedMillis: Long,
    keepAwakeMinutes: Int
): Boolean {
    return nowElapsedMillis - lastInteractionElapsedMillis < displayKeepAwakeDurationMillis(keepAwakeMinutes)
}

internal fun shouldEnterIdleBlackout(
    enabled: Boolean,
    nowElapsedMillis: Long,
    lastInteractionElapsedMillis: Long,
    timeoutMillis: Long = IdleBlackoutTimeoutMillis
): Boolean {
    if (!enabled || timeoutMillis <= 0L) return false
    return nowElapsedMillis - lastInteractionElapsedMillis >= timeoutMillis
}

internal fun screenOffConnectionOption(key: String): ScreenOffConnectionOption {
    if (key == "always") return ScreenOffConnectionOption("always", "계속 유지", Long.MAX_VALUE)
    val minutes = key.removeSuffix("m").toIntOrNull()
        ?.takeIf { it in MinScreenOffTimeoutMinutes..MaxScreenOffTimeoutMinutes && it % ScreenOffTimeoutStepMinutes == 0 }
        ?: DefaultScreenOffConnectionOptionKey.removeSuffix("m").toInt()
    return ScreenOffConnectionOption("${minutes}m", "${minutes}분", minutes * 60 * 1_000L)
}

private fun isValidScreenOffOptionKey(key: String): Boolean {
    return key == "always" || screenOffConnectionOption(key).key == key
}

internal fun isWithinSleepWindow(
    enabled: Boolean,
    startMinutes: Int,
    endMinutes: Int,
    nowMinutes: Int
): Boolean {
    if (!enabled) return false
    return if (startMinutes <= endMinutes) {
        nowMinutes in startMinutes until endMinutes
    } else {
        nowMinutes >= startMinutes || nowMinutes < endMinutes
    }
}
