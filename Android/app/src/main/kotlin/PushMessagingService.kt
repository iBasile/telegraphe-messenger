package telegraphe.module

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import java.net.HttpURLConnection
import java.net.URL

class PushMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        getSharedPreferences("telegraphe", Context.MODE_PRIVATE).edit()
            .putString("fcm_token", token).apply()
        registerToken(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (message.data["type"] != "wake") return
        val unread = fetchMailbox()
        createChannel()
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_email)
            .setContentTitle("Telegraphe")
            .setContentText(if (unread > 1) "$unread nouveaux messages" else "Nouveau message")
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, notification)
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Messages", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
    }

    private fun registerToken(token: String) {
        val prefs = getSharedPreferences("telegraphe", Context.MODE_PRIVATE)
        val endpoint = prefs.getString("api_url", null) ?: return
        val accessToken = prefs.getString("access_token", null) ?: return
        Thread {
            (URL("$endpoint/devices/push-token").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                setRequestProperty("Authorization", "Bearer $accessToken")
                setRequestProperty("Content-Type", "application/json")
                doOutput = true
                outputStream.use { it.write("""{"deviceId":"${prefs.getString("device_id", "")}","platform":"android","token":"$token"}""".toByteArray()) }
                inputStream.close()
                disconnect()
            }
        }.start()
    }

    private fun fetchMailbox(): Int {
        val prefs = getSharedPreferences("telegraphe", Context.MODE_PRIVATE)
        val endpoint = prefs.getString("api_url", null) ?: return 1
        val accessToken = prefs.getString("access_token", null) ?: return 1
        return try {
            val cursor = prefs.getLong("mailbox_cursor", 0)
            val connection = URL("$endpoint/mailbox?cursor=$cursor").openConnection() as HttpURLConnection
            connection.setRequestProperty("Authorization", "Bearer $accessToken")
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            connection.disconnect()
            Regex("\"cursor\":(\\d+)").find(body)?.groupValues?.get(1)?.toLongOrNull()?.let {
                prefs.edit().putLong("mailbox_cursor", it).apply()
            }
            Regex("\"clientId\"").findAll(body).count().coerceAtLeast(1)
        } catch (_: Exception) {
            1
        }
    }

    companion object {
        private const val CHANNEL_ID = "messages"
        private const val NOTIFICATION_ID = 1001
    }
}
