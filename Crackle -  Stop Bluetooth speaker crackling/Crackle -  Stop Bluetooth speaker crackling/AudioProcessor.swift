import AVFoundation
import Accelerate

class AudioProcessor: ObservableObject {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let inputNode: AVAudioInputNode

    private var recordedAudioBuffer: [Float] = []
    private var referenceAudioBuffer: [Float] = [] // Store the reference signal (A)
    private let bufferSize: AVAudioFrameCount = 4096
    private var audioProcessingQueue = DispatchQueue(label: "com.distortiondetector.audioprocessing")

    // Properties to publish results to SwiftUI
    @Published var analysisResult: String = "Analysis Results:"

    init() {
        inputNode = engine.inputNode
        setupAudioSession()
        setupEngine()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Using .playback allows sound to come from speaker, .record allows mic input.
            // .defaultToSpeaker ensures playback goes to speaker even if headphones are connected (might need user override depending on specific requirements)
            // .allowBluetooth allows using Bluetooth devices (speaker/mic)
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
    }

    private func setupEngine() {
        engine.attach(player)

        let inputFormat = inputNode.inputFormat(forBus: 0)
        // Connect the player to the main mixer node. The format should match for proper connection.
        let mainMixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)

        if let playerFormat = AVAudioFormat(standardFormatWithSampleRate: mainMixerFormat.sampleRate, channels: 1) {
             engine.connect(player, to: engine.mainMixerNode, format: playerFormat)
        } else {
             print("Could not create player format matching main mixer sample rate.")
             // Fallback or error handling
             engine.connect(player, to: engine.mainMixerNode, format: mainMixerFormat)
        }


        // Install a tap on the input node to get microphone data
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { buffer, time in
            // Process mic input here (Signal B) on a background queue
            self.audioProcessingQueue.async {
                 self.processAudioBuffer(buffer: buffer)
            }
        }

