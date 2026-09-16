import AVFoundation
import AppKit
import Combine
import CoreGraphics
import CoreMedia
import CoreVideo
import LEDProtocol
import ScreenCaptureKit

struct CaptureDisplay: Identifiable {
    let id: UInt32
    let name: String
}

/// Owns one capture session. Generation checks prevent a stopped permission/start
/// request from reviving capture after switching modes or disconnecting.
@MainActor
final class MediaCaptureController: NSObject, ObservableObject, SCStreamDelegate {
    @Published private(set) var displays: [CaptureDisplay] = []
    @Published private(set) var status = ""
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var needsPermission = false
    var onColor: ((AmbientRGB) -> Void)?
    var onAudio: ((AudioLevels) -> Void)?
    var onFailure: (() -> Void)?
    private var generation = UUID()
    private var activeStream: SCStream?
    private var output: MediaOutput?
    private var microphone: AVAudioEngine?
    private let queue = DispatchQueue(label: "com.gitlares.desktop-leds.media", qos: .utility)

    func refreshDisplays() async {
        // CoreGraphics inventory does not trigger Screen Recording permission.
        displays = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            return CaptureDisplay(id: number.uint32Value, name: screen.localizedName)
        }
    }
    func stop() {
        generation = UUID()
        starting = false
        running = false
        let old = activeStream
        activeStream = nil
        output = nil
        if let microphone {
            microphone.inputNode.removeTap(onBus: 0)
            microphone.stop()
        }
        microphone = nil
        if let old { Task { try? await old.stopCapture() } }
        status = ""
        needsPermission = false
    }
    func start(
        screen: Bool, audio: Bool, source: AudioSource, displayID: UInt32, style: ScreenColorStyle,
        saturation: Double
    ) {
        stop()
        let token = generation
        starting = true
        status = L("Starting capture…", "Preparando captura…")
        let requiresScreenCapture = screen || (audio && source == .system)
        Task { [self] in
            do {
                let receiver = MediaOutput(
                    screenStyle: style, saturation: saturation,
                    color: { [weak self] color in
                        Task { @MainActor in
                            guard let self, self.generation == token else { return }
                            self.onColor?(color)
                        }
                    },
                    audio: { [weak self] levels in
                        Task { @MainActor in
                            guard let self, self.generation == token else { return }
                            self.onAudio?(levels)
                        }
                    })
                if audio && source == .microphone {
                    let allowed = await AVCaptureDevice.requestAccess(for: .audio)
                    guard generation == token else { return }
                    guard allowed else { throw CaptureError.microphoneDenied }
                    let engine = AVAudioEngine()
                    let format = engine.inputNode.outputFormat(forBus: 0)
                    guard format.channelCount > 0, format.sampleRate > 0 else {
                        throw CaptureError.noMicrophone
                    }
                    engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                        guard let data = buffer.floatChannelData else { return }
                        let samples = Array(
                            UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
                        receiver.acceptAudio(samples, rate: buffer.format.sampleRate)
                    }
                    microphone = engine
                    try engine.start()
                }
                if requiresScreenCapture {
                    // Ask TCC explicitly from the user-initiated mode change.
                    // ScreenCaptureKit can otherwise only return an opaque
                    // failure after permission changes in System Settings.
                    guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                        throw CaptureError.screenCaptureDenied
                    }
                    let content = try await SCShareableContent.excludingDesktopWindows(
                        false, onScreenWindowsOnly: true)
                    guard generation == token else { return }
                    guard
                        let display = content.displays.first(where: {
                            $0.displayID == (displayID == 0 ? CGMainDisplayID() : displayID)
                        }) ?? content.displays.first
                    else { throw CaptureError.noDisplay }
                    let configuration = SCStreamConfiguration()
                    configuration.width = screen ? 96 : 2
                    configuration.height = screen ? max(2, 96 * display.height / display.width) : 2
                    configuration.minimumFrameInterval = CMTime(value: 1, timescale: screen ? 15 : 1)
                    configuration.queueDepth = 3
                    configuration.showsCursor = false
                    configuration.pixelFormat = kCVPixelFormatType_32BGRA
                    configuration.colorSpaceName = CGColorSpace.sRGB
                    configuration.capturesAudio = audio && source == .system
                    configuration.sampleRate = 48000
                    configuration.channelCount = 2
                    configuration.excludesCurrentProcessAudio = true
                    let excluded = content.applications.filter {
                        $0.bundleIdentifier == Bundle.main.bundleIdentifier
                    }
                    let filter = SCContentFilter(
                        display: display, excludingApplications: excluded, exceptingWindows: [])
                    let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
                    // Screen output is drained even for an audio-only session, but not analyzed.
                    receiver.analyzeScreen = screen
                    try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: queue)
                    if configuration.capturesAudio {
                        try stream.addStreamOutput(receiver, type: .audio, sampleHandlerQueue: queue)
                    }
                    try await stream.startCapture()
                    guard generation == token else {
                        try? await stream.stopCapture()
                        return
                    }
                    activeStream = stream
                }
                guard generation == token else { return }
                output = receiver
                starting = false
                running = true
                status =
                    audio
                    ? (source == .system
                        ? L("Listening to Mac audio", "Escuchando el audio del Mac")
                        : L("Listening to the microphone", "Escuchando el micrófono"))
                    : L("Reading screen colors", "Leyendo colores de pantalla")
            } catch {
                guard generation == token else { return }
                stop()
                let screenDenied = requiresScreenCapture && !CGPreflightScreenCaptureAccess()
                needsPermission = (error as? CaptureError) == .microphoneDenied || screenDenied
                status = screenDenied
                    ? L(
                        "Screen Recording permission is required. If you just enabled it, quit and reopen Desktop LEDs.",
                        "Se necesita permiso de Grabación de pantalla. Si acabas de activarlo, cierra y abre Desktop LEDs.")
                    : L(
                        "Could not start: \(error.localizedDescription)",
                        "No se pudo iniciar: \(error.localizedDescription)")
                onFailure?()
            }
        }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.activeStream === stream else { return }
            self.stop()
            self.status = L(
                "Capture stopped: \(error.localizedDescription)",
                "La captura se detuvo: \(error.localizedDescription)")
            self.onFailure?()
        }
    }
}
private enum CaptureError: LocalizedError {
    case microphoneDenied, screenCaptureDenied, noMicrophone, noDisplay
    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return L(
                "Allow microphone access in System Settings.", "Permite el micrófono en Ajustes del Sistema.")
        case .screenCaptureDenied:
            return L(
                "Allow Screen Recording in System Settings.", "Permite Grabación de pantalla en Ajustes del Sistema.")
        case .noMicrophone: return L("No microphone is available.", "No hay un micrófono disponible.")
        case .noDisplay: return L("No display is available.", "No hay una pantalla disponible.")
        }
    }
}

