package com.streak.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

object FocusBridge {

    const val CHANNEL = "streak/focus"

    private const val PREFS = "HomeWidgetPreferences"
    private const val KEY = "focus_actions"

    private var channel: MethodChannel? = null

    fun attach(context: Context, methodChannel: MethodChannel) {
        channel = methodChannel
        methodChannel.setMethodCallHandler { call, result ->
            handle(context, call, result)
        }
    }

    fun detach(methodChannel: MethodChannel?) {
        if (channel === methodChannel) channel = null
    }

    private fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "show" -> {
                val arguments = call.arguments as? Map<String, Any?>
                if (arguments == null) {
                    result.success(false)
                    return
                }
                FocusService.show(context, FocusState.from(arguments))
                result.success(true)
            }
            "hide" -> {
                FocusService.hide(context)
                result.success(true)
            }
            "drain" -> result.success(drain(context))
            "ack" -> {
                val arguments = call.arguments as? Map<String, Any?>
                val ids = arguments?.get("ids") as? List<*>
                ack(context, ids?.filterIsInstance<String>() ?: emptyList())
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    fun enqueue(context: Context, kind: String, state: JSONObject? = FocusState.read(context)) {
        synchronized(this) {
            val queue = read(context)
            val at = System.currentTimeMillis()
            val sessionId = state?.optString("sessionId") ?: ""
            val phaseId = state?.optString("phaseId") ?: ""
            queue.put(
                JSONObject()
                    .put("id", "$sessionId:$phaseId:$kind:$at")
                    .put("kind", kind)
                    .put("at", at)
                    .put("sessionId", sessionId)
                    .put("phaseId", phaseId)
            )
            write(context, queue)
        }
        notifyDart()
    }

    private fun drain(context: Context): List<Map<String, Any>> = synchronized(this) {
        val queue = read(context)
        var repaired = false
        val result = (0 until queue.length()).mapNotNull { index ->
            queue.optJSONObject(index)?.let {
                if (it.optString("id").isEmpty()) {
                    it.put("id", "legacy:${it.optString("kind")}:${it.optLong("at")}:$index")
                    repaired = true
                }
                mapOf(
                    "id" to it.optString("id"),
                    "kind" to it.optString("kind"),
                    "at" to it.optLong("at"),
                    "sessionId" to it.optString("sessionId"),
                    "phaseId" to it.optString("phaseId"),
                )
            }
        }
        if (repaired) write(context, queue)
        result
    }

    private fun ack(context: Context, ids: List<String>) = synchronized(this) {
        if (ids.isEmpty()) return@synchronized
        val done = ids.toSet()
        val queue = read(context)
        val kept = JSONArray()
        for (index in 0 until queue.length()) {
            val item = queue.optJSONObject(index) ?: continue
            if (!done.contains(item.optString("id"))) kept.put(item)
        }
        write(context, kept)
    }

    private fun notifyDart() {
        val target = channel ?: return
        Handler(Looper.getMainLooper()).post { target.invokeMethod("pending", null) }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun read(context: Context): JSONArray = try {
        val raw = prefs(context).getString(KEY, null)
        if (raw.isNullOrEmpty()) JSONArray() else JSONArray(raw)
    } catch (e: Exception) {
        JSONArray()
    }

    private fun write(context: Context, queue: JSONArray) {
        prefs(context).edit().putString(KEY, queue.toString()).commit()
    }
}
