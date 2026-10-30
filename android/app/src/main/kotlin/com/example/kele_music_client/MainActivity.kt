package com.example.kele_music_client

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

// 必须继承 AudioServiceActivity，否则 audio_service 在 Android 上初始化失败。
class MainActivity : AudioServiceActivity() {

    private val downloadChannel = "kele_music/downloads"
    private val updaterChannel = "kele_music/updater"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val filename = call.argument<String>("filename")
                        val mime = call.argument<String>("mime") ?: "audio/mpeg"
                        if (bytes == null || filename.isNullOrEmpty()) {
                            result.error("args", "缺少下载参数", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveToDownloads(bytes, filename, mime))
                        } catch (e: Exception) {
                            result.error("io", e.message ?: "保存失败", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // 检查更新 → 下载完成后的安装链路（见 lib/core/updater.dart）。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Android 8+ 需用户单独授权「安装未知应用」。
                    "canRequestInstall" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                                packageManager.canRequestPackageInstalls()
                    )
                    "openInstallPermission" -> {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                )
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("settings", e.message ?: "无法打开授权页", null)
                        }
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("args", "缺少安装包路径", null)
                            return@setMethodCallHandler
                        }
                        installApk(path, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 经 FileProvider 把 APK 交给系统安装器。
     * FileProvider 的授权在 Manifest（${applicationId}.fileprovider + res/xml/file_paths.xml）。
     */
    private fun installApk(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.error("missing", "安装包不存在，请重新下载", null)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("install", e.message ?: "无法拉起安装界面", null)
        }
    }

    /** 写入系统 Download 目录；Android 10+ 走 MediaStore（无需存储权限）。 */
    private fun saveToDownloads(bytes: ByteArray, filename: String, mime: String): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
            val uri: Uri = contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
            ) ?: throw IllegalStateException("无法创建下载文件")
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("无法写入下载文件")
            "${Environment.DIRECTORY_DOWNLOADS}/$filename"
        } else {
            // Android 9 及以下：直接写公共 Download 目录。
            val dir = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS
            )
            if (!dir.exists()) dir.mkdirs()
            val base = filename.substringBeforeLast('.')
            val ext = if (filename.contains('.')) ".${filename.substringAfterLast('.')}" else ""
            var target = File(dir, filename)
            var n = 1
            while (target.exists()) {
                target = File(dir, "$base ($n)$ext")
                n++
            }
            FileOutputStream(target).use { it.write(bytes) }
            target.absolutePath
        }
    }
}
