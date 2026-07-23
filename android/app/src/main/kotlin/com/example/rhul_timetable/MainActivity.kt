package com.example.rhul_timetable

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.webkit.CookieManager

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.rhul_timetable/cookies"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getCookies") {
                val url = call.argument<String>("url") ?: "https://webtimetables.royalholloway.ac.uk"
                val cookieManager = CookieManager.getInstance()
                val cookies = cookieManager.getCookie(url)
                result.success(cookies)
            } else {
                result.notImplemented()
            }
        }
    }
}
