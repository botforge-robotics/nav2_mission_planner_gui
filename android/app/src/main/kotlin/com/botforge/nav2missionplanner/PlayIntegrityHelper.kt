package com.botforge.nav2missionplanner

import android.content.Context
import com.google.android.play.core.integrity.IntegrityManager
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import com.google.android.play.core.integrity.IntegrityTokenResponse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.tasks.await

class PlayIntegrityHelper(private val context: Context) {

    private val integrityManager: IntegrityManager by lazy {
        IntegrityManagerFactory.create(context)
    }

    suspend fun getIntegrityToken(): String? = withContext(Dispatchers.IO) {
        try {
            val request = IntegrityTokenRequest.builder()
                .setNonce(generateNonce())
                .build()

            val response: IntegrityTokenResponse = integrityManager
                .requestIntegrityToken(request)
                .await()

            return@withContext response.token()
        } catch (e: Exception) {
            e.printStackTrace()
            return@withContext null
        }
    }

    private fun generateNonce(): String {
        val timestamp = System.currentTimeMillis()
        val random = System.nanoTime()
        return "$timestamp-$random"
    }
}
