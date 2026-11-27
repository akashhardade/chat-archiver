package com.vervali.chatarchiver

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Dart -> Kotlin side of `chat_archiver/automation`, exactly as in doc/AUTOMATION_CHANNEL.md. */
class AutomationChannel(context: Context) : MethodChannel.MethodCallHandler {
    private val ctx = context.applicationContext
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isAccessibilityEnabled" -> result.success(ExportAccessibilityService.isEnabled(ctx))

                "openAccessibilitySettings" -> {
                    openAccessibilitySettings()
                    result.success(null)
                }

                "saveConfig" -> {
                    val m = call.arguments as? Map<*, *>
                    if (m == null) {
                        result.error("bad_args", "saveConfig expects a map", null)
                    } else {
                        Stores.config(ctx).saveConfig(AutomationConfig.fromMap(m))
                        result.success(null)
                    }
                }

                "getConfig" -> result.success(Stores.config(ctx).getConfig()?.toMap())

                "runNow" -> result.success(runNow(call))

                "cancelRun" -> {
                    ExportAccessibilityService.instance?.runner?.cancel()
                    result.success(null)
                }

                "isRunning" -> result.success(ExportAccessibilityService.instance?.runner?.isRunning ?: false)

                "listPendingExports" -> result.success(Stores.pending(ctx).list().map { it.toMap() })

                "ackExport" -> {
                    val jobId = (call.arguments as? Map<*, *>)?.get("jobId") as? String
                    if (jobId == null) result.error("bad_args", "ackExport expects {jobId}", null)
                    else {
                        Stores.pending(ctx).remove(jobId)
                        result.success(null)
                    }
                }

                "getLastRunReport" -> result.success(Stores.report(ctx).load()?.toMap())

                "dumpScreen" -> dumpScreen(call, result)

                "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())

                "requestIgnoreBatteryOptimizations" -> result.success(requestIgnoreBatteryOptimizations())

                "openAppSettings" -> {
                    openAppSettings()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "channel call ${call.method} failed", e)
            result.error("native_error", e.message, null)
        }
    }

    private fun runNow(call: MethodCall): Map<String, Any?> {
        val svc = ExportAccessibilityService.instance
        if (svc == null || !ExportAccessibilityService.isEnabled(ctx)) {
            return mapOf("started" to false, "reason" to "accessibility_disabled")
        }
        val runner = svc.runner
        if (runner.isRunning) return mapOf("started" to false, "reason" to "already_running")
        val ids = (call.arguments as? Map<*, *>)?.get("groupIds") as? List<*>
        val groups = RunPolicy.groupsForManualRun(Stores.config(ctx).getConfig(), ids?.filterIsInstance<String>())
        if (groups.isEmpty()) return mapOf("started" to false, "reason" to "no_groups")
        val res = runner.start(Trigger.MANUAL, groups)
        return mapOf("started" to res.started, "reason" to res.reason)
    }

    private fun dumpScreen(call: MethodCall, result: MethodChannel.Result) {
        val delay = ((call.arguments as? Map<*, *>)?.get("delaySeconds") as? Number)?.toLong() ?: 0L
        main.postDelayed({
            val svc = ExportAccessibilityService.instance
            if (svc == null) {
                result.error("accessibility_disabled", "Accessibility service is not connected", null)
                return@postDelayed
            }
            try {
                result.success(ScreenDump.dumpToFile(svc).absolutePath)
            } catch (e: Exception) {
                Log.e(TAG, "dumpScreen failed", e)
                result.error("dump_failed", e.message, null)
            }
        }, delay.coerceIn(0L, 120L) * 1000L)
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < 23) return true
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(ctx.packageName)
    }

    /**
     * Asks Android to exempt the app from battery optimisation (system dialog). Falls back to the
     * battery-optimisation list, then to the app's info page. Returns which screen was opened:
     * `dialog`, `list`, `app_settings` or `none`.
     */
    private fun requestIgnoreBatteryOptimizations(): String {
        if (Build.VERSION.SDK_INT < 23) return "none"
        val attempts = listOf(
            "dialog" to Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${ctx.packageName}")),
            "list" to Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            "app_settings" to appSettingsIntent(),
        )
        for ((name, intent) in attempts) {
            try {
                ctx.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return name
            } catch (e: Exception) {
                Log.d(TAG, "battery settings '$name' not available", e)
            }
        }
        return "none"
    }

    private fun appSettingsIntent() =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${ctx.packageName}"))

    /** App info page: "Allow restricted settings" (Android 13+), battery, OEM autostart entries live here. */
    private fun openAppSettings() {
        ctx.startActivity(appSettingsIntent().addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun openAccessibilitySettings() {
        val component = ComponentName(ctx, ExportAccessibilityService::class.java).flattenToString()
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            // Best-effort deep link: many Settings builds highlight the service named here.
            putExtra(":settings:fragment_args_key", component)
            putExtra(":settings:show_fragment_args", Bundle().apply { putString(":settings:fragment_args_key", component) })
        }
        if (Build.VERSION.SDK_INT >= 34) {
            try {
                ctx.startActivity(
                    Intent("android.settings.ACCESSIBILITY_DETAILS_SETTINGS").apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        putExtra(Intent.EXTRA_COMPONENT_NAME, component)
                    },
                )
                return
            } catch (e: Exception) {
                Log.d(TAG, "details settings not available, falling back", e)
            }
        }
        ctx.startActivity(intent)
    }

    companion object {
        const val CHANNEL = "chat_archiver/automation"
        private const val TAG = "ChatArchiver"
    }
}
