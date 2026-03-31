package com.example.parent_app

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"com.taska/qr_gallery"
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"saveImage" -> {
					val bytes = call.argument<ByteArray>("bytes")
					var name = call.argument<String>("name") ?: "pickup_qr_${System.currentTimeMillis()}.png"
					if (!name.endsWith(".png", ignoreCase = true)) {
						name += ".png"
					}

					if (bytes == null || bytes.isEmpty()) {
						result.error("INVALID_ARGS", "Missing image bytes", null)
						return@setMethodCallHandler
					}

					try {
						val uri = savePngToGallery(bytes, name)
						result.success(uri.toString())
					} catch (e: Exception) {
						result.error("SAVE_FAILED", e.message ?: "Failed to save image", null)
					}
				}

				else -> result.notImplemented()
			}
		}
	}

	private fun savePngToGallery(bytes: ByteArray, displayName: String): Uri {
		val resolver = applicationContext.contentResolver

		val values = ContentValues().apply {
			put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
			put(MediaStore.Images.Media.MIME_TYPE, "image/png")
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
				put(
					MediaStore.Images.Media.RELATIVE_PATH,
					Environment.DIRECTORY_PICTURES + "/TaskaQR"
				)
				put(MediaStore.Images.Media.IS_PENDING, 1)
			}
		}

		val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
			?: throw IllegalStateException("MediaStore insert returned null")

		resolver.openOutputStream(uri)?.use { out ->
			out.write(bytes)
			out.flush()
		} ?: throw IllegalStateException("Unable to open output stream")

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
			values.clear()
			values.put(MediaStore.Images.Media.IS_PENDING, 0)
			resolver.update(uri, values, null, null)
		}

		return uri
	}
}
