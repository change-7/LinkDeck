package com.pdg.galaxymicrolaunchpad

import android.Manifest
import android.graphics.BitmapFactory
import android.app.TimePickerDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Base64
import java.io.File
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.setContent
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.content.ContextCompat
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.LightMode
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.MicOff
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material.icons.outlined.VolumeUp
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.ripple
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.changedToDown
import androidx.compose.foundation.clickable
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import android.view.WindowManager
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlinx.coroutines.delay

private val Black = Color(0xFF050505)
private val Tile = Color(0xFF191919)
private val Line = Color(0xFF777777)
private val TextPrimary = Color(0xFFF2F2F2)
private val TextMuted = Color(0xFF9A9A9A)
private val Green = Color(0xFF32E875)
private const val LongPressVibrationDurationMillis = 40L
private val Red = Color(0xFFFF3B30)
private val GaugeTrack = Color(0xFF303030)
private val GaugeMid = Color(0xFFFFB020)
private val GaugeCool = Color(0xFF22C7A8)
private val GaugeHigh = Color(0xFF3B82F6)
private val PixelSpaceMint = Color(0xFF58F2D0)
private val PixelSpaceViolet = Color(0xFFB18BFF)
private val DotMatrixBackgroundColor = Color(0xFF080A14)
private val DotMatrixGridColor = Color(0xFF293047)
private val DotMatrixCyan = Color(0xFF62E0FF)
private val DotMatrixLime = Color(0xFFC4FF6C)
private val DotMatrixPink = Color(0xFFFF79C6)
private val DotMatrixPurple = Color(0xFFB79CFF)
private val PixelQuestBackground = Color(0xFF17111F)
private val PixelQuestPanel = Color(0xFF241B2C)
private val PixelQuestFrame = Color(0xFF74523B)
private val PixelQuestGold = Color(0xFFFFC857)
private val PixelQuestCoral = Color(0xFFFF795E)
private val PixelQuestMint = Color(0xFFA7E06E)
private val PixelQuestMuted = Color(0xFFB6A88D)
private val CabinetAmber = Color(0xFFFFBC54)
private val CabinetPanel = Color(0xFF15191B)
private val CabinetFrame = Color(0xFF535B60)
private const val HorizontalSwipeCommitDistanceDp = 32f
private const val DefaultHorizontalSwipeCommitDistancePx = HorizontalSwipeCommitDistanceDp
private const val DefaultVerticalSwipeCommitDistancePx = 80f
private const val AppPageTransitionDurationMillis = 150
private const val AppPageFadeDurationMillis = 100
private const val ButtonActionRevealSuppressionMillis = 2_500L
private val ButtonTileIconSize = 42.dp
private val ButtonTileContentGap = 4.dp
private val ButtonTileLabelFontSize = 14.sp
private val PortraitButtonTileIconSize = 28.dp
private val PortraitButtonTileLabelFontSize = 11.sp
private val UsagePanelHorizontalPadding = 10.dp
private val UsagePanelVerticalPadding = 8.dp
private val UsagePanelContentGap = 6.dp
private val PortraitUsageResetFontSize = 16.sp
private val LandscapeUsageResetFontSize = 14.sp
private val MainContentTopPadding = 0.dp

private data class PhoneSkinStyle(
    val accent: Color,
    val panel: Color,
    val frame: Color,
    val cornerRadius: androidx.compose.ui.unit.Dp,
    val borderWidth: androidx.compose.ui.unit.Dp,
    val themed: Boolean = true
)

private fun phoneSkinStyle(theme: String): PhoneSkinStyle = when (theme) {
    PixelSpaceCodexPhoneTheme -> PhoneSkinStyle(PixelSpaceMint, Color(0xFF101B2D), PixelSpaceMint, 0.dp, 2.dp)
    DotMatrixCodexPhoneTheme -> PhoneSkinStyle(DotMatrixCyan, DotMatrixBackgroundColor, DotMatrixCyan, 8.dp, 1.dp)
    PixelQuestCodexPhoneTheme -> PhoneSkinStyle(PixelQuestGold, PixelQuestPanel, PixelQuestFrame, 0.dp, 2.dp)
    ControlCabinetCodexPhoneTheme -> PhoneSkinStyle(CabinetAmber, CabinetPanel, CabinetFrame, 3.dp, 1.dp)
    else -> PhoneSkinStyle(Line, Tile, Line, 3.dp, 1.dp, themed = false)
}

internal fun clampUsagePercent(value: Int?): Int? = value?.coerceIn(0, 100)

private enum class AppPage(val label: String) {
    Controls("Buttons"),
    Codex("Codex")
}

internal data class ControlAction(
    val label: String,
    val icon: ImageVector,
    val command: String,
    val accent: Color = TextPrimary,
    val id: String = "",
    val actionKind: String = "none",
    val actionValue: String = "",
    val targetAppBundleIdentifier: String = "",
    val launchTargetAppIfNeeded: Boolean = true,
    val folderActions: List<ControlAction> = emptyList(),
    val iconBitmap: ImageBitmap? = null,
    val isPlaceholder: Boolean = false,
    val isIconless: Boolean = false,
    val longPressAction: ControlAction? = null
)

internal data class ButtonPage(
    val id: String,
    val label: String,
    val actions: List<ControlAction>
)

private val defaultActions = listOf(
    ControlAction("Run", Icons.Outlined.PlayArrow, "run", Green),
    ControlAction("Pause", Icons.Outlined.Pause, "pause"),
    ControlAction("Stop", Icons.Outlined.Stop, "stop", Red),
    ControlAction("Terminal", Icons.Outlined.Terminal, "terminal"),
    ControlAction("Browser", Icons.Outlined.Language, "browser"),
    ControlAction("Files", Icons.Outlined.Folder, "files"),
    ControlAction("Search", Icons.Outlined.Search, "search"),
    ControlAction("Capture", Icons.Outlined.PhotoCamera, "capture"),
    ControlAction("Clipboard", Icons.Outlined.ContentPaste, "clipboard"),
    ControlAction("Music", Icons.Outlined.MusicNote, "music"),
    ControlAction("Volume", Icons.Outlined.VolumeUp, "volume"),
    ControlAction("Focus", Icons.Outlined.DarkMode, "focus"),
    ControlAction("Settings", Icons.Outlined.Settings, "settings"),
    ControlAction("More", Icons.Outlined.MoreHoriz, "more"),
    ControlAction("Run", Icons.Outlined.PlayArrow, "run", Green),
    ControlAction("Stop", Icons.Outlined.Stop, "stop", Red)
)

private val defaultButtonPages = listOf(
    ButtonPage("smartphone_page_0", "PAGE 01", defaultActions),
    ButtonPage(
        "smartphone_page_1",
        "PAGE 02",
        listOf(
            defaultActions[3], defaultActions[4], defaultActions[5], defaultActions[6],
            defaultActions[7], defaultActions[8], defaultActions[9], defaultActions[10],
            defaultActions[11], defaultActions[12], defaultActions[13], defaultActions[3],
            defaultActions[5], defaultActions[6], defaultActions[10], defaultActions[12]
        )
    ),
    ButtonPage(
        "smartphone_page_2",
        "PAGE 03",
        listOf(
            defaultActions[0], defaultActions[1], defaultActions[2], defaultActions[3],
            defaultActions[6], defaultActions[7], defaultActions[4], defaultActions[5],
            defaultActions[8], defaultActions[9], defaultActions[10], defaultActions[11],
            defaultActions[12], defaultActions[13], defaultActions[0], defaultActions[2]
        )
    )
)

internal val buttonPages = defaultButtonPages.mapIndexed { pageIndex, page ->
    page.copy(actions = page.actions.mapIndexed { buttonIndex, action ->
        action.copy(id = "smartphone_page_${pageIndex}_button_${buttonIndex}")
    })
}

class MainActivity : ComponentActivity() {
    private lateinit var remoteBridge: RemoteBridgeClient
    private var completionWakeLock: PowerManager.WakeLock? = null
    private var completionNotificationPlayer: MediaPlayer? = null
    private var isActivityResumed by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        remoteBridge = RemoteBridgeRuntime.client(this)
        remoteBridge.onCodexCompletion = ::wakeForCodexCompletion
        remoteBridge.onCodexRunning = ::wakeForCodexRunning
        remoteBridge.onCodexApproval = ::wakeForCodexApproval
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        setContent { GalaxyMicroLaunchpadApp(remoteBridge, isActivityResumed) }
        if (intent.getBooleanExtra(CodexResetScheduler.EXTRA_REVEAL_CODEX, false)) {
            remoteBridge.requestCodexReveal()
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(CodexResetScheduler.EXTRA_REVEAL_CODEX, false)) {
            remoteBridge.requestCodexReveal()
        }
    }

    override fun onResume() {
        super.onResume()
        isActivityResumed = true
    }

    override fun onStart() {
        super.onStart()
        ContextCompat.startForegroundService(
            this,
            Intent(this, RemoteBridgeService::class.java).setAction(RemoteBridgeService.ACTION_START)
        )
    }

    override fun onStop() {
        if (!RemoteBridgePreferences(this).keepRunningInBackground) {
            stopService(Intent(this, RemoteBridgeService::class.java))
        }
        super.onStop()
    }

    override fun onPause() {
        isActivityResumed = false
        super.onPause()
    }

    override fun onDestroy() {
        remoteBridge.onCodexCompletion = null
        remoteBridge.onCodexRunning = null
        remoteBridge.onCodexApproval = null
        releaseCompletionWakeLock()
        stopCompletionNotificationSound()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun wakeForCodexCompletion(playSound: Boolean) {
        if (playSound) playCompletionNotificationSound()
        wakeScreenForCodex()
    }

    @Suppress("DEPRECATION")
    private fun wakeForCodexRunning() {
        wakeScreenForCodex()
    }

    @Suppress("DEPRECATION")
    private fun wakeForCodexApproval() {
        wakeScreenForCodex()
    }

    @Suppress("DEPRECATION")
    private fun wakeScreenForCodex() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        val powerManager = getSystemService(PowerManager::class.java)
        if (!shouldWakeForCodex(powerManager.isInteractive)) {
            return
        }
        releaseCompletionWakeLock()
        val wakeLock = powerManager.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "$packageName:codex-completion"
        ).apply {
            setReferenceCounted(false)
            acquire(CodexCompletionWakeDurationMillis)
        }
        completionWakeLock = wakeLock
        window.decorView.postDelayed({
            if (wakeLock.isHeld) wakeLock.release()
            if (completionWakeLock === wakeLock) completionWakeLock = null
        }, CodexCompletionWakeDurationMillis + 500L)
    }

    private fun playCompletionNotificationSound() {
        playCompletionNotificationSound(remoteBridge.selectedCompletionSoundFile)
    }

    private fun playCompletionNotificationSound(customFile: File?) {
        stopCompletionNotificationSound()
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val player = if (customFile == null) {
            MediaPlayer.create(this, R.raw.codex_completion_chime, audioAttributes, 0) ?: return
        } else {
            MediaPlayer().apply { setAudioAttributes(audioAttributes) }
        }
        completionNotificationPlayer = player
        val completionVolume = remoteBridge.selectedCompletionSoundVolume
        player.setVolume(completionVolume, completionVolume)
        player.setOnCompletionListener { finishedPlayer ->
            if (completionNotificationPlayer === finishedPlayer) {
                completionNotificationPlayer = null
            }
            finishedPlayer.release()
        }
        player.setOnErrorListener { failedPlayer, _, _ ->
            if (completionNotificationPlayer === failedPlayer) completionNotificationPlayer = null
            failedPlayer.release()
            if (customFile != null) playCompletionNotificationSound(null)
            true
        }
        if (customFile == null) {
            runCatching { player.start() }.onFailure {
                if (completionNotificationPlayer === player) completionNotificationPlayer = null
                player.release()
            }
            return
        }
        player.setOnPreparedListener { preparedPlayer ->
            if (completionNotificationPlayer === preparedPlayer) preparedPlayer.start()
            else preparedPlayer.release()
        }
        runCatching {
            player.setDataSource(customFile.absolutePath)
            player.prepareAsync()
        }.onFailure {
            if (completionNotificationPlayer === player) completionNotificationPlayer = null
            player.release()
            playCompletionNotificationSound(null)
        }
    }

    private fun stopCompletionNotificationSound() {
        completionNotificationPlayer?.let { player ->
            runCatching { player.stop() }
            player.release()
        }
        completionNotificationPlayer = null
    }

    private fun releaseCompletionWakeLock() {
        completionWakeLock?.let { wakeLock ->
            if (wakeLock.isHeld) wakeLock.release()
        }
        completionWakeLock = null
    }

}

