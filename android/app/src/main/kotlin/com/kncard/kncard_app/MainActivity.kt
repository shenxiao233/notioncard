package com.kncard.kncard_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "kncard/update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> installApk(call.argument<String>("path"), result)
                    "openInstallPermissionSettings" -> openInstallPermissionSettings(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("invalid_apk_path", "APK 路径为空", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            result.error("install_permission_required", "请允许本应用安装未知应用", null)
            return
        }
        val file = File(path)
        val cacheRoot = cacheDir.canonicalFile
        val apkFile = try {
            file.canonicalFile
        } catch (error: Exception) {
            result.error("invalid_apk_path", error.message, null)
            return
        }
        if (!apkFile.path.startsWith(cacheRoot.path + File.separator) ||
            !apkFile.exists() || !apkFile.isFile
        ) {
            result.error("apk_not_found", "更新 APK 不存在", null)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.update_file_provider",
                apkFile,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("install_failed", error.message, null)
        }
    }

    private fun openInstallPermissionSettings(result: MethodChannel.Result) {
        try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                )
            } else {
                Intent(Settings.ACTION_SECURITY_SETTINGS)
            }
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("settings_failed", error.message, null)
        }
    }
}
