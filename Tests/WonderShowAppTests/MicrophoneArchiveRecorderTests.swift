@testable import WonderShowApp
@preconcurrency import AVFoundation
import Testing

@Suite(.serialized)
struct MicrophoneArchiveRecorderTests {
    @Test func microphoneArchiveNormalizesCaptureFormatBeforeAacEncoding() {
        let captureSettings = MicrophoneArchiveAudioSettings.capturePCM()
        let writerSettings = MicrophoneArchiveAudioSettings.writerAAC()

        #expect(captureSettings[AVFormatIDKey] as? AudioFormatID == kAudioFormatLinearPCM)
        #expect(captureSettings[AVSampleRateKey] as? Int == 48_000)
        #expect(captureSettings[AVNumberOfChannelsKey] as? Int == 1)
        #expect(captureSettings[AVLinearPCMBitDepthKey] as? Int == 16)
        #expect(writerSettings[AVFormatIDKey] as? AudioFormatID == kAudioFormatMPEG4AAC)
        #expect(writerSettings[AVSampleRateKey] as? Int == 48_000)
        #expect(writerSettings[AVEncoderBitRateKey] as? Int == 128_000)
    }

    @Test func microphoneArchiveWriterSettingsAreAcceptedByAVFoundation() {
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: MicrophoneArchiveAudioSettings.writerAAC()
        )

        #expect(input.mediaType == .audio)
    }
}