@Composable
private fun GalaxyMicroLaunchpadApp(remoteBridge: RemoteBridgeClient, isActivityResumed: Boolean) {
    val context = LocalContext.current
    val microphonePermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, RemoteBridgeService::class.java).setAction(RemoteBridgeService.ACTION_MICROPHONE_START)
            )
        }
    }
    val toggleMicrophone: (Boolean) -> Unit = { enabled ->
        if (!enabled) {
            context.startService(
                Intent(context, RemoteBridgeService::class.java).setAction(RemoteBridgeService.ACTION_MICROPHONE_STOP)
            )
        } else if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, RemoteBridgeService::class.java).setAction(RemoteBridgeService.ACTION_MICROPHONE_START)
            )
        } else {
            microphonePermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
    val view = LocalView.current
    val preferences = remember(context) { RemoteBridgePreferences(context) }
    val isPortrait = LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT
    var page by remember { mutableStateOf(AppPage.Controls) }
    var buttonPageIndex by rememberSaveable { mutableStateOf(0) }
    var openFolderAction by remember { mutableStateOf<ControlAction?>(null) }
    val currentFolderAction = openFolderAction?.let { folder ->
        remoteBridge.smartphonePages.flatMap { it.actions }
            .firstOrNull { it.id == folder.id }
            ?.let { if (folder.command == "smartphoneButtonLongPress") it.longPressAction else it }
            ?.takeIf { it.actionKind == "appFolder" }
    }
    var suppressCodexRevealUntilElapsedMillis by remember { mutableStateOf(0L) }
    var showConnectionSettings by rememberSaveable { mutableStateOf(false) }
    var idleBlackoutEnabled by rememberSaveable { mutableStateOf(preferences.idleBlackoutEnabled) }
    var displayKeepAwakeMinutes by rememberSaveable {
        mutableStateOf(preferences.displayKeepAwakeMinutes)
    }
    var completionBlinkDurationSeconds by rememberSaveable {
        mutableStateOf(preferences.completionBlinkDurationSeconds)
    }
    var blackoutClockSizePercent by rememberSaveable {
        mutableStateOf(preferences.blackoutClockSizePercent)
    }
    var dismissedCompletionEventId by rememberSaveable { mutableStateOf(0) }
    var blackoutVisible by remember { mutableStateOf(false) }
    var screenKeepAwakeExpired by remember { mutableStateOf(false) }
    var lastInteractionElapsedMillis by remember { mutableStateOf(SystemClock.elapsedRealtime()) }
    var lastUserInteractionElapsedMillis by remember { mutableStateOf(lastInteractionElapsedMillis) }
    var localMessage by remember { mutableStateOf("Mac을 찾는 중…") }
    var dismissedApproval by remember { mutableStateOf<RemoteApproval?>(null) }
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
    LaunchedEffect(remoteBridge.pendingApproval) {
        dismissedApproval = null
    }
    LaunchedEffect(isPortrait) {
        if (isPortrait) page = AppPage.Controls
    }
    val markInteraction = {
        val nowElapsedMillis = SystemClock.elapsedRealtime()
        lastInteractionElapsedMillis = nowElapsedMillis
        lastUserInteractionElapsedMillis = nowElapsedMillis
        blackoutVisible = false
        dismissedCompletionEventId = remoteBridge.codexRevealEventId
    }
    val markRemoteActivity = {
        lastInteractionElapsedMillis = SystemClock.elapsedRealtime()
        blackoutVisible = false
    }
    LaunchedEffect(isActivityResumed) {
        if (isActivityResumed) {
            val resumedAtElapsedMillis = SystemClock.elapsedRealtime()
            lastInteractionElapsedMillis = resumedAtElapsedMillis
            lastUserInteractionElapsedMillis = resumedAtElapsedMillis
            blackoutVisible = false
        }
    }
    LaunchedEffect(idleBlackoutEnabled) {
        blackoutVisible = false
        while (true) {
            delay(1_000L)
            if (shouldEnterIdleBlackout(
                    enabled = idleBlackoutEnabled,
                    nowElapsedMillis = SystemClock.elapsedRealtime(),
                    lastInteractionElapsedMillis = lastInteractionElapsedMillis
                )) {
                blackoutVisible = true
            }
        }
    }

    LaunchedEffect(displayKeepAwakeMinutes, lastUserInteractionElapsedMillis) {
        screenKeepAwakeExpired = false
        val remainingMillis = displayKeepAwakeDurationMillis(displayKeepAwakeMinutes) -
            (SystemClock.elapsedRealtime() - lastUserInteractionElapsedMillis)
        if (remainingMillis > 0L) {
            delay(remainingMillis)
        }
        screenKeepAwakeExpired = !shouldKeepScreenAwake(
            nowElapsedMillis = SystemClock.elapsedRealtime(),
            lastInteractionElapsedMillis = lastUserInteractionElapsedMillis,
            keepAwakeMinutes = displayKeepAwakeMinutes
        )
    }

    DisposableEffect(view, screenKeepAwakeExpired) {
        view.keepScreenOn = !screenKeepAwakeExpired
        onDispose {
            view.keepScreenOn = false
        }
    }
    LaunchedEffect(
        isPortrait,
        remoteBridge.codexRevealEventId,
        remoteBridge.codexRevealReason,
        remoteBridge.activity,
        remoteBridge.commandSucceeded,
        remoteBridge.fiveHourRemainingPercent,
        remoteBridge.remainingPercent,
        remoteBridge.connectionState,
        remoteBridge.codexConnected,
        remoteBridge.pendingApproval
    ) {
        if (!isPortrait && remoteBridge.codexRevealEventId > 0
            && shouldAutoRevealCodexPage(
                reason = remoteBridge.codexRevealReason,
                nowElapsedMillis = SystemClock.elapsedRealtime(),
                suppressUntilElapsedMillis = suppressCodexRevealUntilElapsedMillis
            )
        ) {
            page = AppPage.Codex
        }
        if (remoteBridge.codexRevealEventId > 0
            || normalizeRemoteActivity(remoteBridge.activity) != "idle"
            || remoteBridge.commandSucceeded != null
        ) {
            markRemoteActivity()
        }
    }
    val completionEventId = if (
        remoteBridge.codexRevealEventId > dismissedCompletionEventId
            && shouldBlinkCompletionHeader(remoteBridge.codexRevealReason)
    ) {
        remoteBridge.codexRevealEventId
    } else {
        0
    }
    val headerMessage = if (completionEventId > 0) {
        "Codex 작업 완료"
    } else if (remoteBridge.connectionState == RemoteConnectionState.Connected) {
        remoteBridge.message
    } else {
        localMessage
    }
    var horizontalDrag by remember { mutableStateOf(0f) }
    var pageTransitionDirection by remember { mutableStateOf(1) }
    val swipeCommitDistancePx = horizontalSwipeCommitDistancePx(LocalDensity.current.density)
    val currentPage by rememberUpdatedState(page)
    val currentButtonPageIndex by rememberUpdatedState(buttonPageIndex)
    val currentButtonPageCount by rememberUpdatedState(remoteBridge.smartphonePages.size)
    val currentSwipeCommitDistancePx by rememberUpdatedState(swipeCommitDistancePx)

    Surface(color = Black, modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.navigationBars)
                .pointerInput(Unit) {
                    awaitPointerEventScope {
                        while (true) {
                            val event = awaitPointerEvent(PointerEventPass.Initial)
                            if (event.changes.any { it.changedToDown() }) markInteraction()
                        }
                    }
                }
                .pointerInput(isPortrait) {
                    detectHorizontalDragGestures(
                        onHorizontalDrag = { change, dragAmount ->
                            change.consume()
                            horizontalDrag += dragAmount
                        },
                        onDragEnd = {
                            if (isPortrait) {
                                val currentIndex = currentButtonPageIndex
                                val nextIndex = horizontalSwipeTarget(
                                    currentIndex = currentIndex,
                                    pageCount = currentButtonPageCount,
                                    dragDistance = horizontalDrag,
                                    commitDistancePx = currentSwipeCommitDistancePx
                                )
                                if (nextIndex != currentIndex) {
                                    buttonPageIndex = nextIndex
                                    openFolderAction = null
                                }
                            } else {
                                val currentIndex = AppPage.entries.indexOf(currentPage)
                                val nextIndex = horizontalSwipeTarget(
                                    currentIndex = currentIndex,
                                    pageCount = AppPage.entries.size,
                                    dragDistance = horizontalDrag,
                                    commitDistancePx = currentSwipeCommitDistancePx
                                )
                                if (nextIndex != currentIndex) {
                                    pageTransitionDirection = horizontalSwipeTransitionDirection(horizontalDrag)
                                    page = AppPage.entries[nextIndex]
                                }
                            }
                            horizontalDrag = 0f
                        },
                        onDragCancel = {
                            horizontalDrag = 0f
                        }
                    )
                }
            ) {
            if (isPortrait) Spacer(Modifier.height(32.dp))
            Header(
                message = headerMessage,
                messageColor = when (remoteBridge.commandSucceeded) {
                    true -> Green
                    false -> Red
                    null -> TextMuted
                },
                connectionState = remoteBridge.connectionState,
                macSleepMode = remoteBridge.macSleepMode,
                activeSessionCount = remoteBridge.activeSessionCount,
                fiveHourRemaining = remoteBridge.fiveHourRemainingPercent,
                weeklyRemaining = remoteBridge.remainingPercent,
                codexPhoneTheme = remoteBridge.codexPhoneTheme,
                completionEventId = completionEventId,
                completionBlinkDurationMillis = completionBlinkDurationMillis(completionBlinkDurationSeconds),
                onCompletionFlashFinished = { dismissedCompletionEventId = completionEventId }
            )
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
            ) {
                AnimatedContent(
                    targetState = if (isPortrait) AppPage.Controls else page,
                    modifier = Modifier.fillMaxSize(),
                    transitionSpec = {
                        (slideInHorizontally(animationSpec = tween(AppPageTransitionDurationMillis)) { width -> pageTransitionDirection * (width / 5) } + fadeIn(tween(AppPageFadeDurationMillis))) togetherWith
                            (slideOutHorizontally(animationSpec = tween(AppPageTransitionDurationMillis)) { width -> -pageTransitionDirection * (width / 5) } + fadeOut(tween(AppPageFadeDurationMillis)))
                    },
                    label = "app-page-transition"
                ) { targetPage ->
                    when (targetPage) {
                        AppPage.Controls -> ControlsPage(
                            phoneTheme = remoteBridge.codexPhoneTheme,
                            microphoneActive = remoteBridge.microphoneActive || remoteBridge.microphoneStarting,
                            microphoneEnabled = remoteBridge.connectionState == RemoteConnectionState.Connected && !remoteBridge.microphoneStarting,
                            onMicrophoneToggle = toggleMicrophone,
                            pages = remoteBridge.smartphonePages,
                            pageIndex = buttonPageIndex,
                            folderAction = currentFolderAction,
                            fiveHourRemaining = remoteBridge.fiveHourRemainingPercent,
                            weeklyRemaining = remoteBridge.remainingPercent,
                            fiveHourResetsAt = remoteBridge.fiveHourResetsAt,
                            weeklyResetsAt = remoteBridge.resetsAt,
                            dotMatrixSkin = remoteBridge.codexPhoneTheme == DotMatrixCodexPhoneTheme,
                            pixelQuestSkin = remoteBridge.codexPhoneTheme == PixelQuestCodexPhoneTheme,
                            onPageChange = {
                                openFolderAction = null
                                buttonPageIndex = it
                            },
                            onConnectionSettings = { showConnectionSettings = true },
                            onOpenFolder = { action ->
                                openFolderAction = action
                                suppressCodexRevealUntilElapsedMillis =
                                    SystemClock.elapsedRealtime() + ButtonActionRevealSuppressionMillis
                                remoteBridge.sendSmartphoneButton(action.id, action.command == "smartphoneButtonLongPress")
                            },
                            onCloseFolder = { openFolderAction = null },
                            onAction = { action ->
                                suppressCodexRevealUntilElapsedMillis =
                                    SystemClock.elapsedRealtime() + ButtonActionRevealSuppressionMillis
                                if (action.command == "smartphoneButton" || action.command == "smartphoneButtonLongPress") {
                                    remoteBridge.sendSmartphoneButton(action.id, action.command == "smartphoneButtonLongPress")
                                } else {
                                    remoteBridge.sendCommand(action.command)
                                }
                            }
                        )
                        AppPage.Codex -> CodexStatusPage(remoteBridge)
                    }
                }
            }
        }
        if (idleBlackoutEnabled && blackoutVisible) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Black)
                    .pointerInput(Unit) {
                        awaitEachGesture {
                            awaitFirstDown(requireUnconsumed = false)
                            markInteraction()
                        }
                    }
            ) {
                BlackoutFlipClock(
                    sizePercent = blackoutClockSizePercent,
                    modifier = Modifier.fillMaxSize()
                )
                BlackoutStatusIndicator(
                    isCodexWorking = shouldShowCodexWorkingStatus(remoteBridge.activeSessionCount),
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(end = 18.dp, bottom = 18.dp)
                )
            }
        }
        if (showConnectionSettings) {
            BridgeConnectionSettingsDialog(
                microphoneActive = remoteBridge.microphoneActive,
                microphoneStarting = remoteBridge.microphoneStarting,
                microphoneEnabled = remoteBridge.connectionState == RemoteConnectionState.Connected,
                onMicrophoneToggle = toggleMicrophone,
                soundOutputTarget = remoteBridge.completionSoundTarget.takeIf { it == remoteBridge.approvalSoundOutputTarget } ?: "",
                soundOutputTargetEnabled = remoteBridge.connectionState == RemoteConnectionState.Connected,
                onSoundOutputTargetChanged = remoteBridge::requestSoundOutputTarget,
                idleBlackoutEnabled = idleBlackoutEnabled,
                displayKeepAwakeMinutes = displayKeepAwakeMinutes,
                completionBlinkDurationSeconds = completionBlinkDurationSeconds,
                blackoutClockSizePercent = blackoutClockSizePercent,
                onIdleBlackoutEnabledChanged = { idleBlackoutEnabled = it },
                onDisplayKeepAwakeMinutesChanged = { displayKeepAwakeMinutes = it },
                onCompletionBlinkDurationSecondsChanged = { completionBlinkDurationSeconds = it },
                onBlackoutClockSizePercentChanged = { blackoutClockSizePercent = it },
                onDismiss = { showConnectionSettings = false }
            )
        }
        remoteBridge.pendingApproval?.takeIf {
            shouldShowApprovalDialog(it, dismissedApproval)
        }?.let { approval ->
            ApprovalRequestDialog(
                approval = approval,
                onDecision = { decision, requestKey -> remoteBridge.sendCodexApproval(decision, requestKey) },
                onDismiss = { dismissedApproval = approval }
            )
        }
    }
}

@Composable
private fun BlackoutStatusIndicator(
    isCodexWorking: Boolean,
    modifier: Modifier = Modifier
) {
    val motion = rememberInfiniteTransition(label = "blackout-codex-indicator")
    val pulseProgress by motion.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(650),
            repeatMode = RepeatMode.Reverse
        ),
        label = "blackout-codex-indicator-pulse"
    )
    Box(
        modifier = modifier
            .size(8.dp)
            .background(
                if (isCodexWorking) {
                    Green.copy(alpha = blackoutIndicatorAlpha(isCodexWorking, pulseProgress))
                } else {
                    TextPrimary
                },
                CircleShape
            )
    )
}

@Composable
private fun Header(
    message: String,
    messageColor: Color,
    connectionState: RemoteConnectionState,
    macSleepMode: String,
    activeSessionCount: Int,
    fiveHourRemaining: Int?,
    weeklyRemaining: Int?,
    codexPhoneTheme: String,
    completionEventId: Int,
    completionBlinkDurationMillis: Long,
    onCompletionFlashFinished: () -> Unit
) {
    val isCodexWorking = shouldShowCodexWorkingStatus(activeSessionCount)
    val isCompletion = completionEventId > 0
    var completionBlinkOn by remember { mutableStateOf(false) }
    LaunchedEffect(completionEventId, completionBlinkDurationMillis) {
        completionBlinkOn = false
        if (completionEventId > 0) {
            val blinkSteps = 8
            val halfPeriodMillis = (completionBlinkDurationMillis / blinkSteps).coerceAtLeast(80L)
            repeat(blinkSteps) { step ->
                completionBlinkOn = step % 2 == 0
                delay(halfPeriodMillis)
            }
            onCompletionFlashFinished()
        }
        completionBlinkOn = false
    }
    val pulse = rememberInfiniteTransition(label = "codex-header-pulse")
    val pulseProgress by pulse.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(900),
            repeatMode = RepeatMode.Reverse
        ),
        label = "codex-header-pulse-progress"
    )
    val pixelSpaceSkin = codexPhoneTheme == PixelSpaceCodexPhoneTheme
    val dotMatrixSkin = codexPhoneTheme == DotMatrixCodexPhoneTheme
    val pixelQuestSkin = codexPhoneTheme == PixelQuestCodexPhoneTheme
    val workingAccent = when {
        codexPhoneTheme == ControlCabinetCodexPhoneTheme -> CabinetAmber
        pixelSpaceSkin -> PixelSpaceMint
        dotMatrixSkin -> DotMatrixCyan
        pixelQuestSkin -> PixelQuestGold
        else -> Green
    }
    val workingStatusColor = if (isCodexWorking) {
        workingAccent.copy(alpha = codexHeaderPulseAlpha("running", pulseProgress))
    } else {
        Green
    }
    val completionStatusColor = if (completionBlinkOn) Green else Green.copy(alpha = 0.25f)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(32.dp)
            .padding(horizontal = if (LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT) 16.dp else 20.dp),
    ) {
        val isPortrait = LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT
        if (isPortrait) {
            Row(modifier = Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(9.dp)
                        .background(
                            if (connectionState == RemoteConnectionState.Connected) Green else TextMuted,
                            RoundedCornerShape(50)
                        )
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    when (connectionState) {
                        RemoteConnectionState.Connected -> "Mac connected"
                        RemoteConnectionState.Connecting -> "Connecting to Mac"
                        RemoteConnectionState.Searching -> "Searching for Mac"
                        RemoteConnectionState.Disconnected -> "Mac disconnected"
                    },
                    color = TextPrimary,
                    fontSize = 13.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.width(12.dp))
                MacSleepStatusBadge(connectionState, macSleepMode)
                Spacer(Modifier.width(8.dp))
                HeaderActivityStatus(
                    modifier = Modifier.weight(1f),
                    isCodexWorking = isCodexWorking,
                    isCompletion = isCompletion,
                    message = message,
                    messageColor = messageColor,
                    workingStatusColor = workingStatusColor,
                    completionStatusColor = completionStatusColor,
                    pixelSpaceSkin = pixelSpaceSkin,
                    dotMatrixSkin = dotMatrixSkin,
                    pixelQuestSkin = pixelQuestSkin
                )
            }
        } else {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(10.dp)
                        .background(
                            if (connectionState == RemoteConnectionState.Connected) Green else TextMuted,
                            RoundedCornerShape(50)
                        )
                )
                Spacer(Modifier.width(12.dp))
                Text(
                    when (connectionState) {
                        RemoteConnectionState.Connected -> "Mac connected"
                        RemoteConnectionState.Connecting -> "Connecting to Mac"
                        RemoteConnectionState.Searching -> "Searching for Mac"
                        RemoteConnectionState.Disconnected -> "Mac disconnected"
                    },
                    color = TextPrimary,
                    fontSize = 16.sp
                )
                Spacer(Modifier.width(18.dp))
                MacSleepStatusBadge(connectionState, macSleepMode)
                Spacer(Modifier.width(12.dp))
                HeaderActivityStatus(
                    modifier = Modifier.weight(1f).padding(end = 12.dp),
                    isCodexWorking = isCodexWorking,
                    isCompletion = isCompletion,
                    message = message,
                    messageColor = messageColor,
                    workingStatusColor = workingStatusColor,
                    completionStatusColor = completionStatusColor,
                    pixelSpaceSkin = pixelSpaceSkin,
                    dotMatrixSkin = dotMatrixSkin,
                    pixelQuestSkin = pixelQuestSkin
                )
                UsageMeter(label = "5시간", remainingPercent = fiveHourRemaining, accent = GaugeCool)
                Spacer(Modifier.width(10.dp))
                UsageMeter(label = "주간", remainingPercent = weeklyRemaining, accent = GaugeHigh)
            }
        }
    }
}

