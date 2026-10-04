package com.pdg.galaxymicrolaunchpad

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Base64
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID
import java.util.concurrent.Executors

/** App-scoped owner shared by the foreground service and the visible activity. */
internal object RemoteBridgeRuntime {
    @Volatile private var sharedClient: RemoteBridgeClient? = null

    fun client(context: Context): RemoteBridgeClient {
        return sharedClient ?: synchronized(this) {
            sharedClient ?: RemoteBridgeClient(context.applicationContext).also { sharedClient = it }
        }
    }
}

enum class RemoteConnectionState {
    Disconnected,
    Searching,
    Connecting,
    Connected
}

internal fun shouldDisconnectAfterReadTimeout(consecutiveTimeouts: Int): Boolean = consecutiveTimeouts >= 2

internal data class RemoteCommandPayload(
    val command: String,
    val buttonID: String?,
    val decision: String?,
    val commandID: String,
    val approvalRequestKey: String?
)

internal fun remoteCommandPayload(
    command: String,
    buttonID: String? = null,
    decision: String? = null,
    commandID: String = UUID.randomUUID().toString(),
    approvalRequestKey: String? = null
): RemoteCommandPayload = RemoteCommandPayload(command, buttonID, decision, commandID, approvalRequestKey)

internal fun buildRemoteCommandPayload(
    command: String,
    buttonID: String? = null,
    decision: String? = null,
    commandID: String = UUID.randomUUID().toString(),
    approvalRequestKey: String? = null
): JSONObject {
    val payload = remoteCommandPayload(command, buttonID, decision, commandID, approvalRequestKey)
    return JSONObject()
        .put("type", "command")
        .put("protocolVersion", 1)
        .put("id", payload.commandID)
        .put("command", payload.command)
        .apply {
            if (payload.buttonID != null) put("buttonID", payload.buttonID)
            if (payload.decision != null) put("decision", payload.decision)
            if (payload.approvalRequestKey != null) put("approvalRequestKey", payload.approvalRequestKey)
        }
}

internal data class RemoteApproval(
    val title: String,
    val detail: String,
    val requestID: Int? = null,
    val requestKey: String? = null,
    val source: String = "appServer",
    val canRespond: Boolean = true
)


internal fun shouldPlayApprovalSoundOnPhone(outputTarget: String): Boolean =
    outputTarget != "mac"

internal fun shouldShowApprovalDialog(
    pendingApproval: RemoteApproval?,
    dismissedApproval: RemoteApproval?
): Boolean = pendingApproval != null && pendingApproval != dismissedApproval

class RemoteBridgeClient(context: Context) {
    companion object {
        private const val SERVICE_TYPE = "_micro-launchpad._tcp."
        private const val BRIDGE_PORT = 43_123
        private const val CONNECT_TIMEOUT_MS = 2_000
        private const val READ_TIMEOUT_MS = 5_000
        private const val RETRY_DELAY_MS = 3_000L
        private const val MAX_COMPLETION_SOUND_BYTES = 10 * 1024 * 1024
        private const val MAX_APPROVAL_SOUND_BYTES = 10 * 1024 * 1024
    }

