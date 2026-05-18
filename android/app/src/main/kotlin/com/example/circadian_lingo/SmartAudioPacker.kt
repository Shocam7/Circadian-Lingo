package com.example.circadian_lingo

import android.content.Context
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream

object SmartAudioPacker {
    private const val TAG = "SmartAudioPacker"
    
    // 28 seconds of 16kHz 16-bit mono PCM = 28 * 16000 * 2 = 896,000 bytes
    private const val MAX_PACKET_BYTES = 896_000
    // 200ms of 16kHz 16-bit mono PCM = 0.2 * 16000 * 2 = 6400 bytes
    private const val SILENCE_BYTES = 6400

    data class SpeechSegment(val startMs: Long, val endMs: Long)

    fun pack(context: Context, originalWavPath: String, jsonTimestamps: String, prefix: String = ""): List<String> {
        val packetPaths = mutableListOf<String>()
        val segments = parseTimestamps(jsonTimestamps)
        if (segments.isEmpty()) {
            Log.i(TAG, "No speech segments to pack.")
            return packetPaths
        }

        val originalFile = File(originalWavPath)
        if (!originalFile.exists()) {
            Log.e(TAG, "Original WAV not found: $originalWavPath")
            return packetPaths
        }

        // Read all bytes and strip the 44-byte WAV header to get raw PCM
        val allBytes = originalFile.readBytes()
        if (allBytes.size <= 44) {
            Log.w(TAG, "Audio file too small")
            return packetPaths
        }
        val pcmData = allBytes.copyOfRange(44, allBytes.size)

        val currentPacketBuffer = ByteArrayOutputStream()
        var packetIndex = 0

        val silenceData = ByteArray(SILENCE_BYTES) { 0 }

        for (segment in segments) {
            // Convert ms to byte indices
            // 1 sec = 16000 samples * 2 bytes = 32000 bytes
            val startByte = (segment.startMs * 32000 / 1000).toInt()
            val endByte = (segment.endMs * 32000 / 1000).toInt()

            val safeStart = startByte.coerceIn(0, pcmData.size)
            // Ensure endByte is at an even boundary so we don't split a 16-bit sample
            var safeEnd = endByte.coerceIn(0, pcmData.size)
            if ((safeEnd - safeStart) % 2 != 0) safeEnd-- 
            
            if (safeStart >= safeEnd) continue

            val segmentLength = safeEnd - safeStart

            // Check if adding this segment (and silence) would overflow the packet limit
            if (currentPacketBuffer.size() > 0 && (currentPacketBuffer.size() + segmentLength + SILENCE_BYTES > MAX_PACKET_BYTES)) {
                // Flush current packet
                val packetPath = writePacketWav(context, currentPacketBuffer.toByteArray(), packetIndex++, prefix)
                packetPaths.add(packetPath)
                currentPacketBuffer.reset()
            }

            // Append silence if this is not the first segment in the packet
            if (currentPacketBuffer.size() > 0) {
                currentPacketBuffer.write(silenceData)
            }

            // Append segment PCM
            currentPacketBuffer.write(pcmData, safeStart, segmentLength)
        }

        // Flush the last packet if it has data
        if (currentPacketBuffer.size() > 0) {
            val packetPath = writePacketWav(context, currentPacketBuffer.toByteArray(), packetIndex, prefix)
            packetPaths.add(packetPath)
        }

        Log.i(TAG, "Packed into ${packetPaths.size} packets.")
        return packetPaths
    }

    private fun writePacketWav(context: Context, pcmData: ByteArray, index: Int, prefix: String): String {
        val fileName = if (prefix.isEmpty()) "packet_$index.wav" else "${prefix}_packet_$index.wav"
        val file = File(context.filesDir, fileName)
        
        val totalDataLen = pcmData.size
        val totalAudioLen = totalDataLen + 36
        val longSampleRate = 16000L
        val channels = 1
        val byteRate = 16000 * 2 * 1

        val header = ByteArray(44)
        header[0] = 'R'.code.toByte()
        header[1] = 'I'.code.toByte()
        header[2] = 'F'.code.toByte()
        header[3] = 'F'.code.toByte()

        // Little Endian
        header[4] = (totalAudioLen and 0xff).toByte()
        header[5] = ((totalAudioLen shr 8) and 0xff).toByte()
        header[6] = ((totalAudioLen shr 16) and 0xff).toByte()
        header[7] = ((totalAudioLen shr 24) and 0xff).toByte()

        header[8] = 'W'.code.toByte()
        header[9] = 'A'.code.toByte()
        header[10] = 'V'.code.toByte()
        header[11] = 'E'.code.toByte()
        header[12] = 'f'.code.toByte()
        header[13] = 'm'.code.toByte()
        header[14] = 't'.code.toByte()
        header[15] = ' '.code.toByte()

        header[16] = 16 // 4 bytes: size of 'fmt ' chunk
        header[17] = 0
        header[18] = 0
        header[19] = 0
        header[20] = 1 // format = 1 (PCM)
        header[21] = 0
        header[22] = channels.toByte()
        header[23] = 0

        header[24] = (longSampleRate and 0xff).toByte()
        header[25] = ((longSampleRate shr 8) and 0xff).toByte()
        header[26] = ((longSampleRate shr 16) and 0xff).toByte()
        header[27] = ((longSampleRate shr 24) and 0xff).toByte()

        header[28] = (byteRate and 0xff).toByte()
        header[29] = ((byteRate shr 8) and 0xff).toByte()
        header[30] = ((byteRate shr 16) and 0xff).toByte()
        header[31] = ((byteRate shr 24) and 0xff).toByte()

        header[32] = (2 * 16 / 8).toByte() // block align
        header[33] = 0
        header[34] = 16 // bits per sample
        header[35] = 0

        header[36] = 'd'.code.toByte()
        header[37] = 'a'.code.toByte()
        header[38] = 't'.code.toByte()
        header[39] = 'a'.code.toByte()

        header[40] = (totalDataLen and 0xff).toByte()
        header[41] = ((totalDataLen shr 8) and 0xff).toByte()
        header[42] = ((totalDataLen shr 16) and 0xff).toByte()
        header[43] = ((totalDataLen shr 24) and 0xff).toByte()

        FileOutputStream(file).use { out ->
            out.write(header, 0, 44)
            out.write(pcmData)
        }

        return file.absolutePath
    }

    private fun parseTimestamps(jsonString: String): List<SpeechSegment> {
        val segments = mutableListOf<SpeechSegment>()
        try {
            // Regex to parse [{"start_ms": 100, "end_ms": 2500}]
            val regex = """"start_ms"\s*:\s*(\d+)\s*,\s*"end_ms"\s*:\s*(\d+)""".toRegex()
            val matches = regex.findAll(jsonString)
            for (match in matches) {
                val start = match.groupValues[1].toLong()
                val end = match.groupValues[2].toLong()
                segments.add(SpeechSegment(start, end))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse JSON timestamps: $jsonString", e)
        }
        return segments
    }
}