@Composable
private fun MacSleepStatusBadge(connectionState: RemoteConnectionState, mode: String) {
    val connected = connectionState == RemoteConnectionState.Connected
    val label = if (!connected) "상태 미확인" else when (mode) {
        "insomnia" -> "불면증"
        "sleep" -> "숙면"
        else -> "상태 미확인"
    }
    val color = when {
        connected && mode == "insomnia" -> Color(0xFFFFB45C)
        connected && mode == "sleep" -> Color(0xFF8DBFFF)
        else -> TextMuted
    }
    val icon = when {
        connected && mode == "insomnia" -> Icons.Outlined.LightMode
        connected && mode == "sleep" -> Icons.Outlined.DarkMode
        else -> Icons.Outlined.MoreHoriz
    }
    Row(
        modifier = Modifier.background(color.copy(alpha = 0.22f), RoundedCornerShape(6.dp))
            .border(1.dp, color.copy(alpha = 0.4f), RoundedCornerShape(6.dp))
            .padding(horizontal = 8.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(14.dp))
        Text(text = label, color = color, fontSize = 12.sp, fontWeight = FontWeight.Medium, maxLines = 1)
    }
}

@Composable
private fun HeaderActivityStatus(
    modifier: Modifier,
    isCodexWorking: Boolean,
    isCompletion: Boolean,
    message: String,
    messageColor: Color,
    workingStatusColor: Color,
    completionStatusColor: Color,
    pixelSpaceSkin: Boolean,
    dotMatrixSkin: Boolean,
    pixelQuestSkin: Boolean
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (isCodexWorking) {
            RunningStatusIndicator(
                color = workingStatusColor,
                pixelStyle = pixelSpaceSkin,
                dotMatrixStyle = dotMatrixSkin,
                pixelQuestStyle = pixelQuestSkin
            )
            Text(
                "Codex 작업중",
                color = workingStatusColor,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        if (isCompletion) {
            Text(
                "Codex 작업 완료",
                color = completionStatusColor,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        if (!isCodexWorking && !isCompletion) {
            Text(
                message,
                color = messageColor,
                fontSize = 14.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

/**
 * A compact, always-mounted working indicator. The header is shared by both
 * app pages, so the running motion stays visible even when the user is on the
 * button page instead of the full Codex status page.
 */
@Composable
private fun RunningStatusIndicator(
    color: Color,
    pixelStyle: Boolean,
    dotMatrixStyle: Boolean = false,
    pixelQuestStyle: Boolean = false
) {
    if (dotMatrixStyle) {
        DotMatrixStatusMotion(activity = "running", color = color, modifier = Modifier.size(18.dp))
        return
    }
    if (pixelQuestStyle) {
        PixelQuestStatusMark(activity = "running", color = color, modifier = Modifier.size(18.dp))
        return
    }
    val motion = rememberInfiniteTransition(label = "codex-running-header-indicator")
    val rotation by motion.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200),
            repeatMode = RepeatMode.Restart
        ),
        label = "codex-running-header-rotation"
    )
    val pulse by motion.animateFloat(
        initialValue = 0.55f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(850),
            repeatMode = RepeatMode.Reverse
        ),
        label = "codex-running-header-pulse"
    )
    Canvas(modifier = Modifier.size(18.dp)) {
        if (pixelStyle) {
            drawPixelSpinner(color, rotation)
            return@Canvas
        }
        val center = Offset(size.width / 2f, size.height / 2f)
        val radius = size.minDimension * 0.28f
        drawCircle(color = color.copy(alpha = 0.16f * pulse), radius = radius * 1.8f, center = center)
        rotate(rotation, center) {
            drawArc(
                color = color,
                startAngle = -65f,
                sweepAngle = 235f,
                useCenter = false,
                style = Stroke(width = size.minDimension * 0.14f, cap = StrokeCap.Round)
            )
        }
        drawCircle(color = color, radius = radius * 0.72f, center = center)
    }
}

@Composable
private fun BridgeConnectionSettingsDialog(
    microphoneActive: Boolean,
    microphoneStarting: Boolean,
    microphoneEnabled: Boolean,
    onMicrophoneToggle: (Boolean) -> Unit,
    soundOutputTarget: String,
    soundOutputTargetEnabled: Boolean,
    onSoundOutputTargetChanged: (String) -> Unit,
    idleBlackoutEnabled: Boolean,
    displayKeepAwakeMinutes: Int,
    completionBlinkDurationSeconds: Int,
    blackoutClockSizePercent: Int,
    onIdleBlackoutEnabledChanged: (Boolean) -> Unit,
    onDisplayKeepAwakeMinutesChanged: (Int) -> Unit,
    onCompletionBlinkDurationSecondsChanged: (Int) -> Unit,
    onBlackoutClockSizePercentChanged: (Int) -> Unit,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val preferences = remember { RemoteBridgePreferences(context) }
    var draftMacBridgeHost by remember { mutableStateOf(preferences.macBridgeHost) }
    var keepRunningInBackground by remember { mutableStateOf(preferences.keepRunningInBackground) }
    var selectedKey by remember { mutableStateOf(preferences.screenOffOptionKey) }
    var sleepWindowEnabled by remember { mutableStateOf(preferences.sleepWindowEnabled) }
    var sleepWindowStart by remember { mutableStateOf(preferences.sleepWindowStartMinutes) }
    var sleepWindowEnd by remember { mutableStateOf(preferences.sleepWindowEndMinutes) }
    var draftIdleBlackoutEnabled by remember { mutableStateOf(idleBlackoutEnabled) }
    var draftDisplayKeepAwakeMinutes by remember {
        mutableStateOf(clampDisplayKeepAwakeMinutes(displayKeepAwakeMinutes))
    }
    var draftCompletionBlinkDurationSeconds by remember {
        mutableStateOf(completionBlinkDurationSeconds)
    }
    var draftSoundOutputTarget by remember(soundOutputTarget) { mutableStateOf(soundOutputTarget) }
    var draftBlackoutClockSizePercent by remember {
        mutableStateOf(clampBlackoutClockSizePercent(blackoutClockSizePercent))
    }
    val selectedMinutes = selectedKey.removeSuffix("m").toIntOrNull()
        ?.coerceIn(MinScreenOffTimeoutMinutes, MaxScreenOffTimeoutMinutes)
        ?: 30
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Tile,
        titleContentColor = TextPrimary,
        textContentColor = TextPrimary,
        title = { Text("연결 설정", color = TextPrimary) },
        text = {
            Column(
                modifier = Modifier
                    .heightIn(max = 420.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                OutlinedTextField(
                    value = draftMacBridgeHost,
                    onValueChange = { draftMacBridgeHost = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("맥의 Tailscale 주소") },
                    placeholder = { Text("100.x.x.x") },
                    supportingText = {
                        Text("같은 Wi-Fi의 Mac을 먼저 찾고, 찾지 못하면 이 주소로 연결합니다.")
                    },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri)
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("백그라운드 연결 유지", color = TextPrimary, fontSize = 14.sp)
                    Spacer(Modifier.weight(1f))
                    Switch(
                        checked = keepRunningInBackground,
                        onCheckedChange = { keepRunningInBackground = it },
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Black,
                            checkedTrackColor = Green,
                            checkedBorderColor = Green,
                            uncheckedThumbColor = TextMuted,
                            uncheckedTrackColor = Tile,
                            uncheckedBorderColor = TextMuted
                        )
                    )
                }
                Text(
                    "끄면 앱을 벗어나거나 화면이 꺼질 때 Mac 연결을 중지합니다.",
                    color = TextMuted,
                    fontSize = 12.sp
                )
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            if (selectedKey == "always") selectedKey = "30m"
                        },
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    RadioButton(
                        selected = selectedKey != "always",
                        onClick = { selectedKey = "${selectedMinutes}m" },
                        colors = RadioButtonDefaults.colors(
                            selectedColor = Green,
                            unselectedColor = TextMuted
                        )
                    )
                    Text("제한 시간", color = TextPrimary, fontSize = 14.sp)
                    Spacer(Modifier.width(8.dp))
                    IconButton(
                        onClick = {
                            val next = (selectedMinutes - ScreenOffTimeoutStepMinutes)
                                .coerceAtLeast(MinScreenOffTimeoutMinutes)
                            selectedKey = "${next}m"
                        },
                        enabled = selectedKey != "always" && selectedMinutes > MinScreenOffTimeoutMinutes,
                        modifier = Modifier.size(34.dp)
                    ) {
                        Icon(Icons.Outlined.Remove, contentDescription = "시간 줄이기", tint = TextPrimary)
                    }
                    Text("${selectedMinutes}분", color = TextPrimary, fontSize = 14.sp)
                    IconButton(
                        onClick = {
                            val next = (selectedMinutes + ScreenOffTimeoutStepMinutes)
                                .coerceAtMost(MaxScreenOffTimeoutMinutes)
                            selectedKey = "${next}m"
                        },
                        enabled = selectedKey != "always" && selectedMinutes < MaxScreenOffTimeoutMinutes,
                        modifier = Modifier.size(34.dp)
                    ) {
                        Icon(Icons.Outlined.Add, contentDescription = "시간 늘리기", tint = TextPrimary)
                    }
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { selectedKey = "always" },
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    RadioButton(
                        selected = selectedKey == "always",
                        onClick = { selectedKey = "always" },
                        colors = RadioButtonDefaults.colors(
                            selectedColor = Green,
                            unselectedColor = TextMuted
                        )
                    )
                    Text("계속 유지", color = TextPrimary, fontSize = 14.sp)
                }
                Spacer(Modifier.height(6.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("디스플레이 켜짐 유지", color = TextPrimary, fontSize = 14.sp)
                    Spacer(Modifier.weight(1f))
                    IconButton(
                        onClick = {
                            draftDisplayKeepAwakeMinutes = clampDisplayKeepAwakeMinutes(
                                draftDisplayKeepAwakeMinutes - DisplayKeepAwakeStepMinutes
                            )
                        },
                        enabled = draftDisplayKeepAwakeMinutes > MinDisplayKeepAwakeMinutes,
                        modifier = Modifier.size(34.dp)
                    ) {
                        Icon(Icons.Outlined.Remove, contentDescription = "화면 유지 시간 줄이기", tint = TextPrimary)
                    }
                    Text("${draftDisplayKeepAwakeMinutes}분", color = TextPrimary, fontSize = 14.sp)
                    IconButton(
                        onClick = {
                            draftDisplayKeepAwakeMinutes = clampDisplayKeepAwakeMinutes(
                                draftDisplayKeepAwakeMinutes + DisplayKeepAwakeStepMinutes
                            )
                        },
                        enabled = draftDisplayKeepAwakeMinutes < MaxDisplayKeepAwakeMinutes,
                        modifier = Modifier.size(34.dp)
                    ) {
                        Icon(Icons.Outlined.Add, contentDescription = "화면 유지 시간 늘리기", tint = TextPrimary)
                    }
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("대기 시 블랙 화면", color = TextPrimary, fontSize = 14.sp)
                    Spacer(Modifier.weight(1f))
                    Switch(
                        checked = draftIdleBlackoutEnabled,
                        onCheckedChange = { draftIdleBlackoutEnabled = it },
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Black,
                            checkedTrackColor = Green,
                            checkedBorderColor = Green,
                            uncheckedThumbColor = TextMuted,
                            uncheckedTrackColor = Tile,
                            uncheckedBorderColor = TextMuted
                        )
                    )
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("플립 시계 크기", color = TextPrimary, fontSize = 14.sp)
                    Spacer(Modifier.weight(1f))
                    IconButton(
                        onClick = {
                            draftBlackoutClockSizePercent = clampBlackoutClockSizePercent(
                                draftBlackoutClockSizePercent - BlackoutClockSizeStepPercent
                            )
                        },
                        enabled = draftBlackoutClockSizePercent > MinBlackoutClockSizePercent,
                        modifier = Modifier.size(34.dp)
                    ) {
                        Icon(Icons.Outlined.Remove, contentDescription = "플립 시계 작게", tint = TextPrimary)
                    }
                    Text("${draftBlackoutClockSizePercent}%", color = TextPrimary, fontSize = 14.sp)
                    IconButton(
                        onClick = {
                            draftBlackoutClockSizePercent = clampBlackoutClockSizePercent(
                                draftBlackoutClockSizePercent + BlackoutClockSizeStepPercent
                            )
                        },
                        enabled = draftBlackoutClockSizePercent < MaxBlackoutClockSizePercent,
                        modifier = Modifier.size(34.dp)
                    ) {
                        Icon(Icons.Outlined.Add, contentDescription = "플립 시계 크게", tint = TextPrimary)
                    }
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("완료 깜빡임", color = TextPrimary, fontSize = 14.sp)
                    Spacer(Modifier.weight(1f))
                    IconButton(
                        onClick = {
                            draftCompletionBlinkDurationSeconds = clampCompletionBlinkDurationSeconds(
                                draftCompletionBlinkDurationSeconds - 1
                            )
                        },
                        enabled = draftCompletionBlinkDurationSeconds > MinCompletionBlinkDurationSeconds,
                        modifier = Modifier.size(34.dp)
                    ) {
                        Icon(Icons.Outlined.Remove, contentDescription = "완료 깜빡임 시간 줄이기", tint = TextPrimary)
                    }
                    Text("${draftCompletionBlinkDurationSeconds}초", color = TextPrimary, fontSize = 14.sp)
                    IconButton(
                        onClick = {
                            draftCompletionBlinkDurationSeconds = clampCompletionBlinkDurationSeconds(
                                draftCompletionBlinkDurationSeconds + 1
                            )
                        },
                        enabled = draftCompletionBlinkDurationSeconds < MaxCompletionBlinkDurationSeconds,
                        modifier = Modifier.size(34.dp)
                    ) {
                        Icon(Icons.Outlined.Add, contentDescription = "완료 깜빡임 시간 늘리기", tint = TextPrimary)
                    }
                }
                Text("알림 사운드 재생 기기", color = TextPrimary, fontSize = 14.sp)
                Text("완료·승인 사운드에 함께 적용됩니다.", color = TextMuted, fontSize = 11.sp)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    listOf("phone" to "휴대폰", "mac" to "Mac").forEach { (target, label) ->
                        Row(
                            modifier = Modifier.clickable(enabled = soundOutputTargetEnabled) {
                                draftSoundOutputTarget = target
                            },
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(
                                selected = draftSoundOutputTarget == target,
                                onClick = { draftSoundOutputTarget = target },
                                enabled = soundOutputTargetEnabled,
                                colors = RadioButtonDefaults.colors(selectedColor = Green, unselectedColor = TextMuted)
                            )
                            Text(label, color = if (soundOutputTargetEnabled) TextPrimary else TextMuted, fontSize = 14.sp)
                        }
                    }
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("휴대폰을 Mac 마이크로 사용", color = TextPrimary, fontSize = 14.sp)
                    Spacer(Modifier.weight(1f))
                    Switch(
                        checked = microphoneActive || microphoneStarting,
                        onCheckedChange = onMicrophoneToggle,
                        enabled = microphoneEnabled && !microphoneStarting,
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Black,
                            checkedTrackColor = Green,
                            checkedBorderColor = Green,
                            uncheckedThumbColor = TextMuted,
                            uncheckedTrackColor = Tile,
                            uncheckedBorderColor = TextMuted
                        )
                    )
                }
                Text("켜면 Mac 기본 마이크가 BlackHole 2ch로 바뀝니다.", color = TextMuted, fontSize = 12.sp)
                Spacer(Modifier.height(6.dp))
                Text("절전 시간대", color = TextPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(
                        selected = sleepWindowEnabled,
                        onClick = { sleepWindowEnabled = !sleepWindowEnabled },
                        colors = RadioButtonDefaults.colors(
                            selectedColor = Green,
                            unselectedColor = TextMuted
                        )
                    )
                    Text("사용", color = TextPrimary, fontSize = 14.sp)
                    Spacer(Modifier.width(8.dp))
                    TextButton(
                        enabled = sleepWindowEnabled,
                        onClick = {
                            val initial = minutesToClock(sleepWindowStart)
                            TimePickerDialog(context, { _, hour, minute ->
                                sleepWindowStart = hour * 60 + minute
                            }, initial.first, initial.second, true).show()
                        }
                    ) { Text(formatClockMinutes(sleepWindowStart), color = if (sleepWindowEnabled) GaugeHigh else TextMuted) }
                    Text(" ~ ", color = TextMuted)
                    TextButton(
                        enabled = sleepWindowEnabled,
                        onClick = {
                            val initial = minutesToClock(sleepWindowEnd)
                            TimePickerDialog(context, { _, hour, minute ->
                                sleepWindowEnd = hour * 60 + minute
                            }, initial.first, initial.second, true).show()
                        }
                    ) { Text(formatClockMinutes(sleepWindowEnd), color = if (sleepWindowEnabled) GaugeHigh else TextMuted) }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val nextMacBridgeHost = draftMacBridgeHost.trim()
                    val macBridgeHostChanged = preferences.macBridgeHost != nextMacBridgeHost
                    preferences.macBridgeHost = nextMacBridgeHost
                    preferences.keepRunningInBackground = keepRunningInBackground
                    preferences.screenOffOptionKey = selectedKey
                    preferences.idleBlackoutEnabled = draftIdleBlackoutEnabled
                    preferences.displayKeepAwakeMinutes = draftDisplayKeepAwakeMinutes
                    preferences.completionBlinkDurationSeconds = draftCompletionBlinkDurationSeconds
                    preferences.blackoutClockSizePercent = draftBlackoutClockSizePercent
                    preferences.sleepWindowEnabled = sleepWindowEnabled
                    preferences.sleepWindowStartMinutes = sleepWindowStart
                    preferences.sleepWindowEndMinutes = sleepWindowEnd
                    context.sendBroadcast(
                        Intent(
                            if (macBridgeHostChanged) RemoteBridgeService.ACTION_CONNECTION_CHANGED
                            else RemoteBridgeService.ACTION_TIMEOUT_CHANGED
                        )
                            .setPackage(context.packageName)
                    )
                    onIdleBlackoutEnabledChanged(draftIdleBlackoutEnabled)
                    onDisplayKeepAwakeMinutesChanged(draftDisplayKeepAwakeMinutes)
                    onCompletionBlinkDurationSecondsChanged(draftCompletionBlinkDurationSeconds)
                    onBlackoutClockSizePercentChanged(draftBlackoutClockSizePercent)
                    if (soundOutputTargetEnabled && draftSoundOutputTarget != soundOutputTarget && draftSoundOutputTarget in setOf("phone", "mac")) {
                        onSoundOutputTargetChanged(draftSoundOutputTarget)
                    }
                    onDismiss()
                }
            ) {
                Text("저장", color = Green)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("취소", color = TextMuted)
            }
        }
    )
}

