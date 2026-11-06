package com.example.kele_music_client

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document as Doc
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

// 必须继承 AudioServiceActivity，否则 audio_service 在 Android 上初始化失败。
class MainActivity : AudioServiceActivity() {

    private val downloadChannel = "kele_music/downloads"
    private val updaterChannel = "kele_music/updater"
    private val notificationChannel = "kele_music/notifications"
    // 本地歌单「扫描文件夹导入」：SAF 目录授权 + 递归扫描 + 复制进应用内。
    private val localAudioChannel = "kele_music/local_audio"
    private val notificationRequestCode = 1002
    private val folderRequestCode = 1003
    private val mainHandler = Handler(Looper.getMainLooper())
    private var localAudioMethodChannel: MethodChannel? = null
    private var pendingFolderResult: MethodChannel.Result? = null
    private val importRunning = AtomicBoolean(false)

    @Volatile
    private var importCancelled = false

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

        // Android 13+ 通知权限（POST_NOTIFICATIONS）：
        // audio_service 的媒体通知不可见时，ColorOS 等激进后台管控会把前台
        // 服务降级冻结，长时间后台回来点播放会失联。此处只负责查询/请求，
        // 引导文案由 Dart 侧经 playErrorStream 提示（见 core/notification_permission.dart）。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(notificationsEnabled())
                    "request" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            !notificationsEnabled()
                        ) {
                            requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                notificationRequestCode
                            )
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // 本地歌单目录导入：目录选择走 SAF（ACTION_OPEN_DOCUMENT_TREE），
        // 递归扫描与复制在后台线程执行，进度经同一通道回传，可随时取消。
        val localAudio = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, localAudioChannel
        )
        localAudioMethodChannel = localAudio
        localAudio.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDirectory" -> pickDirectory(result)
                "importDirectory" -> importDirectory(call, result)
                "cancelImport" -> {
                    importCancelled = true
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == folderRequestCode) {
            val result = pendingFolderResult
            pendingFolderResult = null
            if (result == null) return
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                result.success(null) // 用户取消
                return
            }
            try {
                // 持久化读权限：下次可从同一目录增量导入（进程/重启后仍有效）。
                contentResolver.takePersistableUriPermission(
                    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: SecurityException) {
                // 少数 ROM 不支持持久授权；本次会话仍可读，下次会重新要求选择。
            }
            result.success(
                mapOf("uri" to uri.toString(), "name" to treeDisplayName(uri))
            )
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    /** 弹出系统目录选择器（SAF）。 */
    private fun pickDirectory(result: MethodChannel.Result) {
        if (pendingFolderResult != null) {
            result.error("busy", "目录选择器已打开", null)
            return
        }
        pendingFolderResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
        }
        try {
            startActivityForResult(intent, folderRequestCode)
        } catch (e: Exception) {
            pendingFolderResult = null
            result.error("picker", e.message ?: "无法打开目录选择器", null)
        }
    }

    /** 目录根节点的展示名（选择器返回的 uri 本身不带显示名）。 */
    private fun treeDisplayName(uri: Uri): String {
        return try {
            val docId = DocumentsContract.getTreeDocumentId(uri)
            val docUri = DocumentsContract.buildDocumentUriUsingTree(uri, docId)
            contentResolver.query(
                docUri, arrayOf(Doc.COLUMN_DISPLAY_NAME), null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            } ?: uri.lastPathSegment ?: "所选文件夹"
        } catch (_: Exception) {
            uri.lastPathSegment ?: "所选文件夹"
        }
    }

    /**
     * 递归扫描 SAF 目录树并把音频复制进 files/local_audio。
     * 复制而非直接引用 content:// 的原因：content uri 的读权限可能被系统
     * 回收，且播放链路（urlResolver）只认 file:// 路径。
     */
    private fun importDirectory(call: MethodCall, result: MethodChannel.Result) {
        val treeUriString = call.argument<String>("treeUri")
        val extensions = (call.argument<List<String>>("extensions") ?: emptyList())
            .map { it.lowercase() }.toSet()
        if (treeUriString.isNullOrEmpty()) {
            result.error("args", "缺少目录 uri", null)
            return
        }
        if (extensions.isEmpty()) {
            result.error("args", "缺少音频扩展名白名单", null)
            return
        }
        if (!importRunning.compareAndSet(false, true)) {
            result.error("busy", "已有导入任务进行中", null)
            return
        }
        importCancelled = false
        Thread {
            try {
                val treeUri = Uri.parse(treeUriString)
                val rootDocUri = DocumentsContract.buildDocumentUriUsingTree(
                    treeUri, DocumentsContract.getTreeDocumentId(treeUri)
                )
                val entries = mutableListOf<AudioEntry>()
                collectAudio(treeUri, rootDocUri, "", extensions, entries)
                val total = entries.size
                val destDir = File(filesDir, "local_audio").apply { mkdirs() }
                val imported = mutableListOf<Map<String, Any?>>()
                var failed = 0
                var processed = 0
                for (entry in entries) {
                    if (importCancelled) break
                    processed++
                    val ext = entry.name.substringAfterLast('.', "").lowercase()
                    val dest = File(
                        destDir, "${md5("${entry.relativePath}|${entry.size}")}.$ext"
                    )
                    // 目录里同一文件未变化时跳过复制；已存在的旧副本在本次
                    // 复制失败时保留，避免一次瞬时失败毁掉可用文件。
                    val reusable = dest.exists() && dest.length() == entry.size
                    try {
                        if (!reusable) {
                            val docUri = DocumentsContract.buildDocumentUriUsingTree(
                                treeUri, entry.docId
                            )
                            contentResolver.openInputStream(docUri)?.use { input ->
                                FileOutputStream(dest).use { output ->
                                    input.copyTo(output)
                                }
                            } ?: throw IOException("无法读取文件 ${entry.name}")
                        }
                        imported.add(
                            mapOf(
                                "path" to dest.absolutePath,
                                "name" to entry.name,
                                "relativePath" to entry.relativePath,
                            )
                        )
                    } catch (_: Exception) {
                        if (!reusable) dest.delete()
                        failed++
                    }
                    postImportProgress(processed, total, imported.size, failed)
                }
                val payload = mapOf(
                    "files" to imported,
                    "total" to total,
                    "failed" to failed,
                    "cancelled" to importCancelled,
                )
                mainHandler.post { result.success(payload) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("io", e.message ?: "目录导入失败", null)
                }
            } finally {
                importRunning.set(false)
            }
        }.start()
    }

    /** 广度不敏感的深度优先递归；只收集扩展名在白名单内的普通文件。 */
    private fun collectAudio(
        treeUri: Uri,
        parentDocUri: Uri,
        basePath: String,
        extensions: Set<String>,
        out: MutableList<AudioEntry>
    ) {
        if (importCancelled) return
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri, DocumentsContract.getDocumentId(parentDocUri)
        )
        val projection = arrayOf(
            Doc.COLUMN_DOCUMENT_ID,
            Doc.COLUMN_DISPLAY_NAME,
            Doc.COLUMN_MIME_TYPE,
            Doc.COLUMN_SIZE,
        )
        try {
            contentResolver.query(childrenUri, projection, null, null, null)
                ?.use { cursor ->
                    while (cursor.moveToNext()) {
                        if (importCancelled) return
                        val docId = cursor.getString(0) ?: continue
                        val name = cursor.getString(1) ?: continue
                        val mime = cursor.getString(2)
                        val size = if (cursor.isNull(3)) 0L else cursor.getLong(3)
                        val relative =
                            if (basePath.isEmpty()) name else "$basePath/$name"
                        if (mime == Doc.MIME_TYPE_DIR) {
                            collectAudio(
                                treeUri,
                                DocumentsContract.buildDocumentUriUsingTree(treeUri, docId),
                                relative, extensions, out
                            )
                        } else {
                            val ext = name.substringAfterLast('.', "").lowercase()
                            if (ext.isNotEmpty() && ext in extensions) {
                                out.add(AudioEntry(docId, name, relative, size))
                                if (out.size % 50 == 0) {
                                    postImportProgress(out.size, -1, 0, 0, scanning = true)
                                }
                            }
                        }
                    }
                } ?: throw IOException("无法读取目录（权限可能已失效）")
        } catch (e: SecurityException) {
            throw IOException("无法读取目录（权限可能已失效）", e)
        }
    }

    /** 进度回传：后台线程 → 主线程，避免直接跨线程调用通道。 */
    private fun postImportProgress(
        processed: Int,
        total: Int,
        success: Int,
        failed: Int,
        scanning: Boolean = false
    ) {
        mainHandler.post {
            localAudioMethodChannel?.invokeMethod(
                "progress",
                mapOf(
                    "phase" to if (scanning) "scanning" else "importing",
                    "processed" to processed,
                    "total" to total,
                    "success" to success,
                    "failed" to failed,
                )
            )
        }
    }

    private fun md5(value: String): String {
        val digest = MessageDigest.getInstance("MD5").digest(value.toByteArray())
        return digest.joinToString("") { String.format("%02x", it) }
    }

    private data class AudioEntry(
        val docId: String,
        val name: String,
        val relativePath: String,
        val size: Long,
    )

    /** Android 13+ 才有运行时通知权限；低版本恒为已授权。 */
    private fun notificationsEnabled(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            this, Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
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
