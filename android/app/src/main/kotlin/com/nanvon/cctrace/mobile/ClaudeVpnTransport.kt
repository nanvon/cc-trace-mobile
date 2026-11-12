package com.nanvon.cctrace.mobile

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.RouteInfo
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import okhttp3.Call
import okhttp3.Callback
import okhttp3.ConnectionPool
import okhttp3.Dns
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import java.net.SocketAddress
import java.net.SocketException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import javax.net.SocketFactory

internal class ClaudeVpnTransport(context: Context, messenger: BinaryMessenger) {
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val channel = MethodChannel(messenger, "com.nanvon.cctrace.mobile/claude_vpn")
    private val inFlight = ConcurrentHashMap<Long, Call>()
    private val client = OkHttpClient.Builder()
        .proxy(Proxy.NO_PROXY)
        .connectionPool(ConnectionPool(0, 1, TimeUnit.SECONDS))
        .followRedirects(false)
        .followSslRedirects(false)
        .retryOnConnectionFailure(false)
        .callTimeout(15, TimeUnit.SECONDS)
        .build()

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "send" -> send(call, result)
                "cancel" -> {
                    val id = call.arguments<Number>()?.toLong()
                    if (id != null) inFlight[id]?.cancel()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun send(message: MethodCall, result: MethodChannel.Result) {
        val id = message.argument<Number>("id")?.toLong()
        val method = message.argument<String>("method")
        val url = message.argument<String>("url")
        val headers = message.argument<Map<String, String>>("headers")
        val body = message.argument<ByteArray>("body")
        if (id == null || method == null || url == null ||
            allowedRequests[url] != method || headers == null || body == null
        ) {
            result.error("INVALID_REQUEST", null, null)
            return
        }

        val call = try {
            val manager = connectivity ?: throw VpnUnavailable()
            val network = manager.activeNetwork ?: throw VpnUnavailable()
            val vpn = VpnNetwork(manager, network)
            vpn.linkProperties()
            val request = Request.Builder()
                .url(url)
                .method(method, if (method == "POST") body.toRequestBody() else null)
                .apply { headers.forEach { (key, value) -> header(key, value) } }
                .build()
            client.newBuilder()
                .dns(vpn)
                .socketFactory(vpn.socketFactory)
                .build()
                .newCall(request)
        } catch (_: VpnUnavailable) {
            result.error("VPN_UNAVAILABLE", null, null)
            return
        } catch (_: SecurityException) {
            result.error("VPN_UNAVAILABLE", null, null)
            return
        } catch (_: IllegalArgumentException) {
            result.error("INVALID_REQUEST", null, null)
            return
        }

        if (inFlight.putIfAbsent(id, call) != null) {
            result.error("INVALID_REQUEST", null, null)
            return
        }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                inFlight.remove(id, call)
                val code = if (e is VpnUnavailable) "VPN_UNAVAILABLE" else "VPN_REQUEST_FAILED"
                result.error(code, null, null)
            }

            override fun onResponse(call: Call, response: Response) {
                val payload = try {
                    response.use {
                        mapOf(
                            "status" to it.code,
                            "headers" to it.headers.names().associate { name ->
                                name.lowercase() to it.headers.values(name).joinToString(",")
                            },
                            "body" to (it.body?.bytes() ?: byteArrayOf()),
                        )
                    }
                } catch (error: IOException) {
                    onFailure(call, error)
                    return
                }
                inFlight.remove(id, call)
                result.success(payload)
            }
        })
    }

    fun close() {
        channel.setMethodCallHandler(null)
        inFlight.values.forEach { it.cancel() }
        client.connectionPool.evictAll()
    }

    private companion object {
        val allowedRequests = mapOf(
            "https://api.anthropic.com/api/oauth/usage" to "GET",
            "https://api.anthropic.com/api/oauth/profile" to "GET",
            "https://platform.claude.com/v1/oauth/token" to "POST",
        )
    }
}

private class VpnUnavailable : SocketException("VPN unavailable or missing a route")

private class VpnNetwork(private val manager: ConnectivityManager, private val network: Network) : Dns {
    fun linkProperties(): LinkProperties {
        val capabilities = manager.getNetworkCapabilities(network)
        if (manager.activeNetwork != network ||
            capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) != true
        ) {
            throw VpnUnavailable()
        }
        return manager.getLinkProperties(network) ?: throw VpnUnavailable()
    }

    override fun lookup(hostname: String): List<InetAddress> {
        val link = linkProperties()
        if (link.dnsServers.isEmpty() || link.dnsServers.any { !link.routesThroughVpn(it) }) {
            throw VpnUnavailable()
        }
        val addresses = network.getAllByName(hostname)
        val currentLink = linkProperties()
        return addresses.filter { currentLink.sourceFor(it) != null }.ifEmpty { throw VpnUnavailable() }
    }

    val socketFactory = object : SocketFactory() {
        // OkHttp connects an unconnected socket to an address returned by its DNS resolver.
        override fun createSocket(): Socket = object : Socket(Proxy.NO_PROXY) {
            override fun connect(endpoint: SocketAddress?, timeout: Int) {
                val destination = (endpoint as? InetSocketAddress)?.address ?: throw VpnUnavailable()
                val source = linkProperties().sourceFor(destination) ?: throw VpnUnavailable()

                // Android can fall through to the physical network for split VPN routes.
                // Use the VPN's own address as well as its network handle for the socket.
                network.bindSocket(this)
                bind(InetSocketAddress(source, 0))
                super.connect(endpoint, timeout)
                if (linkProperties().sourceFor(destination) != source) throw VpnUnavailable()
            }
        }

        // No overload is allowed to perform its own unbound DNS lookup or connect.
        override fun createSocket(host: String, port: Int): Socket = throw VpnUnavailable()
        override fun createSocket(host: String, port: Int, localHost: InetAddress, localPort: Int): Socket =
            throw VpnUnavailable()
        override fun createSocket(host: InetAddress, port: Int): Socket = throw VpnUnavailable()
        override fun createSocket(host: InetAddress, port: Int, localHost: InetAddress, localPort: Int): Socket =
            throw VpnUnavailable()
    }

    private fun LinkProperties.sourceFor(destination: InetAddress): InetAddress? {
        if (!routesThroughVpn(destination)) return null
        return linkAddresses.firstOrNull {
            it.address.javaClass == destination.javaClass && !it.address.isLinkLocalAddress
        }?.address
    }

    private fun LinkProperties.routesThroughVpn(address: InetAddress): Boolean {
        if (address.isAnyLocalAddress || address.isLoopbackAddress ||
            address.isLinkLocalAddress || address.isMulticastAddress
        ) return false
        val route = routes.filter { it.matches(address) }.maxByOrNull { it.destination.prefixLength }
            ?: return false
        // excludeRoute()/RTN_THROW became public in Android 13.
        return interfaceName != null && route.`interface` == interfaceName &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || route.type == RouteInfo.RTN_UNICAST)
    }
}