private fun minutesToClock(minutes: Int): Pair<Int, Int> = minutes / 60 to minutes % 60

private fun formatClockMinutes(minutes: Int): String = "%02d:%02d".format(Locale.US, minutes / 60, minutes % 60)

@Composable
private fun UsageMeter(label: String, remainingPercent: Int?, accent: Color) {
    val clampedPercent = clampUsagePercent(remainingPercent)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Text(label, color = TextMuted, fontSize = 10.sp, fontWeight = FontWeight.Medium)
        Box(
            modifier = Modifier
                .width(38.dp)
                .height(15.dp)
                .border(1.dp, TextMuted, RoundedCornerShape(3.dp))
                .padding(2.dp)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth((clampedPercent ?: 0) / 100f)
                    .background(accent, RoundedCornerShape(1.dp))
            )
        }
        Box(
            modifier = Modifier
                .width(2.dp)
                .height(6.dp)
                .background(TextMuted, RoundedCornerShape(1.dp))
        )
        Text(
            clampedPercent?.let { "$it%" } ?: "--",
            color = if (clampedPercent != null) TextPrimary else TextMuted,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1
        )
    }
}

@Composable
private fun ControlsPage(
    phoneTheme: String,
    microphoneActive: Boolean,
    microphoneEnabled: Boolean,
    onMicrophoneToggle: (Boolean) -> Unit,
    pages: List<ButtonPage>,
    pageIndex: Int,
    folderAction: ControlAction?,
    fiveHourRemaining: Int?,
    weeklyRemaining: Int?,
    fiveHourResetsAt: Double?,
    weeklyResetsAt: Double?,
    dotMatrixSkin: Boolean,
    pixelQuestSkin: Boolean,
    onPageChange: (Int) -> Unit,
    onConnectionSettings: () -> Unit,
    onOpenFolder: (ControlAction) -> Unit,
    onCloseFolder: () -> Unit,
    onAction: (ControlAction) -> Unit
) {
    var nowEpochSeconds by remember { mutableStateOf(System.currentTimeMillis() / 1_000L) }
    LaunchedEffect(phoneTheme) {
        while (true) {
            nowEpochSeconds = System.currentTimeMillis() / 1_000L
            delay(30_000L)
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val isPortrait = maxHeight > maxWidth
        if (isPortrait) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(start = 16.dp, top = MainContentTopPadding, end = 16.dp, bottom = 10.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("PAGES", color = TextMuted, fontSize = 11.sp, fontWeight = FontWeight.Medium)
                    Spacer(Modifier.width(8.dp))
                    if (pages.size <= 3) {
                        Row(
                            modifier = Modifier.weight(1f),
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            pages.forEachIndexed { index, buttonPage ->
                                Box(Modifier.weight(1f)) {
                                    PageSelector(
                                        phoneTheme = phoneTheme,
                                        page = buttonPage,
                                        selected = index == pageIndex,
                                        onClick = { onPageChange(index) },
                                        compact = true
                                    )
                                }
                            }
                        }
                    } else {
                        Row(
                            modifier = Modifier.weight(1f).horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            pages.forEachIndexed { index, buttonPage ->
                                PageSelector(
                                    phoneTheme = phoneTheme,
                                    page = buttonPage,
                                    selected = index == pageIndex,
                                    onClick = { onPageChange(index) },
                                    modifier = Modifier.width(104.dp),
                                    compact = true
                                )
                            }
                        }
                    }
                    IconButton(
                        onClick = { onMicrophoneToggle(!microphoneActive) },
                        enabled = microphoneEnabled,
                        modifier = Modifier.size(44.dp)
                            .background(if (microphoneActive) Green.copy(alpha = 0.18f) else Tile, RoundedCornerShape(12.dp))
                    ) {
                        Icon(
                            if (microphoneActive) Icons.Outlined.Mic else Icons.Outlined.MicOff,
                            contentDescription = if (microphoneActive) "마이크 끄기" else "마이크 켜기",
                            tint = if (microphoneActive) Green else TextMuted
                        )
                    }
                    IconButton(onClick = onConnectionSettings, modifier = Modifier.size(44.dp)) {
                        Icon(Icons.Outlined.Settings, contentDescription = "연결 설정", tint = TextMuted)
                    }
                }
                Spacer(Modifier.height(10.dp))
                ControlsPageContent(
                    phoneTheme = phoneTheme,
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                    isPortrait = true,
                    pages = pages,
                    pageIndex = pageIndex,
                    folderAction = folderAction,
                    onPageChange = onPageChange,
                    onOpenFolder = onOpenFolder,
                    onCloseFolder = onCloseFolder,
                    onAction = onAction
                )
                Spacer(Modifier.height(8.dp))
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (pixelQuestSkin) {
                        PixelQuestUsageProgress(
                            label = "1-WEEK QUEST",
                            remaining = weeklyRemaining,
                            resetAt = weeklyResetsAt,
                            includeDate = true,
                            nowEpochSeconds = nowEpochSeconds,
                            accent = PixelQuestGold
                        )
                        PixelQuestUsageProgress(
                            label = "5-HOUR QUEST",
                            remaining = fiveHourRemaining,
                            resetAt = fiveHourResetsAt,
                            includeDate = false,
                            nowEpochSeconds = nowEpochSeconds,
                            accent = PixelQuestCoral
                        )
                    } else if (phoneTheme == ControlCabinetCodexPhoneTheme) {
                        ControlCabinetUsageGauge("1-week remaining", weeklyRemaining, weeklyResetsAt, true, nowEpochSeconds)
                        ControlCabinetUsageGauge("5-hour remaining", fiveHourRemaining, fiveHourResetsAt, false, nowEpochSeconds)
                    } else {
                        PhoneUsageGauge(phoneTheme, "1-week remaining", weeklyRemaining, weeklyResetsAt, true, nowEpochSeconds)
                        PhoneUsageGauge(phoneTheme, "5-hour remaining", fiveHourRemaining, fiveHourResetsAt, false, nowEpochSeconds)
                    }
                }
            }
        } else {
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(start = 20.dp, top = MainContentTopPadding, end = 20.dp)
            ) {
                Column(
                    modifier = Modifier
                        .width(148.dp)
                        .fillMaxHeight()
                        .padding(end = 22.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text("PAGES", color = TextPrimary, fontSize = 24.sp, fontWeight = FontWeight.Medium)
                    Text("Select a button page", color = TextMuted, fontSize = 13.sp)
                    Spacer(Modifier.height(8.dp))
                    pages.forEachIndexed { index, buttonPage ->
                        PageSelector(
                            phoneTheme = phoneTheme,
                            page = buttonPage,
                            selected = index == pageIndex,
                            onClick = { onPageChange(index) }
                        )
                    }
                    Spacer(Modifier.weight(1f))
                    IconButton(
                        onClick = { onMicrophoneToggle(!microphoneActive) },
                        enabled = microphoneEnabled,
                        modifier = Modifier.size(44.dp)
                            .background(if (microphoneActive) Green.copy(alpha = 0.18f) else Tile, RoundedCornerShape(12.dp))
                    ) {
                        Icon(
                            if (microphoneActive) Icons.Outlined.Mic else Icons.Outlined.MicOff,
                            contentDescription = if (microphoneActive) "마이크 끄기" else "마이크 켜기",
                            tint = if (microphoneActive) Green else TextMuted
                        )
                    }
                    IconButton(onClick = onConnectionSettings, modifier = Modifier.size(44.dp)) {
                        Icon(Icons.Outlined.Settings, contentDescription = "연결 설정", tint = TextMuted)
                    }
                }
                ControlsPageContent(
                    phoneTheme = phoneTheme,
                    modifier = Modifier.fillMaxSize(),
                    isPortrait = false,
                    pages = pages,
                    pageIndex = pageIndex,
                    folderAction = folderAction,
                    onPageChange = onPageChange,
                    onOpenFolder = onOpenFolder,
                    onCloseFolder = onCloseFolder,
                    onAction = onAction
                )
            }
        }
    }
}

