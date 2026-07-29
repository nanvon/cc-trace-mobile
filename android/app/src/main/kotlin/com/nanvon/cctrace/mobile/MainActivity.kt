package com.nanvon.cctrace.mobile

import android.net.Uri
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val channelName = "com.nanvon.cctrace.mobile/oauth_browser"
        private val allowedAuthorizeHosts = setOf("auth.openai.com", "claude.com")
    }

    private var channel: MethodChannel? = null
    private var browserLaunchPending = false
    private var browserPauseObserved = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).also {
            methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> openCustomTab(call.argument<String>("url"), result)
                    "close" -> {
                        // Standard Custom Tabs have no supported programmatic close API.
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun openCustomTab(urlValue: String?, result: MethodChannel.Result) {
        val uri = urlValue?.let(Uri::parse)
        val host = uri?.host
        if (
            uri == null ||
            uri.scheme != "https" ||
            host == null ||
            host !in allowedAuthorizeHosts
        ) {
            result.error("INVALID_ARGUMENT", "Authorize URL is not allowed.", null)
            return
        }

        val providerPackage = CustomTabsClient.getPackageName(this, null)
        if (providerPackage == null) {
            result.error("NO_CUSTOM_TAB", "No Custom Tabs provider is available.", null)
            return
        }

        val customTabsIntent = CustomTabsIntent.Builder()
            .setShowTitle(true)
            .build()
        customTabsIntent.intent.setPackage(providerPackage)

        try {
            browserLaunchPending = true
            browserPauseObserved = false
            customTabsIntent.launchUrl(this, uri)
            result.success(null)
        } catch (_: RuntimeException) {
            browserLaunchPending = false
            browserPauseObserved = false
            result.error("BROWSER_OPEN_FAILED", "Custom Tab could not be opened.", null)
        }
    }

    override fun onPause() {
        if (browserLaunchPending) {
            browserPauseObserved = true
        }
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        if (!browserLaunchPending || !browserPauseObserved) {
            return
        }

        browserLaunchPending = false
        browserPauseObserved = false
        channel?.invokeMethod("browserReturned", null)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
