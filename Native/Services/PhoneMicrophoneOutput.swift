import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

@MainActor
final class PhoneMicrophoneOutput {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var queuedBuffers = 0
    private var previousInputDeviceID: AudioDeviceID?
    private(set) var isRunning = false

    func start() -> String? {
        guard !isRunning else { return nil }
        guard let deviceID = Self.blackHoleDeviceID() else {
            return "Mac에 BlackHole 2ch 입력 장치가 없습니다."
        }
        guard let outputUnit = engine.outputNode.audioUnit else {
            return "Mac 오디오 출력 장치를 열 수 없습니다."
        }
        var selectedDeviceID = deviceID
        let status = AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selectedDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { return "BlackHole 2ch를 선택할 수 없습니다. (\(status))" }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            player.play()
            if let currentInput = Self.defaultInputDeviceID(), currentInput != deviceID {
                let status = Self.setDefaultInputDevice(deviceID)
                guard status == noErr else {
                    player.stop()
                    engine.stop()
                    engine.detach(player)
                    return "Mac 기본 마이크를 BlackHole 2ch로 변경할 수 없습니다. (\(status))"
                }
                previousInputDeviceID = currentInput
            }
            isRunning = true
            return nil
        } catch {
            engine.stop()
            engine.detach(player)
            return "Mac 마이크 입력을 시작할 수 없습니다: \(error.localizedDescription)"
        }
    }

    func enqueue(_ data: Data) {
        guard isRunning, data.count == 640, queuedBuffers < 12,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320),
              let samples = buffer.int16ChannelData?[0] else { return }
        buffer.frameLength = 320
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            memcpy(samples, base, data.count)
        }
        queuedBuffers += 1
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.queuedBuffers = max(0, self.queuedBuffers - 1)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        player.stop()
        engine.stop()
        engine.detach(player)
        if let previousInputDeviceID, Self.defaultInputDeviceID() == Self.blackHoleDeviceID() {
            _ = Self.setDefaultInputDevice(previousInputDeviceID)
        }
        previousInputDeviceID = nil
        queuedBuffers = 0
        isRunning = false
    }

    private static func blackHoleDeviceID() -> AudioDeviceID? {
        let uid = "BlackHole2ch_UID" as CFString
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDeviceForUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafePointer(to: uid) { uidPointer in
            withUnsafeMutablePointer(to: &deviceID) { devicePointer in
                var translation = AudioValueTranslation(
                    mInputData: UnsafeMutableRawPointer(mutating: uidPointer),
                    mInputDataSize: UInt32(MemoryLayout<CFString>.size),
                    mOutputData: devicePointer,
                    mOutputDataSize: UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
                return AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &translation
                )
            }
        }
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    private static func setDefaultInputDevice(_ deviceID: AudioDeviceID) -> OSStatus {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var selectedDeviceID = deviceID
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &selectedDeviceID
        )
    }
}
