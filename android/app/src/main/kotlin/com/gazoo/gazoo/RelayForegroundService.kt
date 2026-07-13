package com.gazoo.gazoo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder

/**
 * Keeps the process alive while a relay is running, so Android doesn't kill
 * the UDP sockets when the app is backgrounded, and holds a multicast lock
 * so the Wi-Fi driver delivers the console's LAN discovery broadcasts.
 *
 * Started/stopped from Dart via the "gazoo/relay_platform" method channel.
 */
class RelayForegroundService : Service() {

    companion object {
        const val EXTRA_SERVER_NAME = "serverName"
        private const val CHANNEL_ID = "gazoo_relay"
        private const val NOTIFICATION_ID = 1
    }

    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val serverName = intent?.getStringExtra(EXTRA_SERVER_NAME) ?: "server"
        val notification = buildNotification(serverName)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        acquireMulticastLock()
        // The relay's actual state lives in the Dart layer; if the system
        // kills us there is nothing useful to restart on its own.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseMulticastLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifi.createMulticastLock("gazoo-relay").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseMulticastLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }

    private fun buildNotification(serverName: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Relay",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply { description = "Shown while a relay is running" },
            )
        }

        val tapIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Gazoo relay active")
            .setContentText("Relaying \"$serverName\" — tap to open")
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentIntent(tapIntent)
            .setOngoing(true)
            .build()
    }
}
