package com.pdg.galaxymicrolaunchpad

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import org.json.JSONObject

/**
 * Optional usage fields are update-like values on the bridge wire. Swift's
 * Codable encoder omits nil optionals, so an absent field must not erase a
 * value that was received in an earlier state snapshot. Only an explicit
 * JSON null clears the cached value.
 */
internal fun mergeRemoteUsageInt(state: JSONObject, key: String, current: Int?): Int? {
    return mergeRemoteUsageInt(
        fieldPresent = state.has(key),
        fieldIsNull = state.isNull(key),
        fieldValue = state.optInt(key),
        current = current
    )
}

internal fun mergeRemoteUsageInt(
    fieldPresent: Boolean,
    fieldIsNull: Boolean,
    fieldValue: Int?,
    current: Int?
): Int? {
    if (!fieldPresent) return current
    if (fieldIsNull) return null
    return fieldValue
}

internal fun mergeRemoteUsageDouble(state: JSONObject, key: String, current: Double?): Double? {
    if (!state.has(key)) return current
    if (state.isNull(key)) return null
    return state.optDouble(key)
}

internal fun normalizeCompletionSoundVolumePercent(value: Int): Float =
    value.coerceIn(0, 100) / 100f

internal fun parseRemoteApproval(state: JSONObject): RemoteApproval? {
    val approval = state.optJSONObject("approval") ?: return null
    return RemoteApproval(
        title = approval.optString("title", "Codex 승인 필요"),
        detail = approval.optString("detail", "계속 진행하려면 확인이 필요합니다."),
        requestID = approval.optInt("requestID").takeIf { approval.has("requestID") },
        requestKey = approval.optString("requestKey").takeIf { approval.has("requestKey") },
        source = approval.optString("source", "appServer"),
        canRespond = approval.optBoolean("canRespond", true)
    )
}

internal data class DecodedSmartphoneIcon(
    val encodedData: String,
    val image: ImageBitmap
)

internal fun parseSmartphonePages(
    state: JSONObject,
    iconBitmapCache: MutableMap<String, DecodedSmartphoneIcon> = mutableMapOf(),
    iconAssets: JSONObject? = null
): List<ButtonPage>? {
    val pageArray = state.optJSONArray("smartphonePages") ?: return null
    val parsedPages = buildList {
        for (pageIndex in 0 until pageArray.length()) {
            val pageObject = pageArray.optJSONObject(pageIndex) ?: continue
            val buttonArray = pageObject.optJSONArray("buttons") ?: continue
            val buttons = buildList {
                for (buttonIndex in 0 until buttonArray.length()) {
                    val buttonObject = buttonArray.optJSONObject(buttonIndex) ?: continue
                    val title = smartphoneButtonTitle(buttonObject)
                    val isPlaceholder = isSmartphoneButtonPlaceholder(title)
                    val buttonID = buttonObject.optString("id", "smartphone_page_${pageIndex}_button_${buttonIndex}")
                    val buttonUsesSecondAction = buttonObject.optJSONObject("secondAction") != null &&
                        buttonObject.optBoolean("isSecondActionActive", false)
                    val activeButtonSymbol = smartphoneIconSymbol(buttonObject)
                    val folderActions = buildList {
                        val shortcutArray = buttonObject.optJSONArray("folderShortcuts") ?: return@buildList
                        for (shortcutIndex in 0 until shortcutArray.length()) {
                            val shortcutObject = shortcutArray.optJSONObject(shortcutIndex) ?: continue
                            val shortcutTitle = smartphoneButtonTitle(shortcutObject)
                            val shortcutID = shortcutObject.optString(
                                "id",
                                "${buttonID}_folder_$shortcutIndex"
                            )
                            val shortcutUsesSecondAction = shortcutObject.optJSONObject("secondAction") != null &&
                                shortcutObject.optBoolean("isSecondActionActive", false)
                            val activeShortcutSymbol = smartphoneIconSymbol(shortcutObject)
                            val iconBitmap = if (isSmartphoneButtonPlaceholder(shortcutTitle)) {
                                null
                            } else {
                                parseSmartphoneIconAsset(state, shortcutID, iconBitmapCache, iconAssets, shortcutUsesSecondAction)
                            }
                            add(
                                ControlAction(
                                    label = shortcutTitle,
                                    icon = iconForSymbol(activeShortcutSymbol),
                                    command = "smartphoneButton",
                                    accent = Color.White,
                                    id = shortcutID,
                                    iconBitmap = iconBitmap,
                                    isPlaceholder = isSmartphoneButtonPlaceholder(shortcutTitle),
                                    isIconless = isIconlessSymbol(activeShortcutSymbol) && iconBitmap == null
                                ).let { parseSmartphonePressActions(shortcutObject, it) }
                            )
                        }
                    }
                    add(
                        ControlAction(
                            label = title,
                            icon = iconForSymbol(activeButtonSymbol),
                            command = "smartphoneButton",
                            accent = Color.White,
                            id = buttonID,
                            folderActions = folderActions,
                            iconBitmap = if (isPlaceholder) null else parseSmartphoneIconAsset(
                                state,
                                buttonID,
                                iconBitmapCache,
                                iconAssets,
                                buttonUsesSecondAction
                            ),
                            isPlaceholder = isPlaceholder,
                            isIconless = isIconlessSymbol(activeButtonSymbol)
                        ).let { parseSmartphonePressActions(buttonObject, it) }
                    )
                }
            }
            if (buttons.isNotEmpty()) {
                add(
                    ButtonPage(
                        id = pageObject.optString("id", "smartphone_page_${pageIndex}"),
                        label = pageObject.optString("name", "PAGE ${String.format("%02d", pageIndex + 1)}"),
                        actions = buttons
                    )
                )
            }
        }
    }
    return parsedPages.takeIf { it.isNotEmpty() }
}

