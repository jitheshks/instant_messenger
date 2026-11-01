package com.example.instant_messenger

import android.content.Context
import android.os.Looper
import android.util.Log
import androidx.annotation.Keep
import com.onesignal.notifications.INotificationReceivedEvent
import com.onesignal.notifications.INotificationServiceExtension
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.Collections
import java.util.LinkedHashSet
import java.util.concurrent.Callable
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicInteger

/**
 * Lightweight native Android OneSignal Notification Service Extension.
 *
 * Intercepts incoming push notifications in native Android code across foreground,
 * background, and terminated states.
 *
 * When an incoming chat message notification arrives, this extension:
 * 1. Extracts the short-lived [receiptToken], [messageId], and [recipientId] from additionalData.
 * 2. Validates that the device is logged in and that the current session belongs to the recipient.
 * 3. Dispatches a direct HTTP PostgREST call to the backend RPC `acknowledge_delivery_token`.
 * 4. Advances the message status to 2 (delivered), allowing the sender to see double grey ticks
 *    without waiting for the recipient to open the Flutter application.
 *
 * Threading & Lifecycle Architecture:
 * - When invoked on a background worker thread (background/terminated states):
 *   Applies a bounded wait of up to [ACK_TIMEOUT_SECONDS] (5s) to ensure the Android
 *   execution window and WakeLock held by OneSignal WorkManager remain active until
 *   the HTTP acknowledgment completes.
 * - When invoked on the main UI thread (foreground state):
 *   Never blocks the main thread; dispatches asynchronously while foreground Realtime
 *   handles immediate acknowledgment.
 * - Multi-threaded daemon pool: Dedicated worker pool prevents executor self-deadlock.
 *
 * Security & Reliability Guarantees:
 * - Best-effort acknowledgment: network errors fail open; Flutter catch-up sync guarantees consistency.
 * - Zero privileged secrets embedded: uses only the public anon key and recipient's session JWT.
 * - Single-use token validation: tokens are verified and deleted server-side.
 * - Monotonic progression: only advances messages where status < 2 (delivered); NEVER marks read.
 * - Display preservation: never suppresses or delays system tray notification rendering.
 */
@Keep
class InstantMessengerNotificationExtension : INotificationServiceExtension {

    companion object {
        private const val TAG = "OneSignalExtension"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val CONNECT_TIMEOUT_MS = 4000
        private const val READ_TIMEOUT_MS = 4000
        private const val ACK_TIMEOUT_SECONDS = 5L
        private const val MAX_RECENT_ACKS = 200

        private val threadNumber = AtomicInteger(1)
        private val ackExecutor = Executors.newCachedThreadPool { runnable ->
            Thread(runnable, "onesignal-ack-worker-${threadNumber.getAndIncrement()}").apply {
                isDaemon = true
            }
        }

        private val recentAcks: MutableSet<String> = Collections.synchronizedSet(LinkedHashSet<String>())
    }

