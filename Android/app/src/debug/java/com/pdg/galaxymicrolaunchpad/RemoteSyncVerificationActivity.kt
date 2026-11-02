package com.pdg.galaxymicrolaunchpad

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Base64
import android.widget.TextView
import java.io.File
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject

class RemoteSyncVerificationActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val output = TextView(this).apply { text = "Remote sync verification running" }
        setContentView(output)
        Thread {
            val result = runCatching { verify(); "PASS: cache, reconnect, ordering, completion, approval, error, icons, skin, sounds, deletion, A/B, folders, long press" }
                .getOrElse { "FAIL: ${it.stackTraceToString()}" }
            Log.i("LinkDeckSyncQA", result)
            runOnUiThread { output.text = result }
        }.start()
    }

    private fun <T> onMain(block: () -> T): T {
        val task = FutureTask<T> { block() }
        Handler(Looper.getMainLooper()).post(task)
        return task.get(10, TimeUnit.SECONDS)
    }

    private fun verify() {
        val prefix = "sync_qa_" + UUID.randomUUID()
        val isolated = object : ContextWrapper(this) {
            override fun getApplicationContext(): Context = this
            override fun getFilesDir(): File = File(baseContext.cacheDir, prefix).apply { mkdirs() }
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                baseContext.getSharedPreferences(prefix + name, mode)
        }
        PhoneAlertVibration(isolated).save(false, AlertVibrationPattern.OFF)
        PhoneAlertVibration(isolated).save(true, AlertVibrationPattern.OFF)
        val client = onMain { RemoteBridgeClient(isolated) }
        val parse = RemoteBridgeClient::class.java.getDeclaredMethod("parseState", String::class.java).apply { isAccessible = true }
        fun send(target: RemoteBridgeClient, value: JSONObject) {
            parse.invoke(target, value.toString())
            onMain { Unit }
        }
        val pages = JSONArray("""[{"id":"page","name":"QA","buttons":[{"id":"button","title":"A","secondTitle":"B","secondAction":{"kind":"url","value":"https://example.com/b"},"isSecondActionActive":true,"action":{"kind":"app","value":"qa.app"},"longPressAction":{"kind":"shortcut","value":"cmd+c"},"folderShortcuts":[{"id":"folder","title":"Folder","action":{"kind":"url","value":"https://example.com"}}]}]}]""")
        val resources = linkedMapOf(
            "buttons" to JSONObject().put("smartphonePages", pages),
            "icons" to JSONObject().put("assets", JSONObject()),
            "completionSound" to JSONObject().put("id", "built-in").put("useBuiltIn", true).put("outputTarget", "phone"),
            "approvalSound" to JSONObject().put("id", "built-in").put("useBuiltIn", true).put("configured", true)
        )
        val png = ByteArrayOutputStream().also { output ->
            Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888).apply {
                compress(Bitmap.CompressFormat.PNG, 100, output)
                recycle()
            }
        }.toByteArray()
        resources["icons"] = JSONObject().put("assets", JSONObject().put("button__B", JSONObject()
            .put("kind", "custom").put("mimeType", "image/png").put("data", Base64.encodeToString(png, Base64.NO_WRAP))))
        fun revision(payload: JSONObject): String = MessageDigest.getInstance("SHA-256").digest(payload.toString().toByteArray())
            .joinToString("") { "%02x".format(it) }
        fun sync(target: RemoteBridgeClient, sequence: Int, transfer: Boolean) {
            send(target, JSONObject().put("type", "sync").put("sessionID", "qa-session").put("sequence", sequence)
                .put("resourceRevisions", JSONObject(resources.mapValues { revision(it.value) })))
            if (transfer) resources.forEach { (name, payload) ->
                send(target, JSONObject().put("type", "resource").put("sessionID", "qa-session").put("name", name)
                    .put("revision", revision(payload)).put("payload", payload))
            }
        }
        fun state(sequence: Int, activity: String, completion: Int = 0): JSONObject = JSONObject()
            .put("type", "state").put("protocolVersion", 3).put("sessionID", "qa-session").put("sequence", sequence)
            .put("codexConnected", true).put("activity", activity).put("message", activity).put("activeSessionCount", if (activity == "running") 1 else 0)
            .put("completionEventID", completion).put("codexPhoneTheme", "pixelSpace")
        var completions = 0
        var approvals = 0
        client.onCodexCompletion = { completions++ }
        client.onCodexApproval = { approvals++ }
        sync(client, 1, true)
        send(client, state(1, "running"))
        check(client.activity == "running" && client.connectionState == RemoteConnectionState.Connected)
        val button = client.smartphonePages.single().actions.single()
        check(button.label == "B" && button.hasSecondAction && button.isSecondActionActive)
        check(button.iconBitmap != null)
        check(button.longPressAction?.command == "smartphoneButtonLongPress")
        check(button.folderActions.single().id == "folder")
        sync(client, 2, false)
        send(client, state(2, "completed", 1))
        send(client, state(2, "completed", 1))
        send(client, state(1, "running"))
        check(completions == 1 && client.activity == "completed")
        val approval = JSONObject().put("title", "QA").put("requestKey", "request-1").put("canRespond", true)
        sync(client, 3, false)
        send(client, state(3, "waitingForApproval", 1).put("approval", approval))
        send(client, state(3, "waitingForApproval", 1).put("approval", approval))
        check(approvals == 1 && client.pendingApproval?.requestKey == "request-1")
        RemoteBridgeClient::class.java.getDeclaredMethod("preserveActiveStateDuringReconnect").apply { isAccessible = true }.invoke(client)
        onMain { Unit }
        check(!client.codexConnected && client.activeSessionCount == 0 && client.pendingApproval == null)
        val recreated = onMain { RemoteBridgeClient(isolated) }
        onMain { Unit }
        check(recreated.smartphonePages.single().actions.single().label == "B")
        recreated.onCodexCompletion = { completions++ }
        recreated.onCodexApproval = { approvals++ }
        sync(recreated, 3, false)
        send(recreated, state(3, "waitingForApproval", 1).put("approval", approval))
        check(completions == 1 && approvals == 1)
        resources["buttons"] = JSONObject().put("smartphonePages", JSONArray())
        resources["icons"] = JSONObject().put("assets", JSONObject())
        sync(recreated, 4, true)
        send(recreated, state(4, "idle", 1))
        check(recreated.smartphonePages.isEmpty() && recreated.pendingApproval == null)
        val sound = Base64.encodeToString(isolated.resources.openRawResource(R.raw.codex_completion_chime).use { it.readBytes() }, Base64.NO_WRAP)
        resources["completionSound"] = JSONObject().put("id", "qa-custom").put("useBuiltIn", false)
            .put("mimeType", "audio/mpeg").put("data", sound).put("outputTarget", "phone")
        resources["approvalSound"] = JSONObject(resources.getValue("completionSound").toString()).put("configured", true)
        sync(recreated, 5, true)
        send(recreated, state(5, "failed", 1).put("codexPhoneTheme", "dotMatrix"))
        check(recreated.activity == "failed" && recreated.codexPhoneTheme == "dotMatrix")
        check(recreated.selectedCompletionSoundFile != null && recreated.selectedApprovalSoundFile != null)
        resources["completionSound"] = JSONObject().put("id", "none").put("useBuiltIn", true)
        resources["approvalSound"] = JSONObject().put("id", "built-in").put("configured", false)
        sync(recreated, 6, true)
        send(recreated, state(6, "idle", 1))
        check(recreated.selectedCompletionSoundFile == null && recreated.selectedApprovalSoundFile == null)
        check(RemoteSyncCache(File(isolated.filesDir, "remote_resources")).revisions().size == 4)
    }
}