    private val appContext = context.applicationContext
    private val bridgePreferences = RemoteBridgePreferences(appContext)
    private val completionSoundFile = File(appContext.filesDir, "codex_completion_sound")
    private val approvalSoundFile = File(appContext.filesDir, "codex_approval_sound")
    @Volatile private var hasCustomCompletionSound = completionSoundFile.isFile
    private val nsdManager = appContext.getSystemService(NsdManager::class.java)
    private val executor = Executors.newSingleThreadExecutor()
    private val commandExecutor = Executors.newSingleThreadExecutor()
    private val microphoneExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val resetScheduler = CodexResetScheduler(appContext)
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    @Volatile private var socket: Socket? = null
    @Volatile private var microphoneRecorder: AudioRecord? = null
    @Volatile private var microphoneCaptureRequested = false
    @Volatile private var microphoneGeneration = 0
    private var microphoneStartCommandID: String? = null
    private var writer: OutputStreamWriter? = null
    private var started = false
    @Volatile private var lastActivity: String? = null
    @Volatile private var lastCompletionEventId: Int? = null
    @Volatile private var completionSoundOutputTarget = "phone"
    @Volatile private var completionSoundVolume = 1f
    @Volatile private var approvalSoundVolume = 1f
    @Volatile private var hasReceivedRemoteState = false
    /** Set when a reconnect may replay the same active state without a transition. */
    @Volatile private var forceCodexRevealAfterReconnect = false
    @Volatile private var lastApproval: RemoteApproval? = null
    // Usage values are optional on the wire. Keep a transport-level cache so
    // an activity-only update cannot blank values that were already received.
    @Volatile private var cachedUsedPercent: Int? = null
    @Volatile private var cachedRemainingPercent: Int? = null
    @Volatile private var cachedFiveHourRemainingPercent: Int? = null
    @Volatile private var cachedResetsAt: Double? = null
    @Volatile private var cachedFiveHourResetsAt: Double? = null
    private val iconBitmapCache = mutableMapOf<String, DecodedSmartphoneIcon>()
    private var smartphoneIconAssets = JSONObject()
    private var lastStateObject: JSONObject? = null

    internal val selectedCompletionSoundFile: File?
        get() = completionSoundFile.takeIf { hasCustomCompletionSound && it.isFile }
    internal val selectedApprovalSoundFile: File?
        get() = approvalSoundFile.takeIf { it.isFile }
    internal val selectedCompletionSoundVolume: Float
        get() = completionSoundVolume
    internal val selectedApprovalSoundVolume: Float
        get() = approvalSoundVolume

    /** Called on the main thread when a Codex task completion is observed. */
    var onCodexCompletion: ((playSound: Boolean) -> Unit)? = null
    /** Called on the main thread when Codex enters running state. */
    var onCodexRunning: (() -> Unit)? = null
    /** Called on the main thread when a new approval request is received. */
    var onCodexApproval: (() -> Unit)? = null
    /** Called on the main thread whenever the pending approval changes. */
    internal var onCodexApprovalChanged: ((RemoteApproval?) -> Unit)? = null
    var onMicrophoneStopped: (() -> Unit)? = null

    var codexRevealEventId by mutableStateOf(0)
    internal var codexRevealReason by mutableStateOf(CodexRevealReason.Running)
        private set

    var connectionState by mutableStateOf(RemoteConnectionState.Disconnected)
        private set
    var microphoneActive by mutableStateOf(false)
        private set
    var microphoneStarting by mutableStateOf(false)
        private set
    var codexConnected by mutableStateOf(false)
        private set
    var macSleepMode by mutableStateOf("unknown")
        private set
    var activity by mutableStateOf("idle")
        private set
    var codexPhoneTheme by mutableStateOf(bridgePreferences.codexPhoneTheme)
        private set
    var completionSoundTarget by mutableStateOf("phone")
        private set
    var approvalSoundOutputTarget by mutableStateOf(bridgePreferences.approvalSoundOutputTarget)
        private set
    var approvalSoundName by mutableStateOf(bridgePreferences.approvalSoundName ?: "기본 승인음")
        private set
    var message by mutableStateOf("Mac을 찾는 중…")
        private set
    var commandSucceeded by mutableStateOf<Boolean?>(null)
        private set
    var usedPercent by mutableStateOf<Int?>(null)
        private set
    var remainingPercent by mutableStateOf<Int?>(null)
        private set
    var fiveHourRemainingPercent by mutableStateOf<Int?>(null)
        private set
    var resetsAt by mutableStateOf<Double?>(null)
        private set
    var fiveHourResetsAt by mutableStateOf<Double?>(null)
        private set
    internal var pendingApproval by mutableStateOf<RemoteApproval?>(null)
        private set

    internal var activeSessionCount by mutableStateOf(0)
        private set
    internal var smartphonePages by mutableStateOf(buttonPages)
        private set

    fun start() {
        if (started) return
        started = true
        discover()
    }

