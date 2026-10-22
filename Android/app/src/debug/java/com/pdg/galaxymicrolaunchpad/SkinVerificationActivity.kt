package com.pdg.galaxymicrolaunchpad

import android.os.Bundle
import android.content.pm.ActivityInfo
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import org.json.JSONObject
import org.json.JSONArray

class SkinVerificationActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestedOrientation = if (intent.getStringExtra("orientation") == "landscape") {
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        } else {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).hide(WindowInsetsCompat.Type.systemBars())
        val bridge = RemoteBridgeClient(this)
        val now = System.currentTimeMillis() / 1000.0
        val state = JSONObject()
            .put("type", "state")
            .put("codexConnected", true)
            .put("activity", "running")
            .put("message", "스킨 배치 검증 중")
            .put("codexPhoneTheme", intent.getStringExtra("skin") ?: "pixelSpace")
            .put("remainingPercent", 76)
            .put("fiveHourRemainingPercent", 43)
            .put("resetsAt", now + 6 * 86400 + 23 * 3600)
            .put("fiveHourResetsAt", now + 4 * 3600 + 59 * 60)
            .put("resetCredits", JSONArray()
                .put(JSONObject().put("expiresAt", now + 9 * 86400))
                .put(JSONObject().put("expiresAt", now + 17 * 86400)))
        RemoteBridgeClient::class.java.getDeclaredMethod("parseState", String::class.java).apply {
            isAccessible = true
        }.invoke(bridge, state.toString())
        setContent {
            MaterialTheme {
                Box(Modifier.fillMaxSize().background(Color.Black)) {
                    if (intent.getStringExtra("screen") == "full") {
                        GalaxyMicroLaunchpadApp(bridge, true)
                    } else {
                        CodexStatusPage(bridge)
                    }
                }
            }
        }
    }
}