        // Optional: Connect input to main mixer for monitoring purposes. Check format compatibility.
        if mainMixerFormat.channelCount == inputFormat.channelCount && mainMixerFormat.sampleRate == inputFormat.sampleRate {
             engine.connect(inputNode, to: engine.mainMixerNode, format: mainMixerFormat)
        } else {
             // print("Warning: Input and main mixer formats do not match. Cannot connect input to main mixer for monitoring.")
             // If formats don't match, direct connection is not possible without format conversion.
        }
    }

    private func processAudioBuffer(buffer: AVAudioPCMBuffer) {
        // This buffer contains the recorded audio (Signal B)
        // Append the audio data to our storage
        if let floatChannelData = buffer.floatChannelData {
            let frameLength = Int(buffer.frameLength)
            let channelData = UnsafeBufferPointer(start: floatChannelData[0], count: frameLength)
            recordedAudioBuffer.append(contentsOf: channelData)

            // Perform analysis on accumulated buffer when enough data is available
            // The required buffer size depends on the expected delay and the length of the reference signal
            // Let's use a size sufficient to contain at least one full reference signal plus expected delay
            // Example: 5 seconds reference at 44.1kHz + some padding for delay
            let sampleRate = engine.inputNode.inputFormat(forBus: 0).sampleRate
            let requiredBufferSizeForAnalysis = Int(sampleRate * 6.0) // e.g., 6 seconds of audio

            if recordedAudioBuffer.count >= requiredBufferSizeForAnalysis && referenceAudioBuffer.count > 0 {
                 analyzeAudioData()
                 // Optionally clear the buffer after analysis if processing in chunks
                 // recordedAudioBuffer.removeAll()
            }
        }
    }

    private func analyzeAudioData() {
        print("Analyzing recorded audio data...")

        // --- Signal Alignment using Cross-correlation ---
        // We need to find the offset (lag) between the recorded signal (B) and the reference (A)

        let n = recordedAudioBuffer.count
        let m = referenceAudioBuffer.count

        if n < m { // Recorded signal must be at least as long as the reference for meaningful correlation
            print("Recorded buffer is shorter than reference, cannot perform correlation yet.")
            return
        }

        // Use vDSP for cross-correlation
        // Create output buffer for correlation result. Size is n + m - 1.
        var correlationResult = [Float](repeating: 0.0, count: n + m - 1)

        // Perform cross-correlation
        recordedAudioBuffer.withUnsafeBufferPointer { recordedPtr in
            referenceAudioBuffer.withUnsafeBufferPointer { referencePtr in
                correlationResult.withUnsafeMutableBufferPointer { resultPtr in
                    vDSP_xcorrm(recordedPtr.baseAddress!, 1, referencePtr.baseAddress!, 1, resultPtr.baseAddress!, 1, vDSP_Length(n), vDSP_Length(m))
                }
            }
        }

        // Find the index of the maximum correlation value
        var maxCorrelation: Float = 0.0
        var maxIndex: vDSP_Length = 0
        vDSP_maxv_index(correlationResult, 1, &maxCorrelation, &maxIndex, vDSP_Length(correlationResult.count))

        // The lag is calculated relative to the start of the correlation result
        // Adjust index to get the actual lag in terms of samples
        // A positive lag means recorded signal is delayed relative to reference
        let lag = Int(maxIndex) - (m - 1)

        print("Cross-correlation completed. Max correlation: \(maxCorrelation), Lag (samples): \(lag)")

        // --- Align Recorded Signal ---
        // Shift the recorded buffer by the lag to align it with the reference
        // If lag is positive, recorded is delayed, so we shift recorded forward (remove samples from start)
        // If lag is negative, recorded is ahead, so we shift recorded backward (add padding at start)

        var alignedRecordedBuffer: [Float]

        if lag > 0 {
            // Recorded is delayed, remove 'lag' samples from the start of recordedAudioBuffer
            if lag < recordedAudioBuffer.count {
                 alignedRecordedBuffer = Array(recordedAudioBuffer.dropFirst(lag))
            } else {
                 // Lag is greater than or equal to recorded buffer size, cannot align meaningfully
                 print("Lag (\(lag)) is too large to align recorded buffer of size \(recordedAudioBuffer.count).")
                 analysisResult = "Analysis Results: Could not align signals (lag too large)."
                 recordedAudioBuffer.removeAll() // Clear buffer
                 return
            }
        } else if lag < 0 {
            // Recorded is ahead, add 'abs(lag)' zeros to the start of recordedAudioBuffer
            let padding = [Float](repeating: 0.0, count: abs(lag))
            alignedRecordedBuffer = padding + recordedAudioBuffer
        } else {\n            // No lag, signals are already aligned
            alignedRecordedBuffer = recordedAudioBuffer
        }

        // Now 'alignedRecordedBuffer' is (theoretically) time-aligned with the start of 'referenceAudioBuffer'
        // We should only compare the portion of the aligned buffer that corresponds to the reference signal's length
        let comparisonLength = min(alignedRecordedBuffer.count, referenceAudioBuffer.count)
        let recordedForComparison = Array(alignedRecordedBuffer.prefix(comparisonLength))
        let referenceForComparison = Array(referenceAudioBuffer.prefix(comparisonLength))

        // --- Distortion Detection (using aligned signals) ---

        // Example: Simple Clipping Detection
        let clippingThreshold: Float = 0.95 // Threshold for detecting values close to max amplitude
        // Compare the *aligned* recorded signal with the *reference* signal to see if peaks exist in recorded but not in reference
        // This is a very basic approach; a better one would compare peak magnitudes or look for flat tops in the recorded signal where the reference was not maxed out.
        var clippedSamplesInRecorded = 0
        var potentiallyClipped = 0

        for i in 0..<comparisonLength {
            let recordedSample = recordedForComparison[i]
            let referenceSample = referenceForComparison[i]

            // Check if the recorded sample is near clipping levels
            if abs(recordedSample) >= clippingThreshold {
                 clippedSamplesInRecorded += 1

                 // Check if the reference sample at this point was NOT near clipping levels
                 if abs(referenceSample) < clippingThreshold {
                     potentiallyClipped += 1
                 }
            }
        }

        // Reporting potential clipping based on a threshold of potentially clipped samples
        let minPotentiallyClippedSamples = Int(Float(comparisonLength) * 0.005) // e.g., 0.5% of the comparison length

        if potentiallyClipped > minPotentiallyClippedSamples {
             let clippingPercentage = (Float(potentiallyClipped) / Float(comparisonLength)) * 100
             print("Potential Clipping Detected: \(potentiallyClipped) samples clipped in recorded signal where reference was not. (Approx \(String(format: "%.2f", clippingPercentage))% of comparison length)")
             analysisResult = "Analysis Results: Potential Clipping Detected."
        } else {
             print("No significant clipping detected based on this basic check.")
             analysisResult = "Analysis Results: No significant clipping detected."
        }

        // TODO: Implement Crackling Detection (Transient Analysis)
        // TODO: Implement Spectral Comparison (EQ Mismatch)
        // TODO: Implement Harmonic Distortion Analysis

        // Clear the recorded buffer after analysis
        recordedAudioBuffer.removeAll()
    }

    // Generate a simple sine wave buffer and store its float data
    private func generateSineWave(frequency: Float, sampleRate: Double, duration: TimeInterval) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format!, frameCapacity: AVAudioFrameCount(duration * sampleRate)) else {
            return nil
        }

        buffer.frameLength = buffer.frameCapacity
        let amplitude: Float = 0.5
        let samples = buffer.floatChannelData![0]

        for frame in 0..<buffer.frameLength {
            let time = Double(frame) / sampleRate
            samples[Int(frame)] = amplitude * sin(2.0 * .pi * frequency * Float(time))
        }

        // Store the generated sine wave data in referenceAudioBuffer
        referenceAudioBuffer = Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
        print("Generated reference sine wave buffer with \(referenceAudioBuffer.count) samples.")

        return buffer
    }

    // Play the generated sine wave
    func playReferenceSound() {
        // Get sample rate from the input node to ensure consistency
        let sampleRate = engine.inputNode.inputFormat(forBus: 0).sampleRate
        let frequency: Float = 440.0
        let duration: TimeInterval = 5.0 // Increased duration for better analysis and alignment

        if let sineBuffer = generateSineWave(frequency: frequency, sampleRate: sampleRate, duration: duration) {
            // Schedule the buffer for playback. .loops is good for continuous analysis.
            player.scheduleBuffer(sineBuffer, at: nil, options: .loops)
            if !player.isPlaying {
                player.play()
                print("Playing reference sine wave.")
            }
        } else {
            print("Failed to generate sine wave buffer.")
        }
    }

    func startProcessing() {
        do {
            // Clear any previous recorded data and analysis results
            recordedAudioBuffer.removeAll()
            analysisResult = "Analysis Results: Starting..."

            try engine.start()
            // Play the reference sound *after* the engine starts
            playReferenceSound()

            print("Audio engine started and reference sound playing.")
        } catch {
            print("Error starting audio engine: \(error.localizedDescription)")
            analysisResult = "Analysis Results: Error starting engine."
        }
    }

    func stopProcessing() {
        player.stop()
        engine.stop()
        recordedAudioBuffer.removeAll()
        // Keep the last analysis result or reset
        // analysisResult = "Analysis Results: Stopped."
        print("Audio engine stopped.")
    }
} 