internal fun isSmartphoneButtonPlaceholder(title: String): Boolean = title.isBlank()

private fun smartphoneButtonTitle(button: JSONObject): String {
    val isSecondActionActive = button.optJSONObject("secondAction") != null &&
        button.optBoolean("isSecondActionActive", false)
    val secondTitle = button.optString("secondTitle", "")
    return if (isSecondActionActive && secondTitle.isNotBlank()) secondTitle else button.optString("title", "")
}

private fun parseSmartphonePressActions(button: JSONObject, base: ControlAction): ControlAction {
    val legacyLongPress = !button.has("longPressAction") && button.optBoolean("requiresLongPress", false)
    val shortAction = if (legacyLongPress) null else button.optJSONObject("action")
    val longAction = if (legacyLongPress) button.optJSONObject("action") else button.optJSONObject("longPressAction")
    val secondAction = button.optJSONObject("secondAction")
    val isSecondActionActive = secondAction != null && button.optBoolean("isSecondActionActive", false)
    val primaryActionKind = shortAction?.optString("kind", "none") ?: "none"
    val secondActionKind = secondAction?.optString("kind", "none")
    fun configuredAction(action: JSONObject?, command: String): ControlAction = base.copy(
        command = command,
        actionKind = action?.optString("kind", "none") ?: "none",
        actionValue = action?.optString("value", "") ?: "",
        targetAppBundleIdentifier = action?.optString("targetAppBundleIdentifier", "") ?: "",
        launchTargetAppIfNeeded = action?.optBoolean("launchTargetAppIfNeeded", true) ?: true
    )
    val activeShortAction = resolveSmartphoneShortPressAction(shortAction, secondAction, isSecondActionActive)
    return configuredAction(activeShortAction, "smartphoneButton").copy(
        hasSecondAction = secondAction != null,
        isSecondActionActive = isSecondActionActive,
        nextActionKind = if (secondAction == null) null else resolveSmartphoneShortPressAction(
            primaryActionKind,
            secondActionKind,
            !isSecondActionActive
        ),
        longPressAction = longAction?.takeIf { it.optString("kind", "none") != "none" }
            ?.let { configuredAction(it, "smartphoneButtonLongPress") }
    )
}

internal fun <T> resolveSmartphoneShortPressAction(
    primaryAction: T?,
    secondAction: T?,
    isSecondActionActive: Boolean
): T? = if (secondAction != null && isSecondActionActive) secondAction else primaryAction

private fun smartphoneIconSymbol(button: JSONObject): String {
    val isSecondActionActive = button.optJSONObject("secondAction") != null &&
        button.optBoolean("isSecondActionActive", false)
    return if (isSecondActionActive && button.has("secondSymbol")) {
        button.optString("secondSymbol", "")
    } else {
        button.optString("symbol", "")
    }
}

private fun parseSmartphoneIconAsset(
    state: JSONObject,
    buttonID: String,
    iconBitmapCache: MutableMap<String, DecodedSmartphoneIcon>,
    iconAssetsOverride: JSONObject?,
    isSecondActionActive: Boolean
): ImageBitmap? {
    val assets = iconAssetsOverride ?: state.optJSONObject("smartphoneIconAssets")
    val stateKey = "${buttonID}__${if (isSecondActionActive) "B" else "A"}"
    val asset = assets?.optJSONObject(stateKey) ?: assets?.optJSONObject(buttonID) ?: return null
    if (asset.optString("mimeType", "image/png") != "image/png") return null
    val encoded = asset.optString("data", "")
    if (encoded.isEmpty()) return null
    iconBitmapCache[buttonID]?.takeIf { it.encodedData == encoded }?.let { return it.image }
    val bytes = runCatching { Base64.decode(encoded, Base64.DEFAULT) }.getOrNull() ?: return null
    val image = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() ?: return null
    iconBitmapCache[buttonID] = DecodedSmartphoneIcon(encodedData = encoded, image = image)
    return image
}