    override fun onNotificationReceived(event: INotificationReceivedEvent) {
        val notification = event.notification
        val additionalData = notification.additionalData

        if (additionalData == null) {
            Log.d(TAG, "Notification received with null additionalData; skipping delivery ack")
            return
        }

        val messageId = additionalData.optString("messageId", "").trim()
        val receiptToken = additionalData.optString("receiptToken", "").trim()
        val recipientId = additionalData.optString("recipientId", "").trim()

        if (messageId.isEmpty() || receiptToken.isEmpty()) {
            Log.d(TAG, "Notification missing messageId or receiptToken; skipping native delivery ack")
            return
        }

        // Deduplication check
        synchronized(recentAcks) {
            if (recentAcks.contains(messageId)) {
                Log.d(TAG, "Duplicate push for messageId=$messageId already acknowledged; skipping")
                return
            }
            recentAcks.add(messageId)
            if (recentAcks.size > MAX_RECENT_ACKS) {
                val it = recentAcks.iterator()
                if (it.hasNext()) {
                    it.next()
                    it.remove()
                }
            }
        }

        val isMainThread = Looper.myLooper() == Looper.getMainLooper()
        val appContext = event.context.applicationContext

        val ackTask = Callable {
            acknowledgeDelivery(
                context = appContext,
                messageId = messageId,
                receiptToken = receiptToken,
                expectedRecipientId = recipientId
            )
        }

        if (isMainThread) {
            // Main UI thread (foreground): never block; dispatch asynchronously
            Log.d(TAG, "onNotificationReceived running on main thread; dispatching ack asynchronously")
            ackExecutor.submit(ackTask)
        } else {
            // Background worker thread: bounded wait of up to 5 seconds
            // Holds OneSignal WorkManager worker and Android execution window
            val future = ackExecutor.submit(ackTask)
            try {
                future.get(ACK_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            } catch (e: TimeoutException) {
                future.cancel(true)
                Log.w(TAG, "Delivery ack for messageId=$messageId timed out after ${ACK_TIMEOUT_SECONDS}s; deferred to catch-up sync")
            } catch (e: InterruptedException) {
                future.cancel(true)
                Thread.currentThread().interrupt()
                Log.w(TAG, "Delivery ack for messageId=$messageId interrupted; deferred to catch-up sync")
            } catch (e: ExecutionException) {
                Log.w(TAG, "Delivery ack for messageId=$messageId execution failed: ${e.cause?.message ?: e.message}")
            } catch (t: Throwable) {
                Log.w(TAG, "Unexpected error awaiting delivery ack for messageId=$messageId: ${t.message}")
            }
        }
    }

    private fun acknowledgeDelivery(
        context: Context,
        messageId: String,
        receiptToken: String,
        expectedRecipientId: String
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        // 1. Resolve Supabase public configuration
        val supabaseUrl = prefs.getString("flutter.supabase_url", null)?.trim()
        val anonKey = prefs.getString("flutter.supabase_anon_key", null)?.trim()

        if (supabaseUrl.isNullOrEmpty() || anonKey.isNullOrEmpty()) {
            Log.d(TAG, "Supabase URL or Anon Key not found in SharedPreferences; skipping native ack")
            return
        }

        // 2. Resolve authenticated user session
        val allKeys = prefs.all.keys
        val authKey = allKeys.find { it.startsWith("flutter.sb-") && it.endsWith("-auth-token") }
            ?: "flutter.supabase.auth.token"

        val rawSession = prefs.getString(authKey, null)?.trim()
        if (rawSession.isNullOrEmpty()) {
            Log.d(TAG, "Recipient is logged out (no session found); skipping delivery ack")
            return
        }

        val sessionJson = try {
            JSONObject(rawSession)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse session JSON from SharedPreferences: ${e.message}")
            return
        }

        val accessToken = sessionJson.optString("access_token", "").trim()
        val userObj = sessionJson.optJSONObject("user")
        val currentUserId = userObj?.optString("id", "")?.trim() ?: ""

        if (accessToken.isEmpty() || currentUserId.isEmpty()) {
            Log.d(TAG, "Recipient session missing accessToken or userId; skipping delivery ack")
            return
        }

        // 3. Validate recipient identity matches current logged-in user
        if (expectedRecipientId.isNotEmpty() && !expectedRecipientId.equals(currentUserId, ignoreCase = true)) {
            Log.w(TAG, "Recipient mismatch: push target=$expectedRecipientId, active user=$currentUserId; skipping")
            return
        }

        // 4. Dispatch atomic RPC to Supabase
        val endpointUrl = "${supabaseUrl.trimEnd('/')}/rest/v1/rpc/acknowledge_delivery_token"
        val url = URL(endpointUrl)
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = READ_TIMEOUT_MS
            doOutput = true
            doInput = true
            useCaches = false
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("apikey", anonKey)
            setRequestProperty("Authorization", "Bearer $accessToken")
        }

        val payload = JSONObject().apply {
            put("p_message_id", messageId)
            put("p_receipt_token", receiptToken)
        }

        try {
            OutputStreamWriter(conn.outputStream, "UTF-8").use { writer ->
                writer.write(payload.toString())
                writer.flush()
            }

            val responseCode = conn.responseCode
            if (responseCode in 200..299) {
                Log.i(TAG, "✅ Native background delivery ack confirmed for messageId=$messageId (HTTP $responseCode)")
            } else {
                val errorStream = conn.errorStream?.bufferedReader()?.readText() ?: "No error body"
                Log.w(TAG, "Delivery ack rejected (HTTP $responseCode): $errorStream")
            }
        } finally {
            conn.disconnect()
        }
    }
}
