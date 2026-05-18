package com.example.circadian_lingo

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * AudioDecoderHelper — AAC M4A → 16kHz Mono 16-bit PCM WAV
 *
 * Uses Android's MediaExtractor + MediaCodec to decode the compressed .m4a
 * file produced by AudioCaptureService. NO FFmpeg is bundled.
 *
 * Output: a standard 44-byte WAV file at 16kHz, mono, 16-bit PCM suitable
 * for direct consumption by SileroVadProcessor and whisper.cpp.
 *
 * The pipeline:
 *   1. MediaExtractor seeks the AAC audio track.
 *   2. MediaCodec.createDecoderByType("audio/mp4a-latm") decodes to raw PCM.
 *   3. Stereo channels are mixed to mono (average L+R).
 *   4. 44100 Hz (MediaRecorder default) is downsampled to 16000 Hz via
 *      linear interpolation — sufficient quality for VAD + speech recognition.
 *   5. PCM data is written as a standard WAV file with a complete 44-byte header.
 */
object AudioDecoderHelper {

    private const val TAG = "AudioDecoderHelper"
    private const val TARGET_SAMPLE_RATE = 16000
    private const val TIMEOUT_US = 10_000L // 10ms codec timeout

    /**
     * Decodes [m4aPath] to a 16kHz mono 16-bit PCM WAV file.
     *
     * @param context   Application context (used to determine output directory).
     * @param m4aPath   Absolute path to the source .m4a file.
     * @return          Absolute path to the decoded .wav file on success, null on failure.
     */
    suspend fun decode(context: Context, m4aPath: String): String? =
        withContext(Dispatchers.IO) {
            val outputDir  = File(context.filesDir, "recordings")
            outputDir.mkdirs()

            val timestamp  = System.currentTimeMillis()
            val outputFile = File(outputDir, "decoded_$timestamp.wav")

            Log.i(TAG, "Decoding: $m4aPath → ${outputFile.absolutePath}")

            try {
                val pcmSamples = extractPcm(m4aPath)
                if (pcmSamples == null || pcmSamples.isEmpty()) {
                    Log.e(TAG, "No PCM samples extracted from $m4aPath")
                    return@withContext null
                }

                writeWav(outputFile, pcmSamples, TARGET_SAMPLE_RATE)
                val durationSec = (pcmSamples.size * 2.0) / 32000.0
                Log.i(TAG, "WAV written: ${outputFile.absolutePath} (${pcmSamples.size} samples, duration=${"%.2f".format(durationSec)}s)")
                outputFile.absolutePath
            } catch (e: Exception) {
                Log.e(TAG, "Decode failed: ${e.message}", e)
                outputFile.delete()
                null
            }
        }

