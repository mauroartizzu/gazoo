package com.gazoo.gazoo

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gazoo/relay_platform",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    requestNotificationPermissionIfNeeded()
                    val intent = Intent(this, RelayForegroundService::class.java).putExtra(
                        RelayForegroundService.EXTRA_SERVER_NAME,
                        call.argument<String>("serverName") ?: "server",
                    )
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stopForegroundService" -> {
                    stopService(Intent(this, RelayForegroundService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * On Android 13+ the foreground service's persistent notification is
     * invisible unless the user grants POST_NOTIFICATIONS. The service (and
     * the relay) run fine either way — this only affects visibility.
     */
    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }
}
