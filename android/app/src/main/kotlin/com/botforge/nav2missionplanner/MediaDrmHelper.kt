package com.botforge.nav2missionplanner

import android.media.MediaDrm
import android.util.Base64
import java.security.MessageDigest
import java.util.*

class MediaDrmHelper {
    companion object {
        private const val WIDEVINE_UUID = "edef8ba979d64acea3c827dcd51d21ed"

        fun getWidevineId(): String? {
            return try {
                val widevineUuid = UUID.fromString(
                    WIDEVINE_UUID.replaceFirst(Regex("(.{8})(.{4})(.{4})(.{4})(.{12})"), "$1-$2-$3-$4-$5")
                )

                val mediaDrm = MediaDrm(widevineUuid)
                val deviceId = mediaDrm.getPropertyByteArray(MediaDrm.PROPERTY_DEVICE_UNIQUE_ID)

                // Create SHA-256 hash of the device ID
                val digest = MessageDigest.getInstance("SHA-256")
                val hash = digest.digest(deviceId)

                // Convert to base64 for easier handling
                Base64.encodeToString(hash, Base64.NO_WRAP)
            } catch (e: Exception) {
                null
            }
        }

        fun isWidevineSupported(): Boolean {
            return try {
                val widevineUuid = UUID.fromString(
                    WIDEVINE_UUID.replaceFirst(Regex("(.{8})(.{4})(.{4})(.{4})(.{12})"), "$1-$2-$3-$4-$5")
                )
                MediaDrm.isCryptoSchemeSupported(widevineUuid)
            } catch (e: Exception) {
                false
            }
        }
    }
}