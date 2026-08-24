package com.nanvon.cctrace.mobile

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import androidx.browser.customtabs.CustomTabsService
import androidx.browser.customtabs.CustomTabsServiceConnection
import androidx.browser.customtabs.CustomTabsSession
import androidx.browser.customtabs.ExperimentalInitialNavigationCanLeaveBrowser
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val channelName = "com.nanvon.cctrace.mobile/oauth_browser"
        private const val keepAliveChannelName =
            "com.nanvon.cctrace.mobile/oauth_keep_alive"
        private val oauthReturnUri = Uri.parse("cctrace://oauth-finished")
        private val allowedAuthorizeHosts = setOf("auth.openai.com", "claude.com")

        /** 只用来枚举「能打开任意 https 链接」的应用，即浏览器。 */
        private val browserProbeUri = Uri.parse("https://example.com")
    }

    private var channel: MethodChannel? = null
    private var keepAliveChannel: MethodChannel? = null
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
                    "listBrowsers" -> result.success(listBrowsers())
                    "open" -> openBrowser(
                        call.argument<String>("url"),
                        call.argument<String>("package"),
                        result,
                    )
                    "close" -> returnToApp(result)
                    "release" -> {
                        releaseBrowserResources()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        keepAliveChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            keepAliveChannelName,
        ).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> result.success(OAuthKeepAliveService.start(this))
                    "stop" -> {
                        OAuthKeepAliveService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /**
     * 设备上所有能打开 https 的应用，附带「是否提供 Custom Tabs 服务」和
     * 「是否为系统默认浏览器」。选择权交给用户：默认浏览器不一定支持 Custom Tabs，
     * 也不一定是用户登录过 Provider 的那一个。
     */
    private fun listBrowsers(): List<Map<String, Any>> {
        val defaultPackage = defaultBrowserPackage()
        return browserPackages()
            .map { (browserPackage, supportsCustomTabs) ->
                mapOf(
                    "packageName" to browserPackage,
                    "label" to applicationLabel(browserPackage),
                    "supportsCustomTabs" to supportsCustomTabs,
                    "isDefault" to (browserPackage == defaultPackage),
                )
            }
            .sortedWith(
                compareByDescending<Map<String, Any>> { it["supportsCustomTabs"] as Boolean }
                    .thenByDescending { it["isDefault"] as Boolean }
                    .thenBy { (it["label"] as String).lowercase() },
            )
    }

    private fun browserPackages(): Map<String, Boolean> {
        val customTabsPackages = packageManager
            .queryIntentServices(
                Intent(CustomTabsService.ACTION_CUSTOM_TABS_CONNECTION),
                0,
            )
            .mapNotNull { it.serviceInfo?.packageName }
            .toSet()

        val browsers = LinkedHashMap<String, Boolean>()
        for (info in packageManager.queryIntentActivities(browserProbeIntent(), 0)) {
            val browserPackage = info.activityInfo?.packageName ?: continue
            if (browserPackage == packageName) {
                continue
            }
            browsers[browserPackage] = browserPackage in customTabsPackages
        }
        return browsers
    }

    private fun browserProbeIntent(): Intent =
        Intent(Intent.ACTION_VIEW, browserProbeUri).addCategory(Intent.CATEGORY_BROWSABLE)

    private fun defaultBrowserPackage(): String? {
        val info = packageManager.resolveActivity(
            browserProbeIntent(),
            PackageManager.MATCH_DEFAULT_ONLY,
        ) ?: return null
        val activityInfo = info.activityInfo ?: return null
        // 没有设默认浏览器时系统返回的是选择器本身，不是一个可用的浏览器。
        if (activityInfo.packageName == "android" ||
            activityInfo.name.contains("ResolverActivity")
        ) {
            return null
        }
        return activityInfo.packageName
    }

    private fun applicationLabel(browserPackage: String): String {
        return try {
            packageManager
                .getApplicationLabel(packageManager.getApplicationInfo(browserPackage, 0))
                .toString()
        } catch (_: PackageManager.NameNotFoundException) {
            browserPackage
        }
    }

    private fun openBrowser(
        urlValue: String?,
        browserPackage: String?,
        result: MethodChannel.Result,
    ) {
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

        val browsers = browserPackages()
        if (browserPackage != null) {
            // 只接受枚举得到的浏览器，不把 authorize URL 交给任意包名。
            val supportsCustomTabs = browsers[browserPackage]
            if (supportsCustomTabs == null) {
                result.error(
                    "BROWSER_NOT_AVAILABLE",
                    "The selected browser is no longer available.",
                    null,
                )
                return
            }
            if (supportsCustomTabs) {
                openCustomTab(uri, browserPackage, result)
            } else {
                openExternalBrowser(uri, browserPackage, result)
            }
            return
        }

        val provider = CustomTabsClient.getPackageName(this, null)
        if (provider != null) {
            openCustomTab(uri, provider, result)
            return
        }
        val fallback = defaultBrowserPackage() ?: browsers.keys.firstOrNull()
        if (fallback == null) {
            result.error("NO_BROWSER", "No browser is available.", null)
            return
        }
        openExternalBrowser(uri, fallback, result)
    }

    private fun openCustomTab(
        uri: Uri,
        providerPackage: String,
        result: MethodChannel.Result,
    ) {
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

    /**
     * 用户选了不提供 Custom Tabs 的浏览器时的通路。锁定 package 而不是发隐式
     * Intent：既不会弹系统「打开方式」，也不会被声明了 App Links 的其他应用截走。
     */
    private fun openExternalBrowser(
        uri: Uri,
        browserPackage: String,
        result: MethodChannel.Result,
    ) {
        val intent = Intent(Intent.ACTION_VIEW, uri)
            .addCategory(Intent.CATEGORY_BROWSABLE)
            .setPackage(browserPackage)
        try {
            browserLaunchPending = true
            browserPauseObserved = false
            startActivity(intent)
            result.success(null)
        } catch (_: RuntimeException) {
            browserLaunchPending = false
            browserPauseObserved = false
            result.error("BROWSER_OPEN_FAILED", "The browser could not be opened.", null)
        }
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

    /**
     * 把应用带回前台，best-effort。
     *
     * Android 10 起后台启动 Activity 会被静默丢弃，所以**登录成功与否不依赖这一步**：
     * 授权码此时已经由 loopback 收下，用户手动切回来同样能看到结果。
     */
    private fun returnToApp(result: MethodChannel.Result) {
        val returnIntent = Intent(this, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(oauthReturnUri)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)

        try {
            startActivity(returnIntent)
            result.success(null)
            // OAuth 已进入终态（调用方只在成功 / 取消 / 超时 / 失败后 close），
            // 带回前台的职责完成后即可释放浏览器资源。
            releaseBrowserResources()
        } catch (_: RuntimeException) {
            releaseBrowserResources()
            result.success(null)
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

    /// OAuth 进入终态后幂等释放浏览器资源：清理 pending 状态、终止未完成的
    /// pending open（避免 MethodChannel result 悬挂）并解绑 Custom Tabs。
    /// 授权进行中保留绑定有助于会话稳定，因此 release 只能由终态或 dispose 触发。
    private fun releaseBrowserResources() {
        browserLaunchPending = false
        browserPauseObserved = false
        failPendingBrowserOpen(
            "BROWSER_SESSION_CLOSED",
            "CC Trace closed the browser session before it connected.",
        )
        disconnectCustomTabsService()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        keepAliveChannel?.setMethodCallHandler(null)
        keepAliveChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        failPendingBrowserOpen(
            "SESSION_START_FAILED",
            "CC Trace was closed while connecting to the browser.",
        )
        disconnectCustomTabsService()
        OAuthKeepAliveService.stop(this)
        super.onDestroy()
    }

    private data class PendingBrowserOpen(
        val uri: Uri,
        val result: MethodChannel.Result,
        val providerPackage: String,
    )
}