    fun stop() {
        stopMicrophone(sendCommand = false)
        hasReceivedRemoteState = false
        forceCodexRevealAfterReconnect = false
        started = false
        discoveryListener?.let { listener ->
            runCatching { nsdManager.stopServiceDiscovery(listener) }
        }
        discoveryListener = null
        runCatching { socket?.close() }
        socket = null
        writer = null
        clearRemoteState("Mac 연결 해제됨")
        setConnection(RemoteConnectionState.Disconnected)
    }

    private fun discover() {
        if (!started) return
        setConnection(RemoteConnectionState.Searching)
        connect("127.0.0.1", BRIDGE_PORT, fallbackToWireless = true)
    }

    private fun discoverWireless() {
        if (!started) return
        val configuredHost = bridgePreferences.macBridgeHost
        if (configuredHost.isNotEmpty()) {
            connect(configuredHost, BRIDGE_PORT)
            return
        }
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                nsdManager.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                    override fun onServiceResolved(resolved: NsdServiceInfo) {
                        if (started && bridgePreferences.macBridgeHost.isEmpty() &&
                            connectionState != RemoteConnectionState.Connected
                        ) {
                            discoveryListener?.let { listener ->
                                runCatching { nsdManager.stopServiceDiscovery(listener) }
                            }
                            val hostAddress = resolved.host.hostAddress
                            if (hostAddress == null) {
                                retryDiscovery()
                                return
                            }
                            connect(hostAddress, resolved.port)
                        }
                    }

                    override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) = Unit
                })
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) = Unit
            override fun onDiscoveryStopped(serviceType: String) = Unit
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                setConnection(RemoteConnectionState.Disconnected)
                retryDiscovery()
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
        }
        discoveryListener = listener
        runCatching {
            nsdManager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        }.onFailure {
            discoveryListener = null
            setConnection(RemoteConnectionState.Disconnected)
            retryDiscovery()
        }
    }

    private fun connect(host: String, port: Int, fallbackToWireless: Boolean = false) {
        setConnection(RemoteConnectionState.Connecting)
        executor.execute {
            try {
                val target = Socket()
                target.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
                target.soTimeout = READ_TIMEOUT_MS
                socket = target
                writer = OutputStreamWriter(target.getOutputStream(), Charsets.UTF_8)
                writer?.append("{\"type\":\"hello\",\"protocolVersion\":1}\n")
                writer?.flush()
                setConnection(RemoteConnectionState.Connected)
                readLoop(target)
            } catch (_: Exception) {
                setConnection(RemoteConnectionState.Disconnected)
            } finally {
                mainHandler.post { stopMicrophone(sendCommand = false) }
                runCatching { socket?.close() }
                socket = null
                writer = null
                iconBitmapCache.clear()
                smartphoneIconAssets = JSONObject()
                lastStateObject = null
                if (started && hasReceivedRemoteState) {
                    // Make the first replayed active state reveal Codex again.
                    forceCodexRevealAfterReconnect = true
                }
                lastApproval = null
                // Keep an active Codex state across a transient bridge
                // reconnect. Clearing it here makes the phone stop its
                // running motion during a short read timeout, even though
                // the Mac will replay the authoritative state on reconnect.
                preserveActiveStateDuringReconnect()
                if (started) {
                    setConnection(RemoteConnectionState.Disconnected)
                    if (fallbackToWireless) {
                        mainHandler.post { discoverWireless() }
                    } else {
                        retryDiscovery()
                    }
                }
            }
        }
    }

    private fun readLoop(target: Socket) {
        val reader = BufferedReader(InputStreamReader(target.getInputStream(), Charsets.UTF_8))
        var consecutiveTimeouts = 0
        while (started && !target.isClosed) {
            try {
                val line = reader.readLine() ?: break
                consecutiveTimeouts = 0
                parseState(line)
            } catch (_: SocketTimeoutException) {
                consecutiveTimeouts += 1
                if (shouldDisconnectAfterReadTimeout(consecutiveTimeouts)) break
                val currentWriter = writer ?: break
                synchronized(currentWriter) {
                    currentWriter.append("{\"type\":\"hello\",\"protocolVersion\":1}\n")
                    currentWriter.flush()
                }
            }
        }
    }

    private fun parseState(line: String) {
        runCatching {
            val state = JSONObject(line)
            if (state.optString("type") == "codexCompletionSound") {
                receiveCompletionSound(state)
                return
            }
            if (state.optString("type") == "codexApprovalSound") {
                receiveApprovalSound(state)
                return
            }
            if (state.optString("type") == "commandResult") {
                val succeeded = state.optBoolean("success", false)
                val resultMessage = state.optString("message", "Mac 명령 처리 완료")
                val commandID = state.optString("id")
                mainHandler.post {
                    if (commandID == microphoneStartCommandID) {
                        microphoneStartCommandID = null
                        microphoneStarting = false
                        if (succeeded) startMicrophoneCapture() else onMicrophoneStopped?.invoke()
                    }
                    commandSucceeded = succeeded
                    message = resultMessage
                }
                return
            }
            if (state.optString("type") == "smartphoneIconAssets") {
                smartphoneIconAssets = state.optJSONObject("assets") ?: JSONObject()
                lastStateObject?.let { currentState ->
                    parseSmartphonePages(currentState, iconBitmapCache, smartphoneIconAssets)?.let { refreshedPages ->
                        mainHandler.post { smartphonePages = refreshedPages }
                    }
                }
                return
            }
            if (state.optString("type") != "state") return
            hasReceivedRemoteState = true
            completionSoundVolume = normalizeCompletionSoundVolumePercent(
                state.optInt("completionSoundVolumePercent", 100)
            )
            approvalSoundVolume = normalizeCompletionSoundVolumePercent(
                state.optInt("approvalSoundVolumePercent", 100)
            )
            val nextUsed = mergeRemoteUsageInt(state, "usedPercent", cachedUsedPercent)
            val nextRemaining = mergeRemoteUsageInt(state, "remainingPercent", cachedRemainingPercent)
            val nextFiveHourRemaining = mergeRemoteUsageInt(state, "fiveHourRemainingPercent", cachedFiveHourRemainingPercent)
            // State refreshes may omit activity while the Mac is busy doing
            // file/tool work. Do not turn that transiently incomplete packet
            // into idle and hide the running motion.
            val nextActivity = if (state.has("activity")) {
                normalizeRemoteActivity(state.optString("activity"))
            } else {
                lastActivity ?: "idle"
            }
            if (state.has("smartphoneIconAssets")) {
                smartphoneIconAssets = state.optJSONObject("smartphoneIconAssets") ?: JSONObject()
            }
            lastStateObject = state
            val nextSmartphonePages = parseSmartphonePages(state, iconBitmapCache, smartphoneIconAssets)
            val nextApproval = parseRemoteApproval(state)
            val approvalEvent = shouldWakeForCodexApproval(lastApproval, nextApproval)
            val approvalChanged = lastApproval != nextApproval
            lastApproval = nextApproval
            val nextCompletionEventId = state.optInt("completionEventID", 0)
            val nextActiveSessionCount = state.optInt("activeSessionCount", 0).coerceAtLeast(0)
            val nextCodexPhoneTheme = normalizeCodexPhoneTheme(
                state.optString("codexPhoneTheme", codexPhoneTheme)
            )
            val reconnectReveal = shouldRevealCodexAfterReconnect(
                forceReveal = forceCodexRevealAfterReconnect,
                currentActivity = nextActivity
            )
            val revealEvent = shouldRevealCodex(
                previousActivity = lastActivity,
                currentActivity = nextActivity,
                previousCompletionEventId = lastCompletionEventId,
                currentCompletionEventId = nextCompletionEventId
            ) || reconnectReveal
            if (reconnectReveal) {
                forceCodexRevealAfterReconnect = false
            }
            val completionEvent = isCodexCompletionEvent(
                previousActivity = lastActivity,
                currentActivity = nextActivity,
                previousCompletionEventId = lastCompletionEventId,
                currentCompletionEventId = nextCompletionEventId
            )
            val playCompletionSound = shouldPlayCodexCompletionSound(
                previousActivity = lastActivity,
                currentActivity = nextActivity,
                previousCompletionEventId = lastCompletionEventId,
                currentCompletionEventId = nextCompletionEventId,
                outputTarget = completionSoundOutputTarget
            )
            val revealReason = when {
                completionEvent || nextActivity == "completed" && revealEvent -> CodexRevealReason.Completion
                nextActivity == "waitingForApproval" && revealEvent -> CodexRevealReason.Approval
                else -> CodexRevealReason.Running
            }
            val runningTransition = shouldWakeForCodexRunningTransition(
                previousActivity = lastActivity,
                currentActivity = nextActivity,
                reconnectReveal = reconnectReveal
            )
            lastActivity = nextActivity
            lastCompletionEventId = nextCompletionEventId
            val nextResetsAt = mergeRemoteUsageDouble(state, "resetsAt", cachedResetsAt)
            val nextFiveHourReset = mergeRemoteUsageDouble(state, "fiveHourResetsAt", cachedFiveHourResetsAt)
            cachedUsedPercent = nextUsed
            cachedRemainingPercent = nextRemaining
            cachedFiveHourRemainingPercent = nextFiveHourRemaining
            cachedResetsAt = nextResetsAt
            cachedFiveHourResetsAt = nextFiveHourReset
            resetScheduler.scheduleFiveHourReset(nextFiveHourReset)
            mainHandler.post {
                codexConnected = state.optBoolean("codexConnected", false)
                macSleepMode = state.optJSONObject("macSleepStatus")?.optString("mode", "unknown") ?: "unknown"
                activity = nextActivity
                message = state.optString("message", "Mac에 연결됨")
                commandSucceeded = null
                if (nextSmartphonePages != null) smartphonePages = nextSmartphonePages
                usedPercent = nextUsed
                remainingPercent = nextRemaining
                fiveHourRemainingPercent = nextFiveHourRemaining
                resetsAt = nextResetsAt
                fiveHourResetsAt = nextFiveHourReset
                UsageWidgetUpdater.onUsageChanged(appContext, nextRemaining, nextFiveHourRemaining)
                pendingApproval = nextApproval
                if (approvalChanged) {
                    onCodexApprovalChanged?.invoke(nextApproval)
                }
                activeSessionCount = nextActiveSessionCount
                if (codexPhoneTheme != nextCodexPhoneTheme) {
                    codexPhoneTheme = nextCodexPhoneTheme
                    bridgePreferences.codexPhoneTheme = nextCodexPhoneTheme
                }
                if (revealEvent) {
                    codexRevealReason = revealReason
                    codexRevealEventId += 1
                }
                if (runningTransition) {
                    onCodexRunning?.invoke()
                }
                if (approvalEvent) {
                    onCodexApproval?.invoke()
                }
                if (completionEvent) {
                    onCodexCompletion?.invoke(playCompletionSound)
                }
            }
        }
    }

    private fun receiveCompletionSound(payload: JSONObject) {
        completionSoundOutputTarget = payload.optString("outputTarget", "phone")
        mainHandler.post { completionSoundTarget = completionSoundOutputTarget }
        completionSoundVolume = normalizeCompletionSoundVolumePercent(payload.optInt("volumePercent", 100))
        if (payload.optBoolean("useBuiltIn", false)) {
            completionSoundFile.delete()
            hasCustomCompletionSound = false
            return
        }

        val encodedData = payload.optString("data")
        val maximumEncodedLength = ((MAX_COMPLETION_SOUND_BYTES + 2) / 3) * 4
        if (encodedData.isEmpty() || encodedData.length > maximumEncodedLength) return
        if (payload.optString("mimeType") !in setOf("audio/wav", "audio/mpeg", "audio/mp4", "audio/ogg")) return
        val audioData = try {
            Base64.decode(encodedData, Base64.DEFAULT)
        } catch (_: IllegalArgumentException) {
            return
        }
        if (audioData.isEmpty() || audioData.size > MAX_COMPLETION_SOUND_BYTES) return

        val temporaryFile = File(appContext.filesDir, "codex_completion_sound.tmp")
        try {
            temporaryFile.writeBytes(audioData)
            Files.move(temporaryFile.toPath(), completionSoundFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
            hasCustomCompletionSound = true
        } catch (_: Exception) {
            temporaryFile.delete()
        }
    }

    private fun receiveApprovalSound(payload: JSONObject) {
        approvalSoundVolume = normalizeCompletionSoundVolumePercent(payload.optInt("volumePercent", 100))
        val outputTarget = payload.optString("outputTarget", "phone")
            .takeIf { it in setOf("phone", "mac") } ?: "phone"
        if (outputTarget != approvalSoundOutputTarget) {
            bridgePreferences.approvalSoundOutputTarget = outputTarget
            mainHandler.post { approvalSoundOutputTarget = outputTarget }
        }
        if (!payload.optBoolean("configured", false)) return
        if (payload.optBoolean("useBuiltIn", false)) {
            approvalSoundFile.delete()
            bridgePreferences.approvalSoundName = null
            mainHandler.post { approvalSoundName = "기본 승인음" }
            return
        }

        val mimeType = payload.optString("mimeType")
        if (mimeType !in setOf("audio/wav", "audio/mpeg", "audio/mp4", "audio/ogg")) return
        val encodedData = payload.optString("data")
        val maximumEncodedLength = ((MAX_APPROVAL_SOUND_BYTES + 2) / 3) * 4
        if (encodedData.isEmpty() || encodedData.length > maximumEncodedLength) return
        val audioData = try {
            Base64.decode(encodedData, Base64.DEFAULT)
        } catch (_: IllegalArgumentException) {
            return
        }
        if (audioData.isEmpty() || audioData.size > MAX_APPROVAL_SOUND_BYTES) return

        val temporaryFile = File(appContext.filesDir, "codex_approval_sound.tmp")
        try {
            temporaryFile.writeBytes(audioData)
            Files.move(temporaryFile.toPath(), approvalSoundFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
            val displayName = payload.optString("title").takeIf { it.isNotBlank() } ?: "Mac 승인음"
            bridgePreferences.approvalSoundName = displayName
            mainHandler.post { approvalSoundName = displayName }
        } catch (_: Exception) {
            temporaryFile.delete()
        }
    }

    fun sendCommand(command: String) {
        sendCommand(command, null)
    }

    fun requestMicrophoneStart() {
        if (connectionState != RemoteConnectionState.Connected || microphoneStarting || microphoneActive) {
            onMicrophoneStopped?.invoke()
            return
        }
        microphoneStarting = true
        microphoneStartCommandID = sendCommand("microphoneStart", buttonID = null)
    }

    fun stopMicrophone(sendCommand: Boolean = true) {
        val wasStarted = microphoneStarting || microphoneActive || microphoneCaptureRequested
        microphoneGeneration += 1
        microphoneStartCommandID = null
        microphoneStarting = false
        microphoneCaptureRequested = false
        microphoneActive = false
        runCatching { microphoneRecorder?.stop() }
        if (sendCommand && wasStarted && connectionState == RemoteConnectionState.Connected) {
            sendCommand("microphoneStop")
        }
        onMicrophoneStopped?.invoke()
    }

    private fun startMicrophoneCapture() {
        microphoneGeneration += 1
        val generation = microphoneGeneration
        microphoneCaptureRequested = true
        microphoneExecutor.execute {
            val minimumSize = AudioRecord.getMinBufferSize(
                16_000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
            )
            if (minimumSize <= 0) {
                mainHandler.post { stopMicrophone() }
                return@execute
            }
            val recorder = try {
                AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    16_000,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    maxOf(minimumSize, 2_560)
                )
            } catch (_: Exception) {
                mainHandler.post { stopMicrophone() }
                return@execute
            }
            try {
                if (recorder.state != AudioRecord.STATE_INITIALIZED || generation != microphoneGeneration) return@execute
                microphoneRecorder = recorder
                recorder.startRecording()
                mainHandler.post { if (generation == microphoneGeneration) microphoneActive = true }
                val frame = ByteArray(640)
                while (generation == microphoneGeneration && microphoneCaptureRequested && socket?.isClosed == false) {
                    var offset = 0
                    while (offset < frame.size && generation == microphoneGeneration) {
                        val count = recorder.read(frame, offset, frame.size - offset, AudioRecord.READ_BLOCKING)
                        if (count <= 0) break
                        offset += count
                    }
                    if (offset != frame.size) break
                    val currentWriter = writer ?: break
                    val payload = JSONObject()
                        .put("type", "microphoneAudio")
                        .put("data", Base64.encodeToString(frame, Base64.NO_WRAP))
                    synchronized(currentWriter) {
                        currentWriter.append(payload.toString()).append('\n')
                        currentWriter.flush()
                    }
                }
            } catch (_: Exception) {
            } finally {
                if (microphoneRecorder === recorder) microphoneRecorder = null
                runCatching { recorder.stop() }
                recorder.release()
                mainHandler.post { if (generation == microphoneGeneration) stopMicrophone() }
            }
        }
    }

    fun requestSoundOutputTarget(target: String) {
        sendCommand(if (target == "mac") "notificationSoundOnMac" else "notificationSoundOnPhone")
    }

    internal fun sendSmartphoneButton(buttonID: String, longPress: Boolean = false) {
        sendCommand(if (longPress) "smartphoneButtonLongPress" else "smartphoneButton", buttonID = buttonID)
    }

    internal fun sendCodexApproval(decision: String, requestKey: String?) {
        sendCommand("codexApproval", decision = decision, approvalRequestKey = requestKey)
    }

    private fun sendCommand(
        command: String,
        buttonID: String? = null,
        decision: String? = null,
        approvalRequestKey: String? = null
    ): String? {
        if (connectionState != RemoteConnectionState.Connected) {
            mainHandler.post {
                commandSucceeded = false
                message = "Mac에 연결된 후 버튼을 눌러주세요."
            }
            return null
        }
        val commandObject = buildRemoteCommandPayload(command, buttonID, decision, approvalRequestKey = approvalRequestKey)
        commandExecutor.execute {
            val currentWriter = writer ?: run {
                mainHandler.post { if (commandObject.getString("id") == microphoneStartCommandID) stopMicrophone(sendCommand = false) }
                return@execute
            }
            runCatching {
                synchronized(currentWriter) {
                    currentWriter.append(commandObject.toString()).append('\n')
                    currentWriter.flush()
                }
            }.onFailure {
                mainHandler.post {
                    if (commandObject.getString("id") == microphoneStartCommandID) stopMicrophone(sendCommand = false)
                    commandSucceeded = false
                    message = "Mac 명령을 전달하지 못했습니다."
                }
            }
        }
        return commandObject.getString("id")
    }

    fun requestCodexReveal() {
        mainHandler.post {
            codexRevealReason = CodexRevealReason.Explicit
            codexRevealEventId += 1
        }
    }

    private fun setConnection(next: RemoteConnectionState) {
        mainHandler.post { connectionState = next }
    }

    private fun clearRemoteState(nextMessage: String = "Mac을 찾는 중…") {
        lastActivity = null
        lastCompletionEventId = null
        lastApproval = null
        cachedUsedPercent = null
        cachedRemainingPercent = null
        cachedFiveHourRemainingPercent = null
        cachedResetsAt = null
        cachedFiveHourResetsAt = null
        mainHandler.post {
            codexConnected = false
            activity = "idle"
            message = nextMessage
            commandSucceeded = null
            usedPercent = null
            remainingPercent = null
            fiveHourRemainingPercent = null
            resetsAt = null
            fiveHourResetsAt = null
            pendingApproval = null
            onCodexApprovalChanged?.invoke(null)
            activeSessionCount = 0
            smartphonePages = buttonPages
        }
    }

    private fun preserveActiveStateDuringReconnect() {
        val active = lastActivity == "running" || lastActivity == "waitingForApproval"
        if (!active) {
            clearRemoteState()
            return
        }
        mainHandler.post {
            codexConnected = false
            message = "Mac 연결을 재시도하는 중…"
            commandSucceeded = null
        }
    }

    private fun retryDiscovery() {
        mainHandler.postDelayed({ if (started && connectionState != RemoteConnectionState.Connected) discover() }, RETRY_DELAY_MS)
    }
}
