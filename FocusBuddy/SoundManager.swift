import AVFoundation
import AppKit

class SoundManager {
    static let shared = SoundManager()

    private var audioEngine: AVAudioEngine?
    private var tonePlayer: AVAudioPlayerNode?

    private init() {
        setupAudioEngine()
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        tonePlayer = AVAudioPlayerNode()

        guard let engine = audioEngine, let player = tonePlayer else { return }

        engine.attach(player)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }

    // MARK: - Clean Sine Tone Generator

    /// Generates a clean, pleasant sine wave tone
    private func generateCleanTone(frequency: Double, duration: Double, volume: Float = 0.2) -> AVAudioPCMBuffer? {
        let sampleRate: Double = 44100
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else { return nil }

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate

            // Clean sine wave
            var sample = Float(sin(2.0 * .pi * frequency * time)) * volume

            // Smooth envelope (attack and release)
            let attackTime = 0.01
            let releaseTime = duration * 0.3

            if time < attackTime {
                sample *= Float(time / attackTime)
            } else if time > duration - releaseTime {
                sample *= Float((duration - time) / releaseTime)
            }

            channelData[frame] = sample
        }

        return buffer
    }

    /// Plays a sequence of tones with timing
    private func playMelody(_ notes: [(frequency: Double, duration: Double, delay: Double)], volume: Float = 0.15) {
        guard let engine = audioEngine, engine.isRunning else {
            setupAudioEngine()
            return
        }

        for note in notes {
            DispatchQueue.main.asyncAfter(deadline: .now() + note.delay) { [weak self] in
                if let buffer = self?.generateCleanTone(frequency: note.frequency, duration: note.duration, volume: volume) {
                    self?.tonePlayer?.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
                    self?.tonePlayer?.play()
                }
            }
        }
    }

    // MARK: - Sound Effects

    /// Warning — gentle two-note alert (like a soft notification)
    func playWarningSound() {
        // G5 -> G5 (gentle double tap)
        playMelody([
            (frequency: 784, duration: 0.08, delay: 0),
            (frequency: 784, duration: 0.08, delay: 0.12)
        ], volume: 0.12)
    }

    /// Distracted — descending minor third (gentle disappointment)
    func playDistractedSound() {
        // E5 -> C5 (minor third down, sounds thoughtful not harsh)
        playMelody([
            (frequency: 659, duration: 0.15, delay: 0),
            (frequency: 523, duration: 0.2, delay: 0.15)
        ], volume: 0.15)
    }

    /// Welcome Back — ascending major chord (cheerful return)
    func playWelcomeBackSound() {
        // C5 -> E5 -> G5 (major triad, happy sound)
        playMelody([
            (frequency: 523, duration: 0.1, delay: 0),
            (frequency: 659, duration: 0.1, delay: 0.08),
            (frequency: 784, duration: 0.15, delay: 0.16)
        ], volume: 0.12)
    }

    /// Happy chirp — quick ascending interval
    func playHappyChirp() {
        // Quick C6 -> E6
        playMelody([
            (frequency: 1047, duration: 0.06, delay: 0),
            (frequency: 1319, duration: 0.08, delay: 0.05)
        ], volume: 0.1)
    }

    /// Click — soft tap
    func playClick() {
        playMelody([
            (frequency: 1000, duration: 0.02, delay: 0)
        ], volume: 0.08)
    }

    /// Love — sweet ascending arpeggio
    func playLoveSound() {
        // C5 -> E5 -> G5 -> C6 (octave arpeggio)
        playMelody([
            (frequency: 523, duration: 0.12, delay: 0),
            (frequency: 659, duration: 0.12, delay: 0.1),
            (frequency: 784, duration: 0.12, delay: 0.2),
            (frequency: 1047, duration: 0.18, delay: 0.3)
        ], volume: 0.12)
    }

    /// Pomodoro Start — energetic ascending fifth
    func playPomodoroStart() {
        // C5 -> G5 (perfect fifth, strong and positive)
        playMelody([
            (frequency: 523, duration: 0.12, delay: 0),
            (frequency: 784, duration: 0.15, delay: 0.1)
        ], volume: 0.15)
    }

    /// Pomodoro End — completion sound (descending resolution)
    func playPomodoroEnd() {
        // G5 -> E5 -> C5 (descending triad, completion)
        playMelody([
            (frequency: 784, duration: 0.12, delay: 0),
            (frequency: 659, duration: 0.12, delay: 0.1),
            (frequency: 523, duration: 0.18, delay: 0.2)
        ], volume: 0.15)
    }

    /// Break Start — relaxing sound
    func playBreakStart() {
        // Soft G4 -> C5 (fourth interval, calm)
        playMelody([
            (frequency: 392, duration: 0.18, delay: 0),
            (frequency: 523, duration: 0.22, delay: 0.15)
        ], volume: 0.1)
    }

    /// Angry beep — low stern tone
    func playAngrySound() {
        // Low C4 (stern but not harsh)
        playMelody([
            (frequency: 262, duration: 0.25, delay: 0)
        ], volume: 0.18)
    }
}
