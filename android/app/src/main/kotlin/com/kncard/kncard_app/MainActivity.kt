package com.kncard.kncard_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Base64
import android.database.Cursor
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "kncard/update"
    private val fileChannelName = "kncard/files"
    private val pickJsonRequestCode = 4101
    private var pendingFileResult: MethodChannel.Result? = null

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fileChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickJsonFile" -> pickJsonFile(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickJsonFile(result: MethodChannel.Result) {
        if (pendingFileResult != null) {
            result.error("file_picker_busy", "文件选择器正在使用", null)
            return
        }
        pendingFileResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "*/*"))
            }
            startActivityForResult(intent, pickJsonRequestCode)
        } catch (error: Exception) {
            pendingFileResult = null
            result.error("file_picker_failed", error.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickJsonRequestCode) return
        val result = pendingFileResult
        pendingFileResult = null
        if (result == null) return
        if (resultCode != RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }
        val uri = data.data!!
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw IllegalStateException("无法读取文件")
            val name = queryDisplayName(uri) ?: "import.json"
            result.success(
                mapOf(
                    "name" to name,
                    "contentBase64" to Base64.encodeToString(bytes, Base64.NO_WRAP),
                ),
            )
        } catch (error: Exception) {
            result.error("file_read_failed", error.message, null)
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        val projection = arrayOf(android.provider.OpenableColumns.DISPLAY_NAME)
        contentResolver.query(uri, projection, null, null, null)?.use { cursor: Cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index)
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/')
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
