package com.nanvon.cctrace.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.annotation.RequiresApi

/**
 * 登录期间的短时前台服务。
 *
 * 授权页在浏览器里打开时本应用退到后台，而授权码要靠本进程里的 loopback server
 * 接收。系统对缓存进程的冻结会让那个 socket 无人 accept，浏览器就停在加载中直到
 * 超时。登录开始时把进程钉在前台，进入终态立即停止。
 *
 * 用 `shortService` 类型：与 OAuth 的 3 分钟超时同量级，不需要任何运行时权限，
 * 也不需要长时运行类型的使用场景声明。
 */
class OAuthKeepAliveService : Service() {
    companion object {
        private const val channelId = "sign_in_keep_alive"
        private const val notificationId = 41999

        /** @return 前台服务是否真的拉起来了；失败不阻断登录，只是失去保活。 */
        fun start(context: Context): Boolean {
            val intent = Intent(context, OAuthKeepAliveService::class.java)
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (_: Exception) {
                // 后台启动前台服务受限等情况：登录继续，只是不再有保活。
                false
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, OAuthKeepAliveService::class.java))
            } catch (_: Exception) {
                // 尽力而为：停不掉也不能影响 OAuth 结果。
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                notificationId,
                buildNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE,
            )
        } else {
            startForeground(notificationId, buildNotification())
        }
        return START_NOT_STICKY
    }

    /** shortService 到点：必须自行结束，否则系统会强制终止进程。 */
    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    override fun onTimeout(startId: Int) {
        stopSelf()
    }

    @RequiresApi(Build.VERSION_CODES.VANILLA_ICE_CREAM)
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(channelId) != null) {
            return
        }
        val channel = NotificationChannel(
            channelId,
            "登录",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "登录期间保持本机回调可用"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("正在完成登录")
            .setContentText("请在浏览器里继续，完成后回到 CC Trace")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .build()
    }
}
