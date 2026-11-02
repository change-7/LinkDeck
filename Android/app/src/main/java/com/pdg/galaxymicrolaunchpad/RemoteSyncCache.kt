package com.pdg.galaxymicrolaunchpad

import android.util.AtomicFile
import java.io.File
import org.json.JSONObject

internal class RemoteSyncCache(private val directory: File) {
    companion object {
        val names = setOf("buttons", "icons", "completionSound", "approvalSound")
        private const val MAX_RECORD_BYTES = 24L * 1024 * 1024
    }

    private val records = mutableMapOf<String, JSONObject>()

    init {
        directory.mkdirs()
        for (name in names) {
            val file = File(directory, "$name.json")
            if (file.length() !in 1..MAX_RECORD_BYTES) continue
            runCatching { AtomicFile(file).openRead().bufferedReader().use { JSONObject(it.readText()) } }
                .getOrNull()?.takeIf { valid(it) }?.let { records[name] = it }
        }
    }

    fun record(name: String): JSONObject? = records[name]
    fun revisions(): Map<String, String> = records.mapValues { it.value.getString("revision") }

    fun discard(name: String) {
        if (name !in names) return
        records.remove(name)
        AtomicFile(File(directory, "$name.json")).delete()
    }

    fun store(record: JSONObject): Boolean {
        if (!valid(record)) return false
        val name = record.getString("name")
        val bytes = record.toString().toByteArray(Charsets.UTF_8)
        if (bytes.size > MAX_RECORD_BYTES) return false
        val file = AtomicFile(File(directory, "$name.json"))
        runCatching {
            val output = file.startWrite()
            try {
                output.write(bytes)
                file.finishWrite(output)
            } catch (error: Exception) {
                file.failWrite(output)
                throw error
            }
        }
        records[name] = record
        return true
    }

    private fun valid(record: JSONObject): Boolean =
        record.optString("name") in names &&
            record.optString("revision").matches(Regex("[a-f0-9]{64}")) &&
            record.optJSONObject("payload") != null
}
