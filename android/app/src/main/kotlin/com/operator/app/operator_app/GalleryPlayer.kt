package com.operator.app.operator_app

import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.MediaStore

class GalleryPlayer(private val context: Context) {

    /**
     * Plays the Nth video from the gallery (1-based, most-recent-first).
     *
     * Queries MediaStore for videos sorted by DATE_ADDED DESC and launches
     * an ACTION_VIEW intent for the video at [index]. Returns a result map
     * for the MethodChannel.
     */
    fun playVideoAt(index: Int?): Map<String, Any?> {
        val safeIndex = (index ?: 1).coerceIn(1, 50)

        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            @Suppress("DEPRECATION") MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }

        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME
        )
        val sortOrder = "${MediaStore.Video.Media.DATE_ADDED} DESC"

        try {
            val cursor = context.contentResolver.query(
                collection,
                projection,
                null,
                null,
                sortOrder
            ) ?: return errorMap("ACCESS_FAILED", "Could not query gallery videos.")

            cursor.use {
                val idColumn = it.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                val nameColumn = it.getColumnIndex(MediaStore.Video.Media.DISPLAY_NAME)

                var position = 0
                var targetId: Long? = null
                var targetName: String? = null
                while (it.moveToNext()) {
                    position++
                    if (position == safeIndex) {
                        targetId = it.getLong(idColumn)
                        targetName = if (nameColumn != -1) it.getString(nameColumn) else null
                        break
                    }
                }

                if (targetId == null) {
                    return mapOf(
                        "success" to false,
                        "status" to "VIDEO_NOT_FOUND",
                        "errorMessage" to "Only found $position video(s); no video #$safeIndex."
                    )
                }

                val contentUri = ContentUris.withAppendedId(collection, targetId)
                val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(contentUri, "video/*")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }

                return try {
                    context.startActivity(viewIntent)
                    mapOf(
                        "success" to true,
                        "status" to "SUCCESS",
                        "videoName" to targetName
                    )
                } catch (e: Exception) {
                    // Fallback: open the gallery app itself so the user can tap manually.
                    try {
                        val galleryIntent =
                            context.packageManager.getLaunchIntentForPackage("com.google.android.apps.photos")
                                ?: context.packageManager.getLaunchIntentForPackage("com.sec.android.app.gallery")
                    if (galleryIntent != null) {
                            galleryIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(galleryIntent)
                        }
                    } catch (_: Exception) {}
                    errorMap("LAUNCH_FAILED", e.localizedMessage ?: "Could not play gallery video.")
                }
            }
        } catch (e: SecurityException) {
            return errorMap(
                "PERMISSION_DENIED",
                "Gallery permission is required to play videos. Please grant media access in settings."
            )
        } catch (e: Exception) {
            return errorMap("ACCESS_FAILED", e.localizedMessage ?: "Could not open gallery videos.")
        }
    }

    private fun errorMap(status: String, msg: String): Map<String, Any?> = mapOf(
        "success" to false,
        "status" to status,
        "errorMessage" to msg
    )
}