internal fun normalizeRemoteActivity(rawActivity: String): String {
    return when (rawActivity.trim().lowercase(java.util.Locale.ROOT)) {
        "working", "work", "in_progress", "in-progress", "inprogress", "processing", "executing", "active", "busy" -> "running"
        "waiting", "waiting_for_approval", "waiting-for-approval", "waitingforapproval" -> "waitingForApproval"
        "complete", "done", "finished" -> "completed"
        "error", "errored" -> "failed"
        "" -> "idle"
        else -> rawActivity.trim().lowercase(java.util.Locale.ROOT)
    }
}

internal enum class CodexRevealReason {
    Running,
    Completion,
    Approval,
    Explicit
}

internal fun shouldAutoRevealCodexPage(
    reason: CodexRevealReason,
    nowElapsedMillis: Long = Long.MAX_VALUE,
    suppressUntilElapsedMillis: Long = 0L
): Boolean {
    if (reason == CodexRevealReason.Running || reason == CodexRevealReason.Completion) return false
    return nowElapsedMillis >= suppressUntilElapsedMillis
}

internal fun shouldBlinkCompletionHeader(reason: CodexRevealReason): Boolean {
    return reason == CodexRevealReason.Completion
}

internal fun shouldShowCodexWorkingStatus(activeSessionCount: Int): Boolean {
    return activeSessionCount > 0
}

internal fun shouldWakeForCodexApproval(
    previousApproval: RemoteApproval?,
    currentApproval: RemoteApproval?
): Boolean {
    return currentApproval != null && previousApproval != currentApproval
}

internal fun shouldRevealCodex(
    previousActivity: String?,
    currentActivity: String,
    previousCompletionEventId: Int? = null,
    currentCompletionEventId: Int? = null
): Boolean {
    val activeActivities = setOf("running", "completed", "waitingForApproval")
    val enteringRunning = currentActivity == "running"
        && previousActivity !in setOf("running", "waitingForApproval")
    return enteringRunning
        || currentActivity in activeActivities
        && previousActivity == null
        || currentActivity in setOf("completed", "waitingForApproval") && previousActivity != currentActivity
        || previousCompletionEventId != null
        && currentCompletionEventId != null
        && currentCompletionEventId > previousCompletionEventId
}

/**
 * A reconnect can replay the same active state that was already visible before
 * the socket dropped. In that case the activity value does not transition, but
 * the phone still needs to return to the Codex page so its working motion is
 * visible again.
 */
internal fun shouldRevealCodexAfterReconnect(forceReveal: Boolean, currentActivity: String): Boolean {
    if (!forceReveal) return false
    return normalizeRemoteActivity(currentActivity) in setOf("running", "waitingForApproval", "completed")
}

internal fun isCodexCompletionEvent(
    previousActivity: String?,
    currentActivity: String,
    previousCompletionEventId: Int?,
    currentCompletionEventId: Int?
): Boolean {
    val enteredCompleted = currentActivity == "completed" && previousActivity != "completed"
    val completionCounterAdvanced = previousCompletionEventId != null
        && currentCompletionEventId != null
        && currentCompletionEventId > previousCompletionEventId
    return enteredCompleted || completionCounterAdvanced
}

internal fun shouldPlayCodexCompletionSound(
    previousActivity: String?,
    currentActivity: String,
    previousCompletionEventId: Int?,
    currentCompletionEventId: Int?,
    outputTarget: String = "phone"
): Boolean {
    if (previousActivity == null || outputTarget != "phone") return false
    return isCodexCompletionEvent(
        previousActivity = normalizeRemoteActivity(previousActivity),
        currentActivity = normalizeRemoteActivity(currentActivity),
        previousCompletionEventId = previousCompletionEventId,
        currentCompletionEventId = currentCompletionEventId
    )
}

internal fun codexHeaderPulseAlpha(activity: String, progress: Float): Float {
    if (normalizeRemoteActivity(activity) != "running") return 1f
    return 0.58f + progress.coerceIn(0f, 1f) * 0.42f
}

internal fun blackoutIndicatorAlpha(isCodexWorking: Boolean, progress: Float): Float {
    if (!isCodexWorking) return 1f
    return 0.18f + progress.coerceIn(0f, 1f) * 0.82f
}
