package com.obuda.biotech.spacemedx

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Working mode: the screen stays on, a foreground service (with its
        // notification) keeps the app collecting and sending in the background.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "spacemedx/awake")
            .setMethodCallHandler { call, result ->
                if (call.method == "set") {
                    val on = call.argument<Boolean>("on") ?: (call.arguments == true)
                    val text = call.argument<String>("text") ?: "Collecting and sending data"
                    val screenOn = call.argument<Boolean>("screenOn") ?: true
                    runOnUiThread {
                        if (on) {
                            if (screenOn) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            askNotificationPermission()
                            try {
                                WorkService.start(this, text)
                            } catch (e: RuntimeException) {
                                // background start refused: the screen flag still holds the app awake
                            }
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            WorkService.stop(this)
                        }
                    }
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun askNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 9001)
        }
    }

    override fun onDestroy() {
        if (isFinishing) WorkService.stop(this)
        super.onDestroy()
    }
}