@Composable
private fun ControlsPageContent(
    phoneTheme: String,
    modifier: Modifier,
    isPortrait: Boolean,
    pages: List<ButtonPage>,
    pageIndex: Int,
    folderAction: ControlAction?,
    onPageChange: (Int) -> Unit,
    onOpenFolder: (ControlAction) -> Unit,
    onCloseFolder: () -> Unit,
    onAction: (ControlAction) -> Unit
) {
    var verticalDrag by remember { mutableStateOf(0f) }
    val contentModifier = if (isPortrait) {
        modifier
    } else {
        modifier.pointerInput(pageIndex, pages.size) {
            detectVerticalDragGestures(
                onVerticalDrag = { change, dragAmount ->
                    change.consume()
                    verticalDrag += dragAmount
                },
                onDragEnd = {
                    val nextPage = verticalSwipeTarget(pageIndex, pages.size, verticalDrag)
                    if (nextPage != pageIndex) onPageChange(nextPage)
                    verticalDrag = 0f
                },
                onDragCancel = { verticalDrag = 0f }
            )
        }
    }
    BoxWithConstraints(contentModifier) {
        val availableWidth = maxWidth
        val availableHeight = maxHeight
        AnimatedContent(
            targetState = pageIndex to folderAction,
            modifier = Modifier.fillMaxSize(),
            transitionSpec = {
                val direction = pageTransitionDirection(initialState.first, targetState.first, pages.size)
                val enter = if (isPortrait) {
                    slideInHorizontally(animationSpec = tween(260)) { width -> direction * (width / 5) }
                } else {
                    slideInVertically(animationSpec = tween(260)) { height -> direction * (height / 5) }
                }
                val exit = if (isPortrait) {
                    slideOutHorizontally(animationSpec = tween(260)) { width -> -direction * (width / 5) }
                } else {
                    slideOutVertically(animationSpec = tween(260)) { height -> -direction * (height / 5) }
                }
                (enter + fadeIn(tween(180))) togetherWith (exit + fadeOut(tween(180)))
            },
            contentKey = { content -> smartphonePageContentTransitionKey(content.first, content.second?.id) },
            label = "button-page-transition"
        ) { content ->
            val (targetPageIndex, targetFolderAction) = content
            val columnCount = 4
            val gap = 10.dp
            if (targetFolderAction != null) {
                FolderContentsPage(
                    phoneTheme = phoneTheme,
                    folderAction = targetFolderAction,
                    maxWidth = availableWidth,
                    maxHeight = availableHeight,
                    isPortrait = isPortrait,
                    onCloseFolder = onCloseFolder,
                    onAction = onAction
                )
            } else {
                val targetPage = pages[targetPageIndex.coerceIn(pages.indices)]
                val rowCount = (targetPage.actions.size + columnCount - 1) / columnCount
                val requestedTileHeight = if (isPortrait) {
                    ((availableHeight - gap * (rowCount - 1)) / rowCount)
                        .coerceAtLeast(88.dp)
                        .coerceAtMost(112.dp)
                } else {
                    (availableHeight - gap * (rowCount - 1)) / rowCount
                }
                val tileHeight = requestedTileHeight.coerceAtLeast(56.dp)
                val gridHeight = tileHeight * rowCount + gap * (rowCount - 1)
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.TopStart
                ) {
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(columnCount),
                        modifier = if (isPortrait) {
                            Modifier.fillMaxWidth().height(gridHeight.coerceAtMost(availableHeight))
                        } else {
                            Modifier.fillMaxSize()
                        },
                        horizontalArrangement = Arrangement.spacedBy(gap),
                        verticalArrangement = Arrangement.spacedBy(gap),
                        userScrollEnabled = isPortrait && gridHeight > availableHeight
                    ) {
                        items(targetPage.actions) { action ->
                            ActionTile(
                                phoneTheme = phoneTheme,
                                action = action,
                                tileHeight = tileHeight,
                                onClick = {
                                    if (action.actionKind == "appFolder") onOpenFolder(action) else onAction(action)
                                },
                                onLongClick = action.longPressAction?.let { longAction ->
                                    { if (longAction.actionKind == "appFolder") onOpenFolder(longAction) else onAction(longAction) }
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun FolderContentsPage(
    phoneTheme: String,
    folderAction: ControlAction,
    maxWidth: androidx.compose.ui.unit.Dp,
    maxHeight: androidx.compose.ui.unit.Dp,
    isPortrait: Boolean,
    onCloseFolder: () -> Unit,
    onAction: (ControlAction) -> Unit
) {
    val folderItems = folderGridItems(folderAction)
    val columnCount = FolderGridColumnCount
    val visibleRowCount = (folderItems.size + columnCount - 1) / columnCount
    val gap = 10.dp
    val requestedTileHeight = if (isPortrait) {
        ((maxHeight - gap * (visibleRowCount - 1)) / visibleRowCount)
            .coerceAtLeast(88.dp)
            .coerceAtMost(112.dp)
    } else {
        (maxHeight - gap * (visibleRowCount - 1)) / visibleRowCount
    }
    val tileHeight = requestedTileHeight.coerceAtLeast(56.dp)
    val gridHeight = tileHeight * visibleRowCount + gap * (visibleRowCount - 1)
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.TopStart
    ) {
        LazyVerticalGrid(
            columns = GridCells.Fixed(columnCount),
            modifier = if (isPortrait) {
                Modifier.fillMaxWidth().height(gridHeight.coerceAtMost(maxHeight))
            } else {
                Modifier.fillMaxSize()
            },
            horizontalArrangement = Arrangement.spacedBy(gap),
            verticalArrangement = Arrangement.spacedBy(gap),
            userScrollEnabled = isPortrait && gridHeight > maxHeight
        ) {
            items(folderItems) { action ->
                ActionTile(
                    phoneTheme = phoneTheme,
                    action = action,
                    tileHeight = tileHeight,
                    onClick = { if (action.command == "closeFolder") onCloseFolder() else onAction(action) },
                    onLongClick = action.longPressAction?.let { longAction -> { onAction(longAction) } }
                )
            }
        }
    }
}

private const val FolderGridColumnCount = 4
private const val FolderGridRowCount = 4
private const val FolderGridMinimumItemCount = FolderGridColumnCount * FolderGridRowCount

internal fun folderGridItems(folderAction: ControlAction): List<ControlAction> {
    val items = buildList {
        add(
            ControlAction(
                label = "상위 폴더",
                icon = Icons.Outlined.KeyboardArrowUp,
                command = "closeFolder",
                accent = TextPrimary,
                id = "${folderAction.id}_parent"
            )
        )
        addAll(folderAction.folderActions)
        while (size < FolderGridMinimumItemCount) {
            add(
                ControlAction(
                    label = "",
                    icon = Icons.Outlined.MoreHoriz,
                    command = "folderPlaceholder",
                    id = "${folderAction.id}_empty_$size",
                    isPlaceholder = true,
                    isIconless = true
                )
            )
        }
    }
    return items
}

private fun pageTransitionDirection(initialPage: Int, targetPage: Int, pageCount: Int): Int {
    if (initialPage == targetPage) return 1
    if (initialPage == pageCount - 1 && targetPage == 0) return 1
    if (initialPage == 0 && targetPage == pageCount - 1) return -1
    return if (targetPage > initialPage) 1 else -1
}

@Composable
private fun PageSelector(
    phoneTheme: String,
    page: ButtonPage,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    compact: Boolean = false
) {
    val skin = phoneSkinStyle(phoneTheme)
    val shape = RoundedCornerShape(skin.cornerRadius)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(40.dp)
            .clickable(onClick = onClick)
            .background(if (selected) skin.panel else Color.Transparent, shape)
            .border(skin.borderWidth, if (selected) skin.frame else Color.Transparent, shape)
            .padding(horizontal = if (compact) 6.dp else 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(if (compact) 5.dp else 6.dp)
                .background(if (selected && skin.themed) skin.accent else if (selected) Green else TextMuted, RoundedCornerShape(50))
        )
        Spacer(Modifier.width(if (compact) 6.dp else 10.dp))
        Text(
            page.label,
            color = if (selected && skin.themed) skin.accent else if (selected) TextPrimary else TextMuted,
            fontFamily = if (skin.themed) FontFamily.Monospace else FontFamily.Default,
            fontSize = if (compact) 12.sp else 14.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ActionTile(
    phoneTheme: String,
    action: ControlAction,
    tileHeight: androidx.compose.ui.unit.Dp,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null
) {
    val isPortrait = LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT
    val pixelSpace = phoneTheme == PixelSpaceCodexPhoneTheme
    val dotMatrix = phoneTheme == DotMatrixCodexPhoneTheme
    val pixelQuest = phoneTheme == PixelQuestCodexPhoneTheme
    val controlCabinet = phoneTheme == ControlCabinetCodexPhoneTheme
    val skin = phoneSkinStyle(phoneTheme)
    val themed = skin.themed
    val hasShortPressAction = !action.isPlaceholder && (action.command != "smartphoneButton" || action.actionKind != "none")
    val hasLongPressAction = !action.isPlaceholder && action.longPressAction != null && onLongClick != null
    val hapticFeedback = LocalHapticFeedback.current
    val context = LocalContext.current
    val vibrator = remember(context) { context.getSystemService(Vibrator::class.java) }
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    var longPressProgress by remember(action.id) { mutableStateOf(0f) }
    val longPressTimeoutMillis = LocalViewConfiguration.current.longPressTimeoutMillis
    val pressScale by animateFloatAsState(
        targetValue = if (pressed) 0.96f else 1f,
        animationSpec = tween(durationMillis = 100),
        label = "action-tile-press-scale"
    )
    LaunchedEffect(pressed, hasLongPressAction, longPressTimeoutMillis) {
        if (!pressed || !hasLongPressAction) {
            longPressProgress = 0f
            return@LaunchedEffect
        }

        val startedAt = SystemClock.uptimeMillis()
        while (true) {
            val elapsedMillis = SystemClock.uptimeMillis() - startedAt
            longPressProgress = (elapsedMillis.toFloat() / longPressTimeoutMillis.coerceAtLeast(1L))
                .coerceIn(0f, 1f)
            if (longPressProgress >= 1f) break
            delay(16L)
        }
    }
    val accent = skin.accent
    val background = skin.panel
    val frame = skin.frame
    val shape = RoundedCornerShape(skin.cornerRadius)
    androidx.compose.material3.Surface(
        color = if (pressed && themed) androidx.compose.ui.graphics.lerp(background, accent, 0.18f) else background,
        contentColor = action.accent,
        shape = shape,
        modifier = Modifier
            .fillMaxWidth()
            .height(tileHeight)
            .graphicsLayer {
                scaleX = pressScale
                scaleY = pressScale
            }
            .border(skin.borderWidth, if (pressed && themed) accent else frame, shape)
            .clip(shape)
            .combinedClickable(
                enabled = hasShortPressAction || hasLongPressAction,
                role = Role.Button,
                interactionSource = interactionSource,
                indication = ripple(),
                onClickLabel = if (hasShortPressAction) "짧게 눌러 실행" else null,
                onLongClickLabel = if (hasLongPressAction) "길게 눌러 실행" else null,
                onLongClick = if (action.command == "smartphoneButton" || hasLongPressAction) {
                    {
                        if (hasLongPressAction) {
                            if (vibrator?.hasVibrator() == true) {
                                vibrator.vibrate(
                                    VibrationEffect.createOneShot(
                                        LongPressVibrationDurationMillis,
                                        VibrationEffect.DEFAULT_AMPLITUDE
                                    )
                                )
                            } else {
                                hapticFeedback.performHapticFeedback(HapticFeedbackType.LongPress)
                            }
                            onLongClick?.invoke()
                        }
                    }
                } else null,
                onClick = { if (hasShortPressAction) onClick() }
            )
            .semantics {
                if (hasLongPressAction) {
                    stateDescription = if (hasShortPressAction) "짧게 누르기와 길게 누르기에 각각 동작 지정됨" else "길게 눌러 실행"
                }
            }
    ) {
        Box(Modifier.fillMaxSize().drawBehind {
            if (controlCabinet) {
                val inset = 7.dp.toPx()
                for (x in listOf(inset, size.width - inset)) {
                    for (y in listOf(inset, size.height - inset)) {
                        val bolt = Offset(x, y)
                        drawCircle(CabinetFrame, 2.5.dp.toPx(), bolt)
                        drawLine(Black, bolt - Offset(1.5.dp.toPx(), 0f), bolt + Offset(1.5.dp.toPx(), 0f), 1.dp.toPx())
                    }
                }
                drawLine(accent.copy(alpha = if (pressed) 1f else 0.4f), Offset(inset * 2, size.height - inset), Offset(size.width - inset * 2, size.height - inset), 2.dp.toPx())
            } else if (dotMatrix) {
                val step = 8.dp.toPx()
                var y = step / 2
                while (y < size.height) {
                    var x = step / 2
                    while (x < size.width) {
                        drawCircle(DotMatrixGridColor.copy(alpha = 0.45f), 0.7.dp.toPx(), Offset(x, y))
                        x += step
                    }
                    y += step
                }
            } else if (pixelSpace || pixelQuest) {
                val inset = 5.dp.toPx()
                val edge = 1.dp.toPx()
                drawLine(accent.copy(alpha = 0.35f), Offset(inset, inset), Offset(size.width - inset, inset), edge)
                drawLine(accent.copy(alpha = 0.35f), Offset(inset, inset), Offset(inset, size.height - inset), edge)
            }
        }) {
            if (!action.isPlaceholder) {
                Column(
                    modifier = Modifier.fillMaxSize(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(ButtonTileContentGap, Alignment.CenterVertically)
                ) {
                    if (!action.isIconless) {
                        action.iconBitmap?.let { bitmap ->
                            Image(
                                bitmap = bitmap,
                                contentDescription = action.label,
                                modifier = Modifier.size(if (isPortrait) PortraitButtonTileIconSize else ButtonTileIconSize)
                            )
                        } ?: Icon(
                            action.icon,
                            contentDescription = action.label,
                            modifier = Modifier.size(if (isPortrait) PortraitButtonTileIconSize else ButtonTileIconSize)
                        )
                    }
                    Text(
                        action.label,
                        color = if (themed && action.accent == TextPrimary) accent else action.accent,
                        fontFamily = if (themed) FontFamily.Monospace else FontFamily.Default,
                        fontSize = if (isPortrait) PortraitButtonTileLabelFontSize else ButtonTileLabelFontSize,
                        fontWeight = FontWeight.Medium,
                        textAlign = TextAlign.Center,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                if (hasLongPressAction) {
                    Text(
                        if (hasShortPressAction) "짧게 / 길게" else "길게",
                        color = if (themed) accent else TextMuted,
                        fontSize = 10.sp,
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(top = 3.dp, end = 12.dp)
                            .clearAndSetSemantics { }
                    )
                }
            }
            if (hasLongPressAction) {
                Canvas(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(3.dp)
                        .align(Alignment.BottomCenter)
                ) {
                    drawRect(frame.copy(alpha = 0.35f))
                    if (longPressProgress > 0f) {
                        drawRect(
                            color = accent,
                            size = Size(size.width * longPressProgress, size.height)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CodexStatusPage(remoteBridge: RemoteBridgeClient) {
    var nowEpochSeconds by remember { mutableStateOf(System.currentTimeMillis() / 1_000L) }
    LaunchedEffect(Unit) {
        while (true) {
            nowEpochSeconds = System.currentTimeMillis() / 1_000L
            delay(30_000L)
        }
    }
    // Keep rendering defensive for older bridge payloads or a state replay
    // received while reconnecting. The client normally normalizes this value,
    // but the UI must never fall back to the idle branch for an active alias.
    val activity = normalizeRemoteActivity(remoteBridge.activity)
    val pixelSpaceSkin = remoteBridge.codexPhoneTheme == PixelSpaceCodexPhoneTheme
    val dotMatrixSkin = remoteBridge.codexPhoneTheme == DotMatrixCodexPhoneTheme
    val pixelQuestSkin = remoteBridge.codexPhoneTheme == PixelQuestCodexPhoneTheme
    val controlCabinetSkin = remoteBridge.codexPhoneTheme == ControlCabinetCodexPhoneTheme
    val activityTitle = when (activity) {
        "connecting" -> "CONNECTING"
        "running" -> "RUNNING"
        "waitingForApproval" -> "WAITING FOR APPROVAL"
        "completed" -> "COMPLETED"
        "failed" -> "FAILED"
        else -> "IDLE"
    }
    val activityColor = when {
        controlCabinetSkin && activity == "running" -> CabinetAmber
        controlCabinetSkin && activity == "completed" -> Green
        pixelQuestSkin && activity == "running" -> PixelQuestGold
        pixelQuestSkin && activity == "completed" -> PixelQuestMint
        pixelQuestSkin && activity == "waitingForApproval" -> PixelQuestCoral
        pixelQuestSkin && activity == "failed" -> PixelQuestCoral
        pixelQuestSkin -> PixelQuestMuted
        dotMatrixSkin && activity == "running" -> DotMatrixCyan
        dotMatrixSkin && activity == "completed" -> DotMatrixLime
        pixelSpaceSkin && activity == "running" -> PixelSpaceMint
        activity == "failed" -> Red
        activity == "waitingForApproval" -> GaugeMid
        activity == "running" -> Green
        activity == "completed" -> GaugeHigh
        else -> TextMuted
    }
    val fiveHourRemaining = remoteBridge.fiveHourRemainingPercent
    val weeklyRemaining = remoteBridge.remainingPercent
    if (controlCabinetSkin) {
        ControlCabinetCodexStatusPage(remoteBridge, activity, activityTitle, activityColor, nowEpochSeconds)
        return
    }
    if (pixelQuestSkin) {
        PixelQuestCodexStatusPage(
            remoteBridge = remoteBridge,
            activity = activity,
            activityTitle = activityTitle,
            activityColor = activityColor,
            nowEpochSeconds = nowEpochSeconds
        )
        return
    }
    if (LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT) {
        PortraitCodexStatusPage(
            remoteBridge = remoteBridge,
            activity = activity,
            activityTitle = activityTitle,
            activityColor = activityColor,
            nowEpochSeconds = nowEpochSeconds,
            pixelSpaceSkin = pixelSpaceSkin,
            dotMatrixSkin = dotMatrixSkin,
            fiveHourRemaining = fiveHourRemaining,
            weeklyRemaining = weeklyRemaining
        )
        return
    }
    Box(Modifier.fillMaxSize()) {
        if (pixelSpaceSkin) {
            Image(
                painter = painterResource(R.drawable.codex_pixel_space_background),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
            Box(Modifier.fillMaxSize().background(Black.copy(alpha = 0.24f)))
            if (activity == "running") PixelSpaceMotionOverlay(Modifier.fillMaxSize())
        } else if (dotMatrixSkin) {
            DotMatrixBackdrop(Modifier.fillMaxSize())
        }
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(start = 20.dp, top = MainContentTopPadding, end = 20.dp, bottom = 18.dp)
        ) {
        Column(
            modifier = Modifier.width(300.dp).fillMaxHeight(),
            verticalArrangement = Arrangement.spacedBy(if (pixelSpaceSkin) 6.dp else 12.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("CODEX", color = TextPrimary, fontSize = 28.sp, fontWeight = FontWeight.Medium)
                Text(
                    if (remoteBridge.codexConnected) "Codex connected" else "Codex unavailable",
                    color = TextPrimary,
                    fontSize = 18.sp
                )
            }
            if (pixelSpaceSkin) {
                Spacer(Modifier.weight(0.25f))
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Remaining usage", color = TextMuted, fontSize = 15.sp)
                    UsageGauge(
                        "5-hour remaining",
                        fiveHourRemaining,
                        modifier = Modifier.width(200.dp),
                        valueFontSizeSp = 22
                    )
                    Text(
                        formatResetTime(remoteBridge.fiveHourResetsAt, includeDate = false),
                        color = TextPrimary,
                        fontSize = 16.sp,
                        lineHeight = 20.sp,
                        fontWeight = FontWeight.Medium,
                        maxLines = 1
                    )
                    Text(
                        formatRemainingDuration(remoteBridge.fiveHourResetsAt, nowEpochSeconds),
                        color = TextMuted,
                        fontSize = 14.sp,
                        lineHeight = 18.sp,
                        maxLines = 1
                    )
                }
                Spacer(Modifier.weight(1.25f))
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    UsageGauge(
                        "1-week remaining",
                        weeklyRemaining,
                        modifier = Modifier.width(200.dp),
                        valueFontSizeSp = 22
                    )
                    Text(
                        formatResetTime(remoteBridge.resetsAt, includeDate = true),
                        color = TextPrimary,
                        fontSize = 16.sp,
                        lineHeight = 20.sp,
                        fontWeight = FontWeight.Medium,
                        maxLines = 1
                    )
                    Text(
                        formatRemainingDuration(remoteBridge.resetsAt, nowEpochSeconds),
                        color = TextMuted,
                        fontSize = 14.sp,
                        lineHeight = 18.sp,
                        maxLines = 1
                    )
                }
                Spacer(Modifier.weight(0.25f))
            } else {
                Spacer(Modifier.weight(0.55f))
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Remaining usage", color = TextMuted, fontSize = 15.sp)
                    Row(horizontalArrangement = Arrangement.spacedBy(22.dp)) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("5-hour", color = TextMuted, fontSize = 13.sp)
                            Text(
                                fiveHourRemaining?.let { "$it%" } ?: "—",
                                color = usageGaugeColor(fiveHourRemaining),
                                fontSize = 36.sp
                            )
                            Text(
                                formatResetTime(remoteBridge.fiveHourResetsAt, includeDate = false),
                                color = TextPrimary,
                                fontSize = 16.sp,
                                lineHeight = 20.sp,
                                fontWeight = FontWeight.Medium,
                                maxLines = 1
                            )
                            Text(
                                formatRemainingDuration(remoteBridge.fiveHourResetsAt, nowEpochSeconds),
                                color = TextMuted,
                                fontSize = 14.sp,
                                lineHeight = 18.sp,
                                maxLines = 1
                            )
                        }
                        Column(modifier = Modifier.weight(1f)) {
                            Text("1-week", color = TextMuted, fontSize = 13.sp)
                            Text(
                                weeklyRemaining?.let { "$it%" } ?: "—",
                                color = usageGaugeColor(weeklyRemaining),
                                fontSize = 36.sp
                            )
                            Text(
                                formatResetTime(remoteBridge.resetsAt, includeDate = true),
                                color = TextPrimary,
                                fontSize = 16.sp,
                                lineHeight = 20.sp,
                                fontWeight = FontWeight.Medium,
                                maxLines = 1
                            )
                            Text(
                                formatRemainingDuration(remoteBridge.resetsAt, nowEpochSeconds),
                                color = TextMuted,
                                fontSize = 14.sp,
                                lineHeight = 18.sp,
                                maxLines = 1
                            )
                        }
                    }
                }
                Spacer(Modifier.weight(0.45f))
            }
        }
        Box(
            modifier = Modifier.weight(1f).fillMaxHeight().padding(horizontal = 28.dp)
        ) {
            Column(modifier = Modifier.fillMaxSize()) {
                Text("Codex status", color = TextMuted, fontSize = 13.sp)
                Spacer(Modifier.height(16.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    StatusMotion(
                        activity = activity,
                        color = activityColor,
                        pixelStyle = pixelSpaceSkin,
                        dotMatrixStyle = dotMatrixSkin
                    )
                    Spacer(Modifier.width(18.dp))
                    Column {
                        Text(activityTitle, color = activityColor, fontSize = 34.sp, fontWeight = FontWeight.Medium)
                        Text(remoteBridge.message, color = TextPrimary, fontSize = 20.sp, maxLines = 1)
                    }
                }
                remoteBridge.pendingApproval?.let { approval ->
                    Spacer(Modifier.height(14.dp))
                    ApprovalPrompt(
                        approval = approval,
                        onDecision = { decision, requestKey -> remoteBridge.sendCodexApproval(decision, requestKey) }
                    )
                }
                Spacer(Modifier.weight(1f))
                if (!pixelSpaceSkin) {
                    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        UsageGauge(
                            label = "5-hour remaining",
                            remaining = fiveHourRemaining,
                            dotStyle = dotMatrixSkin,
                            dotTint = DotMatrixCyan
                        )
                        UsageGauge(
                            label = "1-week remaining",
                            remaining = weeklyRemaining,
                            dotStyle = dotMatrixSkin,
                            dotTint = DotMatrixPurple
                        )
                    }
                }
                Spacer(Modifier.weight(0.65f))
                Row(horizontalArrangement = Arrangement.spacedBy(22.dp)) {
                    StatusLine(
                        "Mac bridge",
                        if (remoteBridge.connectionState == RemoteConnectionState.Connected) Green else TextMuted
                    )
                    StatusLine("Codex App Server", if (remoteBridge.codexConnected) Green else TextMuted)
                    StatusLine("Activity: $activityTitle", activityColor)
                }
                Spacer(Modifier.height(18.dp))
            }
        }
    }
    }
}

@Composable
private fun ControlCabinetCodexStatusPage(
    remoteBridge: RemoteBridgeClient,
    activity: String,
    activityTitle: String,
    activityColor: Color,
    nowEpochSeconds: Long
) {
    val portrait = LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT
    BoxWithConstraints(Modifier.fillMaxSize().background(CabinetPanel)) {
        Image(
            painter = painterResource(R.drawable.control_cabinet_background),
            contentDescription = null,
            contentScale = ContentScale.FillBounds,
            modifier = Modifier.fillMaxSize()
        )
        val horizontalInset = maxWidth * 0.095f
        val verticalInset = if (portrait) 20.dp else maxHeight * 0.09f
        val summary: @Composable () -> Unit = {
            Text("CODEX", color = CabinetAmber, fontSize = 28.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
            StatusLine(if (remoteBridge.codexConnected) "Codex connected" else "Codex unavailable", if (remoteBridge.codexConnected) Green else TextMuted)
            Spacer(Modifier.height(16.dp))
            Text("REMAINING USAGE", color = TextMuted, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
            Spacer(Modifier.height(10.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                for ((label, remaining, resetAt) in listOf(
                    Triple("5-hour", remoteBridge.fiveHourRemainingPercent, remoteBridge.fiveHourResetsAt),
                    Triple("1-week", remoteBridge.remainingPercent, remoteBridge.resetsAt)
                )) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(label, color = TextMuted, fontSize = 12.sp)
                        Text(remaining?.let { "$it%" } ?: "—", color = usageGaugeColor(remaining), fontSize = 30.sp, fontFamily = FontFamily.Monospace)
                        Text(formatResetTime(resetAt, includeDate = label == "1-week"), color = TextPrimary, fontSize = 13.sp)
                        Text(formatRemainingDuration(resetAt, nowEpochSeconds), color = TextMuted, fontSize = 12.sp)
                    }
                }
            }
        }
        val status: @Composable () -> Unit = {
            Text("CODEX STATUS", color = CabinetAmber, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ControlCabinetMotion(activity, activityColor)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(activityTitle, color = activityColor, fontSize = if (activity == "waitingForApproval") 18.sp else 25.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
                    Text(remoteBridge.message, color = TextPrimary, fontSize = 14.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
            remoteBridge.pendingApproval?.let { approval ->
                ApprovalPrompt(approval) { decision, requestKey -> remoteBridge.sendCodexApproval(decision, requestKey) }
            }
            ControlCabinetUsageGauge("5-hour remaining", remoteBridge.fiveHourRemainingPercent, remoteBridge.fiveHourResetsAt, false, nowEpochSeconds)
            ControlCabinetUsageGauge("1-week remaining", remoteBridge.remainingPercent, remoteBridge.resetsAt, true, nowEpochSeconds)
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                StatusLine("Mac bridge", if (remoteBridge.connectionState == RemoteConnectionState.Connected) Green else TextMuted)
                StatusLine("Codex App Server", if (remoteBridge.codexConnected) Green else TextMuted)
            }
        }
        val panel = Modifier.background(CabinetPanel.copy(alpha = 0.90f), RoundedCornerShape(4.dp))
            .border(1.dp, CabinetFrame, RoundedCornerShape(4.dp)).padding(16.dp)
        if (portrait) {
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = horizontalInset, vertical = verticalInset),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Column(Modifier.fillMaxWidth().then(panel)) { summary() }
                Column(Modifier.fillMaxWidth().then(panel), verticalArrangement = Arrangement.spacedBy(12.dp)) { status() }
            }
        } else {
            Row(
                Modifier.fillMaxSize().padding(horizontal = horizontalInset, vertical = verticalInset),
                horizontalArrangement = Arrangement.spacedBy(18.dp)
            ) {
                Column(Modifier.weight(0.43f).fillMaxHeight().then(panel).verticalScroll(rememberScrollState())) { summary() }
                Column(
                    Modifier.weight(0.57f).fillMaxHeight().then(panel).verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) { status() }
            }
        }
    }
}

@Composable
private fun ControlCabinetMotion(activity: String, color: Color) {
    val running = activity == "running"
    val phase = if (running) {
        val motion = rememberInfiniteTransition(label = "cabinet-running")
        val value by motion.animateFloat(
            initialValue = 0f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(tween(1800, easing = LinearEasing), RepeatMode.Restart),
            label = "cabinet-rotor-leds"
        )
        value
    } else 0f
    Canvas(Modifier.size(width = 68.dp, height = 82.dp)) {
        val center = Offset(size.width / 2f, 32.dp.toPx())
        val radius = 25.dp.toPx()
        drawCircle(Black, radius, center)
        drawCircle(CabinetFrame, radius, center, style = Stroke(2.dp.toPx()))
        rotate(phase * 360f, center) {
            repeat(6) { index ->
                rotate(index * 60f, center) {
                    drawLine(color.copy(alpha = 0.8f), center + Offset(8.dp.toPx(), 0f), center + Offset(19.dp.toPx(), 5.dp.toPx()), 6.dp.toPx(), StrokeCap.Round)
                }
            }
        }
        drawCircle(CabinetFrame, 6.dp.toPx(), center)
        drawCircle(color, 2.dp.toPx(), center)
        repeat(6) { index ->
            val lit = if (running) index == (phase * 6).toInt().coerceAtMost(5) else index == 0
            val position = Offset(9.dp.toPx() + index * 10.dp.toPx(), 73.dp.toPx())
            if (lit) drawCircle(color.copy(alpha = 0.15f), 5.dp.toPx(), position)
            drawCircle(if (lit) color else CabinetFrame.copy(alpha = 0.5f), 2.5.dp.toPx(), position)
        }
    }
}

@Composable
private fun PortraitCodexStatusPage(
    remoteBridge: RemoteBridgeClient,
    activity: String,
    activityTitle: String,
    activityColor: Color,
    nowEpochSeconds: Long,
    pixelSpaceSkin: Boolean,
    dotMatrixSkin: Boolean,
    fiveHourRemaining: Int?,
    weeklyRemaining: Int?
) {
    Box(Modifier.fillMaxSize()) {
        if (pixelSpaceSkin) {
            Image(
                painter = painterResource(R.drawable.codex_pixel_space_background),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
            Box(Modifier.fillMaxSize().background(Black.copy(alpha = 0.24f)))
            if (activity == "running") PixelSpaceMotionOverlay(Modifier.fillMaxSize())
        } else if (dotMatrixSkin) {
            DotMatrixBackdrop(Modifier.fillMaxSize())
        }
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(start = 18.dp, top = MainContentTopPadding, end = 18.dp, bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("CODEX", color = TextPrimary, fontSize = 24.sp, fontWeight = FontWeight.Medium)
                Text(
                    if (remoteBridge.codexConnected) "Codex connected" else "Codex unavailable",
                    color = TextMuted,
                    fontSize = 14.sp
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                StatusMotion(
                    activity = activity,
                    color = activityColor,
                    pixelStyle = pixelSpaceSkin,
                    dotMatrixStyle = dotMatrixSkin
                )
                Spacer(Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("Codex status", color = TextMuted, fontSize = 12.sp)
                    Text(
                        activityTitle,
                        color = activityColor,
                        fontSize = 23.sp,
                        fontWeight = FontWeight.Medium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        remoteBridge.message,
                        color = TextPrimary,
                        fontSize = 14.sp,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            remoteBridge.pendingApproval?.let { approval ->
                ApprovalPrompt(approval = approval) { decision, requestKey -> remoteBridge.sendCodexApproval(decision, requestKey) }
            }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Remaining usage", color = TextMuted, fontSize = 14.sp)
                UsageGauge(
                    label = "1-week remaining",
                    remaining = weeklyRemaining,
                    dotStyle = dotMatrixSkin,
                    dotTint = DotMatrixPurple
                )
                UsageResetInfo(remoteBridge.resetsAt, true, nowEpochSeconds, TextPrimary, TextMuted)
                UsageGauge(
                    label = "5-hour remaining",
                    remaining = fiveHourRemaining,
                    dotStyle = dotMatrixSkin,
                    dotTint = DotMatrixCyan
                )
                UsageResetInfo(remoteBridge.fiveHourResetsAt, false, nowEpochSeconds, TextPrimary, TextMuted)
            }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Connections", color = TextMuted, fontSize = 12.sp)
                StatusLine(
                    "Mac bridge",
                    if (remoteBridge.connectionState == RemoteConnectionState.Connected) Green else TextMuted
                )
                StatusLine("Codex App Server", if (remoteBridge.codexConnected) Green else TextMuted)
                StatusLine("Activity: $activityTitle", activityColor)
            }
        }
    }
}

@Composable
private fun PixelQuestCodexStatusPage(
    remoteBridge: RemoteBridgeClient,
    activity: String,
    activityTitle: String,
    activityColor: Color,
    nowEpochSeconds: Long
) {
    val isPortrait = LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT
    Box(Modifier.fillMaxSize().background(PixelQuestBackground)) {
        Canvas(Modifier.fillMaxSize()) {
            val tile = 24.dp.toPx()
            val columns = (size.width / tile).toInt() + 1
            val rows = (size.height / tile).toInt() + 1
            repeat(rows) { row ->
                repeat(columns) { column ->
                    if ((column * 13 + row * 7) % 41 == 0) {
                        drawRect(
                            color = PixelQuestFrame.copy(alpha = 0.16f),
                            topLeft = Offset(column * tile + tile / 2f, row * tile + tile / 2f),
                            size = Size(2.dp.toPx(), 2.dp.toPx())
                        )
                    }
                }
            }
        }
        Column(
            modifier = Modifier
                .fillMaxSize()
                .then(if (isPortrait) Modifier.verticalScroll(rememberScrollState()) else Modifier)
                .padding(horizontal = if (isPortrait) 18.dp else 24.dp, vertical = 14.dp),
            verticalArrangement = if (isPortrait) Arrangement.spacedBy(14.dp) else Arrangement.SpaceBetween
        ) {
            if (isPortrait) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Column {
                        Text("CODEX QUEST", color = PixelQuestGold, fontSize = 19.sp, fontWeight = FontWeight.Bold)
                        Text("ARCADE STATUS // LIVE", color = PixelQuestMuted, fontSize = 10.sp)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        PixelQuestConnectionTag(
                            label = "MAC LINK",
                            connected = remoteBridge.connectionState == RemoteConnectionState.Connected
                        )
                        PixelQuestConnectionTag(label = "CODEX SERVER", connected = remoteBridge.codexConnected)
                    }
                }
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column {
                        Text("CODEX QUEST", color = PixelQuestGold, fontSize = 19.sp, fontWeight = FontWeight.Bold)
                        Text("ARCADE STATUS // LIVE", color = PixelQuestMuted, fontSize = 10.sp)
                    }
                    Spacer(Modifier.weight(1f))
                    PixelQuestConnectionTag(
                        label = "MAC LINK",
                        connected = remoteBridge.connectionState == RemoteConnectionState.Connected
                    )
                    Spacer(Modifier.width(12.dp))
                    PixelQuestConnectionTag(label = "CODEX SERVER", connected = remoteBridge.codexConnected)
                }
            }

            PixelQuestStagePanel(
                activity = activity,
                activityTitle = activityTitle,
                activityColor = activityColor,
                message = remoteBridge.message,
                isPortrait = isPortrait,
                modifier = if (isPortrait) {
                    Modifier.fillMaxWidth().height(230.dp)
                } else {
                    Modifier.fillMaxWidth().weight(1f).padding(vertical = 12.dp)
                }
            )
            remoteBridge.pendingApproval?.let { approval ->
                ApprovalPrompt(approval = approval) { decision, requestKey -> remoteBridge.sendCodexApproval(decision, requestKey) }
            }

            if (isPortrait) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    PixelQuestUsageCard(
                        label = "1-WEEK QUEST",
                        remaining = remoteBridge.remainingPercent,
                        resetAt = remoteBridge.resetsAt,
                        includeDate = true,
                        nowEpochSeconds = nowEpochSeconds,
                        accent = PixelQuestGold,
                        modifier = Modifier.fillMaxWidth()
                    )
                    PixelQuestUsageCard(
                        label = "5-HOUR QUEST",
                        remaining = remoteBridge.fiveHourRemainingPercent,
                        resetAt = remoteBridge.fiveHourResetsAt,
                        includeDate = false,
                        nowEpochSeconds = nowEpochSeconds,
                        accent = PixelQuestCoral,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    PixelQuestUsageCard(
                        label = "5-HOUR QUEST",
                        remaining = remoteBridge.fiveHourRemainingPercent,
                        resetAt = remoteBridge.fiveHourResetsAt,
                        includeDate = false,
                        nowEpochSeconds = nowEpochSeconds,
                        accent = PixelQuestCoral,
                        modifier = Modifier.weight(1f)
                    )
                    PixelQuestUsageCard(
                        label = "1-WEEK QUEST",
                        remaining = remoteBridge.remainingPercent,
                        resetAt = remoteBridge.resetsAt,
                        includeDate = true,
                        nowEpochSeconds = nowEpochSeconds,
                        accent = PixelQuestGold,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }
}

@Composable
private fun PixelQuestConnectionTag(label: String, connected: Boolean) {
    val accent = if (connected) PixelQuestMint else PixelQuestMuted
    Row(
        modifier = Modifier
            .background(PixelQuestPanel, RoundedCornerShape(3.dp))
            .border(1.dp, PixelQuestFrame, RoundedCornerShape(3.dp))
            .padding(horizontal = 10.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp)
    ) {
        Canvas(Modifier.size(7.dp)) {
            drawRect(accent, size = size)
        }
        Text(label, color = accent, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1)
    }
}

@Composable
private fun PixelQuestStagePanel(
    activity: String,
    activityTitle: String,
    activityColor: Color,
    message: String,
    isPortrait: Boolean,
    modifier: Modifier = Modifier
) {
    Box(
        modifier
            .background(PixelQuestPanel, RoundedCornerShape(5.dp))
            .border(2.dp, PixelQuestFrame, RoundedCornerShape(5.dp))
    ) {
        PixelQuestRouteCanvas(activity, activityColor, Modifier.fillMaxSize())
        Column(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .fillMaxWidth(if (isPortrait) 0.92f else 0.66f)
                .padding(start = if (isPortrait) 16.dp else 28.dp, end = 8.dp)
        ) {
            Text("CURRENT STAGE  /  01", color = PixelQuestMuted, fontSize = 11.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(7.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                PixelQuestStatusMark(activity, activityColor, Modifier.size(if (isPortrait) 28.dp else 34.dp))
                Spacer(Modifier.width(12.dp))
                Text(
                    activityTitle,
                    color = activityColor,
                    fontSize = if (isPortrait) 21.sp else 29.sp,
                    fontWeight = FontWeight.Black,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Spacer(Modifier.height(7.dp))
            Text(
                message.ifBlank { "Waiting for Codex activity" },
                color = PixelQuestMuted,
                fontSize = if (isPortrait) 14.sp else 16.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
        Text(
            "QUEST 01",
            color = PixelQuestGold,
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.align(Alignment.TopEnd).padding(14.dp)
        )
    }
}

@Composable
private fun PixelQuestRouteCanvas(activity: String, color: Color, modifier: Modifier = Modifier) {
    val motion = rememberInfiniteTransition(label = "pixel-quest-route")
    val phase by motion.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(2_100, easing = LinearEasing), RepeatMode.Restart),
        label = "pixel-quest-route-phase"
    )
    val glow by motion.animateFloat(
        initialValue = 0.45f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(850), RepeatMode.Reverse),
        label = "pixel-quest-route-glow"
    )
    Canvas(modifier) {
        val tile = 30.dp.toPx()
        val columns = (size.width / tile).toInt() + 1
        val rows = (size.height / tile).toInt() + 1
        repeat(rows) { row ->
            repeat(columns) { column ->
                val topLeft = Offset(column * tile, row * tile)
                if ((column + row) % 2 == 0) {
                    drawRect(
                        color = PixelQuestBackground.copy(alpha = 0.3f),
                        topLeft = topLeft,
                        size = Size(tile, tile)
                    )
                }
                drawRect(
                    color = PixelQuestFrame.copy(alpha = 0.22f),
                    topLeft = topLeft,
                    size = Size(tile, tile),
                    style = Stroke(width = 1.dp.toPx())
                )
            }
        }
        val points = listOf(
            Offset(size.width * 0.61f, size.height * 0.82f),
            Offset(size.width * 0.61f, size.height * 0.64f),
            Offset(size.width * 0.72f, size.height * 0.64f),
            Offset(size.width * 0.72f, size.height * 0.38f),
            Offset(size.width * 0.84f, size.height * 0.38f),
            Offset(size.width * 0.84f, size.height * 0.73f),
            Offset(size.width * 0.94f, size.height * 0.73f),
            Offset(size.width * 0.94f, size.height * 0.5f)
        )
        points.zipWithNext().forEach { (start, end) ->
            val steps = (maxOf(kotlin.math.abs(end.x - start.x), kotlin.math.abs(end.y - start.y)) / 6.dp.toPx())
                .toInt()
                .coerceAtLeast(1)
            repeat(steps) { dot ->
                if (dot % 2 == 0) {
                    val t = dot / steps.toFloat()
                    drawRect(
                        color = color.copy(alpha = if (dot % 4 == 0) 0.8f else 0.42f),
                        topLeft = Offset(start.x + (end.x - start.x) * t, start.y + (end.y - start.y) * t),
                        size = Size(3.dp.toPx(), 3.dp.toPx())
                    )
                }
            }
        }
        val progress = if (activity == "running") phase else if (activity == "completed") 1f else 0.58f
        val segmentPosition = progress * (points.size - 1)
        val segment = segmentPosition.toInt().coerceAtMost(points.lastIndex - 1)
        val segmentProgress = segmentPosition - segment
        val start = points[segment]
        val end = points[segment + 1]
        val marker = Offset(
            start.x + (end.x - start.x) * segmentProgress,
            start.y + (end.y - start.y) * segmentProgress
        )
        if (activity == "running") {
            val pixel = 6.dp.toPx()
            drawRect(color.copy(alpha = glow), Offset(marker.x - pixel / 2f, marker.y - pixel / 2f), Size(pixel, pixel))
            drawRect(color.copy(alpha = glow * 0.7f), Offset(marker.x - pixel * 1.5f, marker.y - pixel / 2f), Size(pixel, pixel))
            drawRect(color.copy(alpha = glow * 0.45f), Offset(marker.x - pixel / 2f, marker.y - pixel * 1.5f), Size(pixel, pixel))
        } else if (activity == "completed") {
            drawRect(PixelQuestMint.copy(alpha = glow), Offset(marker.x - 5.dp.toPx(), marker.y - 5.dp.toPx()), Size(10.dp.toPx(), 10.dp.toPx()))
        } else {
            drawRect(color.copy(alpha = glow), Offset(marker.x - 4.dp.toPx(), marker.y - 4.dp.toPx()), Size(8.dp.toPx(), 8.dp.toPx()))
        }
        val gate = points.last()
        drawRect(PixelQuestGold.copy(alpha = 0.78f), Offset(gate.x - 7.dp.toPx(), gate.y - 9.dp.toPx()), Size(3.dp.toPx(), 18.dp.toPx()))
        drawRect(PixelQuestGold.copy(alpha = 0.78f), Offset(gate.x + 4.dp.toPx(), gate.y - 9.dp.toPx()), Size(3.dp.toPx(), 18.dp.toPx()))
        drawRect(PixelQuestGold.copy(alpha = 0.78f), Offset(gate.x - 7.dp.toPx(), gate.y - 9.dp.toPx()), Size(14.dp.toPx(), 3.dp.toPx()))
    }
}

@Composable
private fun PixelQuestStatusMark(activity: String, color: Color, modifier: Modifier = Modifier.size(34.dp)) {
    val motion = rememberInfiniteTransition(label = "pixel-quest-mark-$activity")
    val scan by motion.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1_400, easing = LinearEasing), RepeatMode.Restart),
        label = "pixel-quest-mark-scan"
    )
    Canvas(modifier) {
        val cell = size.minDimension / 7f
        val pitch = cell * 1.28f
        val gridSize = pitch * 5 - cell * 0.28f
        val originX = (size.width - gridSize) / 2f
        val originY = (size.height - gridSize) / 2f
        val check = listOf(0 to 2, 1 to 3, 2 to 2, 3 to 1, 4 to 0)
        repeat(5) { row ->
            repeat(5) { column ->
                val active = when (activity) {
                    "completed" -> (column to row) in check
                    "failed" -> row == column || row + column == 4
                    "waitingForApproval" -> (column == 2 && row in 0..3) || (row == 4 && column == 2)
                    "running" -> row == 2 && column in 1..3
                    else -> row == 0 || row == 4 || column == 0 || column == 4
                }
                if (active) {
                    val left = originX + column * pitch
                    val top = originY + row * pitch
                    drawRect(color, Offset(left, top), Size(cell, cell))
                    if (activity == "completed") {
                        val scanY = originY + scan * gridSize
                        if (scanY in top..(top + cell)) {
                            drawRect(
                                Color.White.copy(alpha = 0.48f),
                                Offset(left, scanY),
                                Size(cell, 1.dp.toPx())
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PixelQuestUsageCard(
    label: String,
    remaining: Int?,
    resetAt: Double?,
    includeDate: Boolean,
    nowEpochSeconds: Long,
    accent: Color,
    modifier: Modifier = Modifier
) {
    Column(
        modifier
            .height(130.dp)
            .background(PixelQuestPanel, RoundedCornerShape(4.dp))
            .border(2.dp, PixelQuestFrame, RoundedCornerShape(4.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Canvas(Modifier.size(8.dp)) { drawRect(accent, size = size) }
            Spacer(Modifier.width(7.dp))
            Text(label, color = PixelQuestMuted, fontSize = 11.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.weight(1f))
            Text(remaining?.let { "$it%" } ?: "—", color = accent, fontSize = 23.sp, fontWeight = FontWeight.Black)
        }
        PixelQuestUsageBar(remaining, accent)
        UsageResetInfo(resetAt, includeDate, nowEpochSeconds)
    }
}

@Composable
private fun PixelQuestUsageProgress(
    label: String,
    remaining: Int?,
    resetAt: Double?,
    includeDate: Boolean,
    nowEpochSeconds: Long,
    accent: Color
) {
    Column(Modifier.fillMaxWidth().padding(horizontal = UsagePanelHorizontalPadding, vertical = UsagePanelVerticalPadding), verticalArrangement = Arrangement.spacedBy(UsagePanelContentGap)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Canvas(Modifier.size(8.dp)) { drawRect(accent, size = size) }
            Spacer(Modifier.width(7.dp))
            Text(label, color = PixelQuestMuted, fontSize = 11.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.weight(1f))
            Text(remaining?.let { "$it%" } ?: "—", color = accent, fontSize = 23.sp, fontWeight = FontWeight.Black)
        }
        PixelQuestUsageBar(remaining, accent)
        UsageResetInfo(resetAt, includeDate, nowEpochSeconds)
    }
}

@Composable
private fun UsageResetInfo(resetAt: Double?, includeDate: Boolean, nowEpochSeconds: Long, timeColor: Color = PixelQuestMuted, remainingColor: Color = PixelQuestGold) {
    val fontSize = if (LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT) PortraitUsageResetFontSize else LandscapeUsageResetFontSize
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            formatResetTime(resetAt, includeDate),
            modifier = Modifier.weight(1f),
            color = timeColor,
            fontSize = fontSize,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            formatRemainingDuration(resetAt, nowEpochSeconds),
            modifier = Modifier.weight(1f),
            color = remainingColor,
            fontSize = fontSize,
            fontWeight = FontWeight.Medium,
            textAlign = TextAlign.End,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun PixelQuestUsageBar(remaining: Int?, accent: Color, modifier: Modifier = Modifier) {
    val progress = (remaining ?: 0).coerceIn(0, 100) / 100f
    Canvas(modifier.fillMaxWidth().height(8.dp)) {
        val count = 24
        val gap = 2.dp.toPx()
        val segmentWidth = (size.width - gap * (count - 1)) / count
        val filled = (progress * count).roundToInt()
        repeat(count) { index ->
            drawRect(
                color = if (index < filled) accent else PixelQuestBackground,
                topLeft = Offset(index * (segmentWidth + gap), 0f),
                size = Size(segmentWidth, size.height)
            )
        }
    }
}

@Composable
private fun DotMatrixBackdrop(modifier: Modifier = Modifier) {
    Canvas(modifier.background(DotMatrixBackgroundColor)) {
        val spacing = 28.dp.toPx()
        val radius = 1.2.dp.toPx()
        val columns = (size.width / spacing).toInt() + 1
        val rows = (size.height / spacing).toInt() + 1
        repeat(rows) { row ->
            repeat(columns) { column ->
                val accent = (column * 7 + row * 11) % 37 == 0
                val color = when {
                    !accent -> DotMatrixGridColor.copy(alpha = 0.62f)
                    (column + row) % 2 == 0 -> DotMatrixCyan.copy(alpha = 0.66f)
                    else -> DotMatrixPink.copy(alpha = 0.58f)
                }
                drawCircle(
                    color = color,
                    radius = if (accent) radius * 1.8f else radius,
                    center = Offset(column * spacing + spacing / 2f, row * spacing + spacing / 2f)
                )
            }
        }
    }
}

@Composable
private fun PixelSpaceMotionOverlay(modifier: Modifier = Modifier) {
    val motion = rememberInfiniteTransition(label = "pixel-space-environment")
    val phase by motion.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(2_400, easing = LinearEasing), RepeatMode.Restart),
        label = "pixel-space-data-flow"
    )
    val twinkle by motion.animateFloat(
        initialValue = 0.15f,
        targetValue = 0.9f,
        animationSpec = infiniteRepeatable(tween(700), RepeatMode.Reverse),
        label = "pixel-space-star-twinkle"
    )
    Canvas(modifier) {
        val railY = size.height * 0.61f
        val railStart = size.width * 0.28f
        val railWidth = size.width * 0.68f
        val pixel = 5.dp.toPx()
        repeat(3) { index ->
            val progress = (phase + index / 3f) % 1f
            val fade = minOf(1f, progress * 4f, (1f - progress) * 4f)
            val x = railStart + railWidth * progress
            drawRect(
                color = PixelSpaceMint.copy(alpha = fade * 0.82f),
                topLeft = Offset(x, railY),
                size = Size(pixel, pixel)
            )
            drawRect(
                color = PixelSpaceViolet.copy(alpha = fade * 0.58f),
                topLeft = Offset(x - 11.dp.toPx(), railY + 4.dp.toPx()),
                size = Size(6.dp.toPx(), 2.dp.toPx())
            )
        }
        drawRect(
            color = PixelSpaceMint.copy(alpha = twinkle),
            topLeft = Offset(size.width * 0.43f, size.height * 0.2f),
            size = Size(3.dp.toPx(), 3.dp.toPx())
        )
        drawRect(
            color = PixelSpaceViolet.copy(alpha = 0.2f + twinkle * 0.6f),
            topLeft = Offset(size.width * 0.72f, size.height * 0.31f),
            size = Size(2.dp.toPx(), 2.dp.toPx())
        )
    }
}

private fun DrawScope.drawPixelSpinner(color: Color, rotation: Float) {
    val iconSize = size.minDimension
    val center = Offset(size.width / 2f, size.height / 2f)
    val pixel = iconSize * 0.13f
    val radius = iconSize * 0.36f
    repeat(8) { index ->
        val angle = Math.toRadians((rotation - index * 45f).toDouble())
        val x = (center.x + cos(angle).toFloat() * radius - pixel / 2f).roundToInt().toFloat()
        val y = (center.y + sin(angle).toFloat() * radius - pixel / 2f).roundToInt().toFloat()
        drawRect(
            color = color.copy(alpha = 1f - index * 0.055f),
            topLeft = Offset(x, y),
            size = Size(pixel, pixel)
        )
    }
    val centerPixel = iconSize * 0.17f
    drawRect(
        color = color,
        topLeft = Offset(center.x - centerPixel / 2f, center.y - centerPixel / 2f),
        size = Size(centerPixel, centerPixel)
    )
}

@Composable
private fun ApprovalPrompt(
    approval: RemoteApproval,
    onDecision: (String, String?) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, GaugeMid, RoundedCornerShape(3.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(7.dp)
    ) {
        Text(approval.title, color = GaugeMid, fontSize = 16.sp, fontWeight = FontWeight.Medium)
        Text(
            approval.detail,
            color = TextPrimary,
            fontSize = 12.sp,
            maxLines = 3,
            lineHeight = 16.sp
        )
        if (approval.canRespond) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                androidx.compose.material3.Surface(
                    onClick = { onDecision("accept", approval.requestKey) },
                    color = GaugeHigh,
                    contentColor = TextPrimary,
                    shape = RoundedCornerShape(3.dp),
                    modifier = Modifier.height(34.dp)
                ) {
                    Box(
                        modifier = Modifier.padding(horizontal = 20.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("승인", fontSize = 13.sp, fontWeight = FontWeight.Medium)
                    }
                }
                androidx.compose.material3.Surface(
                    onClick = { onDecision("decline", approval.requestKey) },
                    color = Tile,
                    contentColor = Red,
                    shape = RoundedCornerShape(3.dp),
                    modifier = Modifier
                        .height(34.dp)
                        .border(1.dp, Red, RoundedCornerShape(3.dp))
                ) {
                    Box(
                        modifier = Modifier.padding(horizontal = 20.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("거절", fontSize = 13.sp, fontWeight = FontWeight.Medium)
                    }
                }
            }
        } else {
            Text("Mac에서 승인 요청을 확인해 주세요.", color = TextMuted, fontSize = 12.sp)
        }
    }
}

@Composable
private fun ApprovalRequestDialog(
    approval: RemoteApproval,
    onDecision: (String, String?) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = { if (!approval.canRespond) onDismiss() },
        containerColor = Tile,
        titleContentColor = TextPrimary,
        textContentColor = TextPrimary,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                StatusMotion(activity = "waitingForApproval", color = GaugeMid)
                Spacer(Modifier.width(12.dp))
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("Codex 승인 대기", color = GaugeMid, fontSize = 20.sp, fontWeight = FontWeight.Medium)
                    Text("확인이 필요한 작업입니다", color = TextMuted, fontSize = 13.sp)
                }
            }
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(approval.title, color = TextPrimary, fontSize = 16.sp, fontWeight = FontWeight.Medium)
                Text(
                    approval.detail,
                    color = TextPrimary,
                    fontSize = 13.sp,
                    lineHeight = 18.sp
                )
            }
        },
        confirmButton = {
            if (approval.canRespond) {
                TextButton(onClick = { onDecision("accept", approval.requestKey) }) {
                    Text("승인", color = GaugeHigh, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                }
            } else {
                TextButton(onClick = onDismiss) {
                    Text("확인", color = Green, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                }
            }
        },
        dismissButton = {
            if (approval.canRespond) {
                TextButton(onClick = { onDecision("decline", approval.requestKey) }) {
                    Text("거절", color = Red, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                }
            }
        }
    )
}

@Composable
private fun StatusMotion(
    activity: String,
    color: Color,
    pixelStyle: Boolean = false,
    dotMatrixStyle: Boolean = false
) {
    val normalizedActivity = normalizeRemoteActivity(activity)
    if (dotMatrixStyle) {
        DotMatrixStatusMotion(normalizedActivity, color)
        return
    }
    val motion = rememberInfiniteTransition(label = "codex-status-$normalizedActivity")
    val rotation by motion.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(1600), RepeatMode.Restart),
        label = "status-rotation"
    )
    val pulse by motion.animateFloat(
        initialValue = 0.82f,
        targetValue = 1.08f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "status-pulse"
    )
    val shake by motion.animateFloat(
        initialValue = -3f,
        targetValue = 3f,
        animationSpec = infiniteRepeatable(tween(150), RepeatMode.Reverse),
        label = "status-shake"
    )
    Canvas(modifier = Modifier.size(64.dp)) {
        if (pixelStyle && normalizedActivity == "running") {
            drawPixelSpinner(color, rotation)
            return@Canvas
        }
        val center = Offset(size.width / 2f, size.height / 2f)
        val radius = size.minDimension * 0.27f
        when (normalizedActivity) {
            "running" -> {
                rotate(rotation, center) {
                    drawArc(
                        color = color,
                        startAngle = -70f,
                        sweepAngle = 235f,
                        useCenter = false,
                        style = Stroke(width = size.minDimension * 0.055f, cap = StrokeCap.Round)
                    )
                }
                drawCircle(color = color.copy(alpha = 0.18f), radius = radius * pulse, center = center)
                drawCircle(color = color, radius = radius * 0.58f, center = center)
            }
            "waitingForApproval" -> {
                drawCircle(
                    color = color.copy(alpha = 0.38f),
                    radius = radius * pulse,
                    center = center,
                    style = Stroke(width = size.minDimension * 0.055f)
                )
                drawCircle(color = color.copy(alpha = 0.85f), radius = radius * 0.5f, center = center)
            }
            "completed" -> {
                drawCircle(
                    color = color.copy(alpha = 0.25f),
                    radius = radius * 1.15f,
                    center = center,
                    style = Stroke(width = size.minDimension * 0.04f)
                )
                drawCircle(color = color, radius = radius, center = center, style = Stroke(width = size.minDimension * 0.055f))
                val start = Offset(center.x - radius * 0.52f, center.y)
                val middle = Offset(center.x - radius * 0.1f, center.y + radius * 0.42f)
                val end = Offset(center.x + radius * 0.62f, center.y - radius * 0.45f)
                drawLine(start = start, end = middle, color = color, strokeWidth = size.minDimension * 0.07f, cap = StrokeCap.Round)
                drawLine(start = middle, end = end, color = color, strokeWidth = size.minDimension * 0.07f, cap = StrokeCap.Round)
            }
            "failed" -> {
                translate(left = shake) {
                    drawCircle(color = color.copy(alpha = 0.22f), radius = radius * 1.2f, center = center)
                    drawCircle(color = color, radius = radius, center = center, style = Stroke(width = size.minDimension * 0.055f))
                    drawLine(
                        start = Offset(center.x, center.y - radius * 0.5f),
                        end = Offset(center.x, center.y + radius * 0.14f),
                        color = color,
                        strokeWidth = size.minDimension * 0.07f,
                        cap = StrokeCap.Round
                    )
                    drawCircle(color = color, radius = size.minDimension * 0.04f, center = Offset(center.x, center.y + radius * 0.5f))
                }
            }
            else -> drawCircle(color = color, radius = radius * 0.72f, center = center)
        }
    }
}

@Composable
private fun DotMatrixStatusMotion(
    activity: String,
    color: Color,
    modifier: Modifier = Modifier.size(64.dp)
) {
    val motion = rememberInfiniteTransition(label = "dot-matrix-status-$activity")
    val phase by motion.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1_100), RepeatMode.Reverse),
        label = "dot-matrix-status-phase"
    )
    val glow by motion.animateFloat(
        initialValue = 0.68f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "dot-matrix-status-glow"
    )
    Canvas(modifier) {
        val cell = size.minDimension / 10f
        val gap = cell * 0.35f
        val pitch = cell + gap
        val gridSize = pitch * 5 - gap
        val originX = (size.width - gridSize) / 2f
        val originY = (size.height - gridSize) / 2f
        val cellSize = cell * 0.92f
        val checkPixels = listOf(0 to 2, 1 to 3, 2 to 2, 3 to 1, 4 to 0)

        drawRect(
            color = DotMatrixBackgroundColor.copy(alpha = 0.86f),
            topLeft = Offset(originX - gap * 2, originY - gap * 2),
            size = Size(gridSize + gap * 4, gridSize + gap * 4)
        )
        repeat(5) { row ->
            repeat(5) { column ->
                val topLeft = Offset(originX + column * pitch, originY + row * pitch)
                drawRect(DotMatrixGridColor, topLeft, Size(cellSize, cellSize))
                val active = when (activity) {
                    "completed" -> (column to row) in checkPixels
                    "running" -> row * 5 + column < (phase * 25f).roundToInt()
                    "waitingForApproval" -> row == 2 || column == 2
                    "failed" -> row == column || row + column == 4
                    else -> row in 1..3 && column in 1..3
                }
                if (active) {
                    drawRect(
                        color = color.copy(alpha = if (activity == "completed") glow else 0.7f + 0.3f * glow),
                        topLeft = topLeft,
                        size = Size(cellSize, cellSize)
                    )
                }
            }
        }
    }
}

@Composable
private fun PhoneUsageGauge(phoneTheme: String, label: String, remaining: Int?, resetAt: Double?, includeDate: Boolean, nowEpochSeconds: Long) {
    val skin = phoneSkinStyle(phoneTheme)
    val dotMatrix = phoneTheme == DotMatrixCodexPhoneTheme
    val pixelSpace = phoneTheme == PixelSpaceCodexPhoneTheme
    val accent = if (dotMatrix) {
        if (includeDate) DotMatrixPurple else DotMatrixCyan
    } else if (pixelSpace) {
        if (includeDate) PixelSpaceViolet else PixelSpaceMint
    } else TextPrimary
    val themed = dotMatrix || pixelSpace
    val shape = RoundedCornerShape(skin.cornerRadius)
    val panel = if (themed) {
        Modifier.background(skin.panel, shape)
            .border(1.dp, accent.copy(alpha = 0.55f), shape)
            .padding(horizontal = UsagePanelHorizontalPadding, vertical = UsagePanelVerticalPadding)
    } else Modifier.padding(horizontal = UsagePanelHorizontalPadding, vertical = UsagePanelVerticalPadding)
    Column(Modifier.fillMaxWidth().then(panel), verticalArrangement = Arrangement.spacedBy(UsagePanelContentGap)) {
        UsageGauge(label, remaining, dotStyle = themed, dotTint = if (themed) accent else null)
        UsageResetInfo(resetAt, includeDate, nowEpochSeconds, accent, TextMuted)
    }
}

@Composable
private fun ControlCabinetUsageGauge(label: String, remaining: Int?, resetAt: Double?, includeDate: Boolean, nowEpochSeconds: Long) {
    Box(
        Modifier.fillMaxWidth()
            .background(CabinetPanel, RoundedCornerShape(3.dp))
            .border(1.dp, CabinetFrame, RoundedCornerShape(3.dp))
            .drawBehind {
                val inset = 4.dp.toPx()
                for (x in listOf(inset, size.width - inset)) {
                    for (y in listOf(inset, size.height - inset)) {
                        drawCircle(CabinetFrame, 1.5.dp.toPx(), Offset(x, y))
                    }
                }
            }
            .padding(horizontal = UsagePanelHorizontalPadding, vertical = UsagePanelVerticalPadding)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(UsagePanelContentGap)) {
            UsageGauge(label, remaining, dotStyle = true)
            if (LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT) {
                UsageResetInfo(resetAt, includeDate, nowEpochSeconds, TextPrimary, TextMuted)
            }
        }
    }
}

@Composable
private fun UsageGauge(
    label: String,
    remaining: Int?,
    modifier: Modifier = Modifier,
    valueFontSizeSp: Int = 13,
    dotStyle: Boolean = false,
    dotTint: Color? = null
) {
    val tint = usageGaugeColor(remaining)
    val progress = (remaining ?: 0).coerceIn(0, 100) / 100f
    Column(modifier = modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(label, color = TextMuted, fontSize = 13.sp)
            Spacer(Modifier.weight(1f))
            Text(remaining?.let { "$it%" } ?: "—", color = tint, fontSize = valueFontSizeSp.sp)
        }
        Spacer(Modifier.height(6.dp))
        if (dotStyle) {
            Canvas(Modifier.fillMaxWidth().height(10.dp)) {
                val segmentCount = 28
                val gap = 2.dp.toPx()
                val segmentWidth = (size.width - gap * (segmentCount - 1)) / segmentCount
                val filledSegments = (progress * segmentCount).roundToInt()
                repeat(segmentCount) { index ->
                    drawRect(
                        color = if (index < filledSegments) dotTint ?: tint else GaugeTrack,
                        topLeft = Offset(index * (segmentWidth + gap), 0f),
                        size = Size(segmentWidth, size.height)
                    )
                }
            }
        } else {
            LinearProgressIndicator(
                progress = { progress },
                color = tint,
                trackColor = GaugeTrack,
                modifier = Modifier.fillMaxWidth().height(6.dp)
            )
        }
    }
}

private val koreaZone = ZoneId.of("Asia/Seoul")
private val resetTimeFormatter = DateTimeFormatter.ofPattern("M월 d일 HH:mm", Locale.KOREA)
private val resetClockFormatter = DateTimeFormatter.ofPattern("HH:mm", Locale.KOREA)

private fun formatResetTime(epochSeconds: Double?, includeDate: Boolean): String {
    val seconds = epochSeconds?.toLong() ?: return "—"
    return runCatching {
        val localTime = Instant.ofEpochSecond(seconds).atZone(koreaZone)
        if (includeDate) {
            localTime.format(resetTimeFormatter)
        } else {
            localTime.format(resetClockFormatter)
        }
    }.getOrDefault("—")
}

internal fun formatRemainingDuration(resetEpochSeconds: Double?, nowEpochSeconds: Long): String {
    val resetSeconds = resetEpochSeconds?.takeIf { it.isFinite() }?.toLong() ?: return "—"
    val remainingSeconds = resetSeconds - nowEpochSeconds
    if (remainingSeconds <= 0L) return "곧 갱신"

    val totalMinutes = (remainingSeconds + 59L) / 60L
    val minutesPerDay = 24L * 60L
    val days = totalMinutes / minutesPerDay
    val remainingMinutes = totalMinutes % minutesPerDay
    val hours = remainingMinutes / 60L
    val minutes = remainingMinutes % 60L

    if (days > 0L) {
        return when {
            hours > 0L -> "${days}일+${hours}시간"
            minutes > 0L -> "${days}일+${minutes}분"
            else -> "${days}일"
        }
    }
    return when {
        hours > 0L && minutes > 0L -> "${hours}시간 ${minutes}분"
        hours > 0L -> "${hours}시간"
        else -> "${minutes.coerceAtLeast(1L)}분"
    }
}

private fun usageGaugeColor(remaining: Int?): Color {
    val value = remaining?.coerceIn(0, 100) ?: return TextMuted
    return when {
        value <= 20 -> Red
        value <= 50 -> GaugeMid
        value <= 75 -> GaugeCool
        else -> GaugeHigh
    }
}

@Composable
private fun StatusLine(label: String, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 3.dp)) {
        Box(Modifier.size(5.dp).background(color, RoundedCornerShape(50)))
        Spacer(Modifier.width(7.dp))
        Text(label, color = color.copy(alpha = 0.8f), fontSize = 11.sp)
    }
}

internal fun horizontalSwipeCommitDistancePx(density: Float): Float {
    return HorizontalSwipeCommitDistanceDp * density.coerceAtLeast(0f)
}

internal fun horizontalSwipeTransitionDirection(dragDistance: Float): Int {
    return if (dragDistance < 0f) 1 else -1
}

internal fun horizontalSwipeTarget(
    currentIndex: Int,
    pageCount: Int,
    dragDistance: Float,
    commitDistancePx: Float = DefaultHorizontalSwipeCommitDistancePx
): Int {
    if (pageCount <= 0 || kotlin.math.abs(dragDistance) < commitDistancePx) return currentIndex.coerceIn(0, (pageCount - 1).coerceAtLeast(0))
    val normalizedIndex = currentIndex.coerceIn(0, pageCount - 1)
    return if (dragDistance < 0) {
        (normalizedIndex + 1) % pageCount
    } else {
        (normalizedIndex - 1 + pageCount) % pageCount
    }
}

internal fun verticalSwipeTarget(
    currentIndex: Int,
    pageCount: Int,
    dragDistance: Float,
    commitDistancePx: Float = DefaultVerticalSwipeCommitDistancePx
): Int {
    if (pageCount <= 0) return 0
    val normalizedIndex = currentIndex.coerceIn(0, pageCount - 1)
    if (kotlin.math.abs(dragDistance) <= commitDistancePx) return normalizedIndex
    return if (dragDistance < 0f) {
        (normalizedIndex + 1) % pageCount
    } else {
        (normalizedIndex - 1 + pageCount) % pageCount
    }
}

internal fun smartphonePageContentTransitionKey(pageIndex: Int, folderID: String?): Pair<Int, String?> {
    return pageIndex to folderID
}