    // ─────────────────────────────────────────────────────────────────────────
    // extractPcm: MediaExtractor + MediaCodec → resampled mono int16 samples
    // ─────────────────────────────────────────────────────────────────────────
    private fun extractPcm(m4aPath: String): ShortArray? {
        val extractor = MediaExtractor()
        extractor.setDataSource(m4aPath)

        // Find the first audio track.
        var audioTrackIndex = -1
        var inputFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val fmt = extractor.getTrackFormat(i)
            val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) {
                audioTrackIndex = i
                inputFormat = fmt
                break
            }
        }

        if (audioTrackIndex < 0 || inputFormat == null) {
            Log.e(TAG, "No audio track found in $m4aPath")
            extractor.release()
            return null
        }

        extractor.selectTrack(audioTrackIndex)

        val mime          = inputFormat.getString(MediaFormat.KEY_MIME)!!
        val sourceSampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val sourceChannels   = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

        Log.i(TAG, "Audio track: mime=$mime, sampleRate=$sourceSampleRate, ch=$sourceChannels")

        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(inputFormat, null, null, 0)
        codec.start()

        val rawPcmBytes = mutableListOf<Byte>()
        val inputBuffers  = codec.inputBuffers
        @Suppress("DEPRECATION")
        val outputBuffers = codec.outputBuffers
        val bufferInfo    = MediaCodec.BufferInfo()
        var inputDone     = false
        var outputDone    = false

        while (!outputDone) {
            // Feed compressed data to the decoder.
            if (!inputDone) {
                val inputIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                if (inputIndex >= 0) {
                    val buf = inputBuffers[inputIndex]
                    buf.clear()
                    val sampleSize = extractor.readSampleData(buf, 0)
                    if (sampleSize < 0) {
                        // End of stream.
                        codec.queueInputBuffer(inputIndex, 0, 0, 0,
                                               MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(inputIndex, 0, sampleSize,
                                               extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }

            // Drain decoded PCM from the decoder.
            val outputIndex = codec.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
            if (outputIndex >= 0) {
                val outBuf = outputBuffers[outputIndex]
                val chunk  = ByteArray(bufferInfo.size)
                outBuf.get(chunk)
                outBuf.clear()
                rawPcmBytes.addAll(chunk.toList())
                codec.releaseOutputBuffer(outputIndex, false)

                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    outputDone = true
                }
            }
        }

        codec.stop()
        codec.release()
        extractor.release()

        // rawPcmBytes is now 16-bit PCM at sourceSampleRate with sourceChannels.
        val rawBytes   = rawPcmBytes.toByteArray()
        val rawBuf     = ByteBuffer.wrap(rawBytes).order(ByteOrder.LITTLE_ENDIAN)
        val numRawSamples = rawBytes.size / 2 // 16-bit = 2 bytes per sample
        val rawShorts  = ShortArray(numRawSamples)
        for (i in 0 until numRawSamples) {
            rawShorts[i] = rawBuf.short
        }

        // ── Mix to mono (if stereo) ───────────────────────────────────────
        val monoSamples: ShortArray = if (sourceChannels == 1) {
            rawShorts
        } else {
            ShortArray(numRawSamples / sourceChannels) { i ->
                var sum = 0
                for (ch in 0 until sourceChannels) {
                    sum += rawShorts[i * sourceChannels + ch]
                }
                (sum / sourceChannels).toShort()
            }
        }

        // ── Downsample to 16kHz (linear interpolation) ───────────────────
        return if (sourceSampleRate == TARGET_SAMPLE_RATE) {
            monoSamples
        } else {
            resample(monoSamples, sourceSampleRate, TARGET_SAMPLE_RATE)
        }
    }

    /**
     * Linear interpolation resampler.
     * Quality is sufficient for VAD and speech recognition (not hi-fi music).
     */
    private fun resample(input: ShortArray, inRate: Int, outRate: Int): ShortArray {
        val ratio  = inRate.toDouble() / outRate.toDouble()
        val outLen = (input.size / ratio).toInt()
        val output = ShortArray(outLen)

        for (i in 0 until outLen) {
            val srcPos = i * ratio
            val srcIdx = srcPos.toInt()
            val frac   = srcPos - srcIdx

            val s0 = input.getOrElse(srcIdx)     { 0 }.toDouble()
            val s1 = input.getOrElse(srcIdx + 1) { 0 }.toDouble()
            output[i] = (s0 + frac * (s1 - s0)).toInt().coerceIn(-32768, 32767).toShort()
        }

        Log.i(TAG, "Resampled: $inRate Hz → $outRate Hz | ${input.size} → ${output.size} samples")
        return output
    }

    // ─────────────────────────────────────────────────────────────────────────
    // writeWav: writes a standard 44-byte WAV header followed by the PCM data.
    // ─────────────────────────────────────────────────────────────────────────
    private fun writeWav(file: File, samples: ShortArray, sampleRate: Int) {
        val dataSize   = samples.size * 2 // 2 bytes per int16 sample
        val channels   = 1
        val bitsPerSample = 16
        val byteRate   = sampleRate * channels * bitsPerSample / 8
        val blockAlign = channels * bitsPerSample / 8

        RandomAccessFile(file, "rw").use { raf ->
            // RIFF header
            raf.writeBytes("RIFF")
            raf.writeIntLE(36 + dataSize)  // ChunkSize
            raf.writeBytes("WAVE")
            // fmt sub-chunk
            raf.writeBytes("fmt ")
            raf.writeIntLE(16)             // Subchunk1Size (PCM)
            raf.writeShortLE(1)            // AudioFormat (PCM = 1)
            raf.writeShortLE(channels)
            raf.writeIntLE(sampleRate)
            raf.writeIntLE(byteRate)
            raf.writeShortLE(blockAlign)
            raf.writeShortLE(bitsPerSample)
            // data sub-chunk header
            raf.writeBytes("data")
            raf.writeIntLE(dataSize)

            // PCM samples in little-endian order
            val buf = ByteBuffer.allocate(dataSize).order(ByteOrder.LITTLE_ENDIAN)
            for (s in samples) buf.putShort(s)
            raf.write(buf.array())
        }
    }

    // RandomAccessFile helpers for little-endian writes (WAV is LE).
    private fun RandomAccessFile.writeIntLE(value: Int) {
        val b = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
        b.putInt(value); write(b.array())
    }

    private fun RandomAccessFile.writeShortLE(value: Int) {
        val b = ByteBuffer.allocate(2).order(ByteOrder.LITTLE_ENDIAN)
        b.putShort(value.toShort()); write(b.array())
    }
}