private final class MediaOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    var analyzeScreen = true  // configured before registering outputs
    private let screenStyle: ScreenColorStyle
    private let saturation: Double
    private let colorSink: (AmbientRGB) -> Void
    private let audioSink: (AudioLevels) -> Void
    private let audioLock = NSLock()
    private var analyzer = AudioAnalyzer()
    private var lastAudio = ProcessInfo.processInfo.systemUptime
    private var accumulated = AudioLevels()
    init(
        screenStyle: ScreenColorStyle, saturation: Double, color: @escaping (AmbientRGB) -> Void,
        audio: @escaping (AudioLevels) -> Void
    ) {
        self.screenStyle = screenStyle
        self.saturation = saturation
        colorSink = color
        audioSink = audio
    }
    func acceptAudio(_ samples: [Float], rate: Double) {
        audioLock.lock()
        defer { audioLock.unlock() }
        autoreleasepool {
            let levels = analyzer.process(samples, sampleRate: rate)
            accumulated.bass = max(accumulated.bass, levels.bass)
            accumulated.mid = max(accumulated.mid, levels.mid)
            accumulated.treble = max(accumulated.treble, levels.treble)
            accumulated.volume = max(accumulated.volume, levels.volume)
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastAudio >= 1.0 / 15 {
                audioSink(accumulated)
                accumulated = .init()
                lastAudio = now
            }
        }
    }
    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid else { return }
        if outputType == .audio {
            guard let description = sampleBuffer.formatDescription,
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
                asbd.mFormatID == kAudioFormatLinearPCM,
                asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0, asbd.mBitsPerChannel == 32
            else { return }
            try? sampleBuffer.withAudioBufferList { list, _ in
                guard let first = list.first, let raw = first.mData else { return }
                let channelStride = max(1, Int(first.mNumberChannels))
                let count = min(Int(sampleBuffer.numSamples), Int(first.mDataByteSize) / 4 / channelStride)
                let data = raw.assumingMemoryBound(to: Float.self)
                var mono = [Float]()
                mono.reserveCapacity(count)
                for i in 0..<count {
                    // Average channels in either interleaved or planar Float32 layouts.
                    var sum: Float = 0
                    var channels: Float = 0
                    for buffer in list {
                        guard let bytes = buffer.mData else { continue }
                        let width = max(1, Int(buffer.mNumberChannels))
                        guard (i + 1) * width * 4 <= Int(buffer.mDataByteSize) else { continue }
                        let floats = bytes.assumingMemoryBound(to: Float.self)
                        for ch in 0..<width {
                            sum += floats[i * width + ch]
                            channels += 1
                        }
                    }
                    mono.append(channels > 0 ? sum / channels : data[i * channelStride])
                }
                acceptAudio(mono, rate: asbd.mSampleRate)
            }
        } else if outputType == .screen, analyzeScreen {
            guard
                let attachments = CMSampleBufferGetSampleAttachmentsArray(
                    sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                let rawStatus = attachments.first?[.status] as? Int,
                SCFrameStatus(rawValue: rawStatus) == .complete,
                let buffer = sampleBuffer.imageBuffer
            else { return }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
            let w = CVPixelBufferGetWidth(buffer)
            let h = CVPixelBufferGetHeight(buffer)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            var pixels = [AmbientRGB]()
            pixels.reserveCapacity(w * h / 4)
            for y in Swift.stride(from: 0, to: h, by: 2) {
                for x in Swift.stride(from: 0, to: w, by: 2) {
                    if screenStyle == .edges && x > w / 5 && x < w * 4 / 5 && y > h / 5 && y < h * 4 / 5 {
                        continue
                    }
                    let p = bytes.advanced(by: y * stride + x * 4)
                    pixels.append(.init(red: p[2], green: p[1], blue: p[0]))
                }
            }
            colorSink(ScreenColorAnalyzer.color(pixels: pixels, style: screenStyle, saturation: saturation))
        }
    }
}
