package com.pdg.galaxymicrolaunchpad

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.IBinder
import android.os.PowerManager
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import java.util.Calendar
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

internal fun remoteBridgeServiceStartMode(keepRunningInBackground: Boolean = true): Int =
    if (keepRunningInBackground) Service.START_STICKY else Service.START_NOT_STICKY

/** Keeps the Mac bridge alive independently of the Compose activity lifecycle. */
class RemoteBridgeService : Service() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var preferences: RemoteBridgePreferences
    private lateinit var notificationManager: NotificationManager
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var screenOffDisconnectRunnable: Runnable? = null
    private var screenReceiverRegistered = false
    private var approvalNotificationPlayer: MediaPlayer? = null

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> scheduleScreenOffDisconnect()
                Intent.ACTION_SCREEN_ON -> resumeConnection()
                ACTION_TIMEOUT_CHANGED -> applyCurrentScreenState()
                ACTION_CONNECTION_CHANGED -> {
                    RemoteBridgeRuntime.client(this@RemoteBridgeService).stop()
                    applyCurrentScreenState()
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        preferences = RemoteBridgePreferences(this)
        notificationManager = getSystemService(NotificationManager::class.java)
        createNotificationChannel()
        setMicrophoneForeground(false)
        RemoteBridgeRuntime.client(this).apply {
            onMicrophoneStopped = { setMicrophoneForeground(false) }
            onCodexApprovalChanged = ::updateApprovalNotification
        }
        registerScreenReceiver()
        applyCurrentScreenState()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Android can recreate this service after reclaiming the process while
        // the screen is off; keep the bridge loop running in that case.
        applyCurrentScreenState()
        when (intent?.action) {
            ACTION_MICROPHONE_START -> {
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                    setMicrophoneForeground(true)
                    RemoteBridgeRuntime.client(this).requestMicrophoneStart()
                }
            }
            ACTION_MICROPHONE_STOP -> {
                RemoteBridgeRuntime.client(this).stopMicrophone()
                setMicrophoneForeground(false)
            }
        }
        return remoteBridgeServiceStartMode(preferences.keepRunningInBackground)
    }

    override fun onDestroy() {
        screenOffDisconnectRunnable?.let(mainHandler::removeCallbacks)
        screenOffDisconnectRunnable = null
        if (screenReceiverRegistered) unregisterReceiver(screenReceiver)
        screenReceiverRegistered = false
        RemoteBridgeRuntime.client(this).apply {
            stop()
            onMicrophoneStopped = null
            onCodexApprovalChanged = null
        }
        notificationManager.cancel(APPROVAL_NOTIFICATION_ID)
        stopApprovalSound()
        releaseNetworkLocks()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun registerScreenReceiver() {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(ACTION_TIMEOUT_CHANGED)
            addAction(ACTION_CONNECTION_CHANGED)
        }
        ContextCompat.registerReceiver(this, screenReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        screenReceiverRegistered = true
    }

    private fun resumeConnection() {
        screenOffDisconnectRunnable?.let(mainHandler::removeCallbacks)
        screenOffDisconnectRunnable = null
        preferences.screenOffStartedAtMillis = null
        acquireNetworkLocks()
        RemoteBridgeRuntime.client(this).start()
        updateNotification("Mac bridge active")
    }

    private fun applyCurrentScreenState() {
        val bridge = RemoteBridgeRuntime.client(this)
        if (bridge.microphoneStarting || bridge.microphoneActive) {
            resumeConnection()
            return
        }
        when (screenOffConnectionAction(getSystemService(PowerManager::class.java).isInteractive)) {
            ScreenOffConnectionAction.Resume -> resumeConnection()
            ScreenOffConnectionAction.ScheduleDisconnect -> scheduleScreenOffDisconnect()
        }
    }

    private fun scheduleScreenOffDisconnect() {
        screenOffDisconnectRunnable?.let(mainHandler::removeCallbacks)
        screenOffDisconnectRunnable = null
        val now = Calendar.getInstance()
        val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val nowMillis = now.timeInMillis
        val screenOffStartedAt = preferences.screenOffStartedAtMillis ?: nowMillis.also {
            preferences.screenOffStartedAtMillis = it
        }
        if (preferences.isWithinSleepWindow(nowMinutes)) {
            pauseConnection()
            return
        }
        val timeoutMillis = preferences.screenOffTimeoutMillis
        if (timeoutMillis == Long.MAX_VALUE) return
        val remainingTimeout = timeoutMillis - (nowMillis - screenOffStartedAt)
        if (remainingTimeout <= 0L) {
            pauseConnection()
            return
        }
        val delayUntilSleepWindow = millisUntilSleepWindowStart(now, nowMinutes)
        val delay = minOf(remainingTimeout, delayUntilSleepWindow ?: remainingTimeout)
        screenOffDisconnectRunnable = Runnable { pauseConnection() }.also {
            mainHandler.postDelayed(it, delay)
        }
    }

    private fun millisUntilSleepWindowStart(now: Calendar, nowMinutes: Int): Long? {
        if (!preferences.sleepWindowEnabled) return null
        val start = preferences.sleepWindowStartMinutes
        if (preferences.isWithinSleepWindow(nowMinutes)) return 0L
        val minutesUntilStart = if (start > nowMinutes) start - nowMinutes else 24 * 60 - nowMinutes + start
        val nextStart = (now.clone() as Calendar).apply {
            add(Calendar.MINUTE, minutesUntilStart)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        return (nextStart.timeInMillis - now.timeInMillis).coerceAtLeast(1_000L)
    }

    private fun pauseConnection() {
        screenOffDisconnectRunnable = null
        RemoteBridgeRuntime.client(this).stop()
        releaseNetworkLocks()
        updateNotification("Paused until the screen turns on")
    }

    private fun acquireNetworkLocks() {
        if (wakeLock?.isHeld == true && multicastLock?.isHeld == true) return
        val powerManager = getSystemService(PowerManager::class.java)
        if (wakeLock?.isHeld != true) {
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "$packageName:remote-bridge"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        }

        val wifiManager = getSystemService(WifiManager::class.java)
        if (multicastLock?.isHeld != true) {
            multicastLock = wifiManager.createMulticastLock("$packageName:nsd").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun releaseNetworkLocks() {
        wakeLock?.let { lock -> if (lock.isHeld) lock.release() }
        wakeLock = null
        multicastLock?.let { lock -> if (lock.isHeld) lock.release() }
        multicastLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Mac bridge connection",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps the LinkDeck connection available while the screen is off."
            setShowBadge(false)
        }
        notificationManager.createNotificationChannel(channel)
        notificationManager.createNotificationChannel(
            NotificationChannel(
                APPROVAL_CHANNEL_ID,
                "Codex approval requests",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts when Codex is waiting for approval in LinkDeck."
                setShowBadge(true)
                setSound(null, null)
            }
        )
    }

    private fun updateApprovalNotification(approval: RemoteApproval?) {
        if (approval == null) {
            notificationManager.cancel(APPROVAL_NOTIFICATION_ID)
            stopApprovalSound()
            return
        }
        if (shouldPlayApprovalSoundOnPhone(RemoteBridgeRuntime.client(this).approvalSoundOutputTarget)) {
            playApprovalSound()
        } else {
            stopApprovalSound()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val openLinkDeck = PendingIntent.getActivity(
            this,
            APPROVAL_NOTIFICATION_ID,
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val publicNotification = NotificationCompat.Builder(this, APPROVAL_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_micro)
            .setContentTitle("LinkDeck")
            .setContentText("Codex 승인 요청이 있습니다.")
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .build()
        val notification = NotificationCompat.Builder(this, APPROVAL_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_micro)
            .setContentTitle(approval.title)
            .setContentText("눌러서 LinkDeck에서 요청 내용을 확인하세요.")
            .setContentIntent(openLinkDeck)
            .setPublicVersion(publicNotification)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .build()
        notificationManager.notify(APPROVAL_NOTIFICATION_ID, notification)
    }

    private fun playApprovalSound(builtInOnly: Boolean = false) {
        stopApprovalSound()
        val customFile = if (builtInOnly) null else RemoteBridgeRuntime.client(this).selectedApprovalSoundFile
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val player = if (customFile == null) {
            MediaPlayer.create(this, R.raw.codex_completion_chime, audioAttributes, 0) ?: return
        } else {
            MediaPlayer().apply { setAudioAttributes(audioAttributes) }
        }
        approvalNotificationPlayer = player
        player.setOnCompletionListener { finishedPlayer ->
            if (approvalNotificationPlayer === finishedPlayer) approvalNotificationPlayer = null
            finishedPlayer.release()
        }
        player.setOnErrorListener { failedPlayer, _, _ ->
            if (approvalNotificationPlayer === failedPlayer) approvalNotificationPlayer = null
            failedPlayer.release()
            if (customFile != null) playApprovalSound(builtInOnly = true)
            true
        }
        if (customFile == null) {
            runCatching {
                val volume = RemoteBridgeRuntime.client(this).selectedApprovalSoundVolume
                player.setVolume(volume, volume)
                player.start()
            }.onFailure {
                if (approvalNotificationPlayer === player) approvalNotificationPlayer = null
                player.release()
            }
            return
        }
        player.setOnPreparedListener { preparedPlayer ->
            if (approvalNotificationPlayer === preparedPlayer) {
                val volume = RemoteBridgeRuntime.client(this).selectedApprovalSoundVolume
                preparedPlayer.setVolume(volume, volume)
                preparedPlayer.start()
            } else preparedPlayer.release()
        }
        runCatching {
            player.setDataSource(customFile.absolutePath)
            player.prepareAsync()
        }.onFailure {
            if (approvalNotificationPlayer === player) approvalNotificationPlayer = null
            player.release()
            playApprovalSound(builtInOnly = true)
        }
    }

    private fun stopApprovalSound() {
        approvalNotificationPlayer?.let { player ->
            runCatching { player.stop() }
            player.release()
        }
        approvalNotificationPlayer = null
    }

    private fun updateNotification(message: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        notificationManager.notify(NOTIFICATION_ID, buildNotification(message))
    }

    private fun setMicrophoneForeground(enabled: Boolean) {
        val notification = buildNotification(if (enabled) "Mac 마이크로 음성 전송 중" else "Mac bridge active")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val types = ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE or
                (if (enabled) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0)
            startForeground(NOTIFICATION_ID, notification, types)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        return buildNotification("Mac bridge active")
    }

    private fun buildNotification(message: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_micro)
            .setContentTitle("LinkDeck")
            .setContentText(message)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    companion object {
        const val ACTION_START = "com.pdg.galaxymicrolaunchpad.START_REMOTE_BRIDGE"
        const val ACTION_MICROPHONE_START = "com.pdg.galaxymicrolaunchpad.MICROPHONE_START"
        const val ACTION_MICROPHONE_STOP = "com.pdg.galaxymicrolaunchpad.MICROPHONE_STOP"
        const val ACTION_TIMEOUT_CHANGED = "com.pdg.galaxymicrolaunchpad.REMOTE_BRIDGE_TIMEOUT_CHANGED"
        const val ACTION_CONNECTION_CHANGED = "com.pdg.galaxymicrolaunchpad.REMOTE_BRIDGE_CONNECTION_CHANGED"
        private const val CHANNEL_ID = "mac_bridge_connection"
        private const val APPROVAL_CHANNEL_ID = "codex_approval_v2"
        private const val NOTIFICATION_ID = 43123
        private const val APPROVAL_NOTIFICATION_ID = 43124
    }
}
