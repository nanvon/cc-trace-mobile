package com.nanvon.cctrace.mobile

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import androidx.browser.customtabs.CustomTabsServiceConnection
import androidx.browser.customtabs.CustomTabsSession
import androidx.browser.customtabs.ExperimentalInitialNavigationCanLeaveBrowser
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val channelName = "com.nanvon.cctrace.mobile/oauth_browser"
        private val oauthReturnUri = Uri.parse("cctrace://oauth-finished")
        private val allowedAuthorizeHosts = setOf("auth.openai.com", "claude.com")
    }

    private var channel: MethodChannel? = null
    private var browserLaunchPending = false
    private var browserPauseObserved = false
    private var customTabsSession: CustomTabsSession? = null
    private var customTabsPackage: String? = null
    private var customTabsServiceBound = false
    private var pendingBrowserOpen: PendingBrowserOpen? = null

    private val customTabsServiceConnection = object : CustomTabsServiceConnection() {
        override fun onCustomTabsServiceConnected(
            componentName: ComponentName,
            client: CustomTabsClient,
        ) {
            customTabsPackage = componentName.packageName
            client.warmup(0L)

            val session = client.newSession(null)
            if (session == null) {
                launchPendingBrowserOpenWithoutSession()
                return
            }

            customTabsSession = session
            val pending = pendingBrowserOpen ?: return
            if (pending.providerPackage != componentName.packageName) {
                launchPendingBrowserOpenWithoutSession()
                return
            }

            pendingBrowserOpen = null
            launchCustomTab(
                uri = pending.uri,
                result = pending.result,
                providerPackage = pending.providerPackage,
                session = session,
            )
        }

        override fun onServiceDisconnected(componentName: ComponentName) {
            if (customTabsPackage == componentName.packageName) {
                customTabsSession = null
                customTabsPackage = null
            }
            launchPendingBrowserOpenWithoutSession()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).also {
            methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> openCustomTab(call.argument<String>("url"), result)
                    "close" -> returnToApp(result)
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

        val session = customTabsSession
        if (session != null && customTabsPackage == providerPackage) {
            launchCustomTab(uri, result, providerPackage, session)
            return
        }

        if (pendingBrowserOpen != null) {
            result.error(
                "BROWSER_BUSY",
                "A Custom Tabs session is already connecting.",
                null,
            )
            return
        }

        disconnectCustomTabsService()
        pendingBrowserOpen = PendingBrowserOpen(uri, result, providerPackage)
        val bound = try {
            CustomTabsClient.bindCustomTabsService(
                this,
                providerPackage,
                customTabsServiceConnection,
            )
        } catch (_: RuntimeException) {
            false
        }
        if (!bound) {
            launchPendingBrowserOpenWithoutSession()
            return
        }
        customTabsServiceBound = true
    }

    @OptIn(ExperimentalInitialNavigationCanLeaveBrowser::class)
    private fun launchCustomTab(
        uri: Uri,
        result: MethodChannel.Result,
        providerPackage: String,
        session: CustomTabsSession,
    ) {
        session.mayLaunchUrl(uri, null, null)
        launchCustomTab(
            uri = uri,
            result = result,
            providerPackage = providerPackage,
            builder = CustomTabsIntent.Builder(session),
        )
    }

    @OptIn(ExperimentalInitialNavigationCanLeaveBrowser::class)
    private fun launchCustomTab(
        uri: Uri,
        result: MethodChannel.Result,
        providerPackage: String,
        builder: CustomTabsIntent.Builder,
    ) {
        val customTabsIntent = builder
            .setShowTitle(true)
            .setInitialNavigationAllowedToLeaveBrowser(false)
            .setSendToExternalDefaultHandlerEnabled(false)
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

    private fun launchPendingBrowserOpenWithoutSession() {
        val pending = pendingBrowserOpen ?: return
        pendingBrowserOpen = null
        launchCustomTab(
            uri = pending.uri,
            result = pending.result,
            providerPackage = pending.providerPackage,
            builder = CustomTabsIntent.Builder(),
        )
    }

    private fun returnToApp(result: MethodChannel.Result) {
        val returnIntent = Intent(this, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(oauthReturnUri)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)

        try {
            startActivity(returnIntent)
            result.success(null)
        } catch (_: RuntimeException) {
            result.error(
                "APP_RETURN_FAILED",
                "CC Trace Mobile could not be brought to the foreground.",
                null,
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == Intent.ACTION_VIEW && intent.data == oauthReturnUri) {
            notifyBrowserReturned()
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

        notifyBrowserReturned()
    }

    private fun notifyBrowserReturned() {
        if (!browserLaunchPending) {
            return
        }
        browserLaunchPending = false
        browserPauseObserved = false
        channel?.invokeMethod("browserReturned", null)
    }

    private fun failPendingBrowserOpen(code: String, message: String) {
        val pending = pendingBrowserOpen ?: return
        pendingBrowserOpen = null
        pending.result.error(code, message, null)
    }

    private fun disconnectCustomTabsService() {
        if (customTabsServiceBound) {
            try {
                unbindService(customTabsServiceConnection)
            } catch (_: IllegalArgumentException) {
                // The browser process may already have disconnected.
            }
        }
        customTabsServiceBound = false
        customTabsSession = null
        customTabsPackage = null
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        failPendingBrowserOpen(
            "SESSION_START_FAILED",
            "CC Trace Mobile was closed while connecting to the browser.",
        )
        disconnectCustomTabsService()
        super.onDestroy()
    }

    private data class PendingBrowserOpen(
        val uri: Uri,
        val result: MethodChannel.Result,
        val providerPackage: String,
    )
}
