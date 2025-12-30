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

    /// Warning — very gentle single soft tone (like a whisper)
    func playWarningSound() {
        // Single soft G5 — minimal intrusion
        playMelody([
            (frequency: 784, duration: 0.1, delay: 0)
        ], volume: 0.06)
    }

    /// Distracted — soft descending tone (gentle reminder, not scolding)
    func playDistractedSound() {
        // E5 -> D5 (just a step down, gentle nudge)
        playMelody([
            (frequency: 659, duration: 0.12, delay: 0),
            (frequency: 587, duration: 0.15, delay: 0.1)
        ], volume: 0.08)
    }

    /// Welcome Back — warm ascending (relieved and happy)
    func playWelcomeBackSound() {
        // G4 -> C5 -> E5 (warm major, welcoming)
        playMelody([
            (frequency: 392, duration: 0.1, delay: 0),
            (frequency: 523, duration: 0.1, delay: 0.08),
            (frequency: 659, duration: 0.14, delay: 0.16)
        ], volume: 0.08)
    }

    /// Happy chirp — tiny cheerful blip
    func playHappyChirp() {
        // Single quick high note
        playMelody([
            (frequency: 880, duration: 0.05, delay: 0)
        ], volume: 0.05)
    }

    /// Click — barely audible tap
    func playClick() {
        playMelody([
            (frequency: 800, duration: 0.015, delay: 0)
        ], volume: 0.04)
    }

    /// Love — sweet soft arpeggio
    func playLoveSound() {
        // C5 -> E5 -> G5 (simple triad, gentle)
        playMelody([
            (frequency: 523, duration: 0.1, delay: 0),
            (frequency: 659, duration: 0.1, delay: 0.08),
            (frequency: 784, duration: 0.14, delay: 0.16)
        ], volume: 0.07)
    }

    /// Pomodoro Start — clear but soft
    func playPomodoroStart() {
        // C5 -> G5 (perfect fifth, confident but quiet)
        playMelody([
            (frequency: 523, duration: 0.1, delay: 0),
            (frequency: 784, duration: 0.12, delay: 0.08)
        ], volume: 0.08)
    }

    /// Pomodoro End — satisfying completion
    func playPomodoroEnd() {
        // G5 -> C5 (octave down feels like completion)
        playMelody([
            (frequency: 784, duration: 0.1, delay: 0),
            (frequency: 523, duration: 0.15, delay: 0.1)
        ], volume: 0.08)
    }

    /// Break Start — relaxing descending
    func playBreakStart() {
        // E5 -> C5 (major third down, relaxing)
        playMelody([
            (frequency: 659, duration: 0.15, delay: 0),
            (frequency: 523, duration: 0.2, delay: 0.12)
        ], volume: 0.06)
    }

    /// Gentle nudge — for grace period ending (even softer than warning)
    func playGentleNudge() {
        // Very soft single tone
        playMelody([
            (frequency: 600, duration: 0.08, delay: 0)
        ], volume: 0.04)
    }

    /// Celebration — for milestones
    func playCelebration() {
        // Quick happy arpeggio
        playMelody([
            (frequency: 523, duration: 0.06, delay: 0),
            (frequency: 659, duration: 0.06, delay: 0.05),
            (frequency: 784, duration: 0.08, delay: 0.1)
        ], volume: 0.06)
    }

    /// Angry beep — still soft but lower (disappointed, not aggressive)
    func playAngrySound() {
        // Low tone, but still gentle
        playMelody([
            (frequency: 330, duration: 0.2, delay: 0)
        ], volume: 0.1)
    }
}
