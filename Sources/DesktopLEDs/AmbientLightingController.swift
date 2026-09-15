import Combine
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import LEDProtocol

/// macOS capture adapter. It maps the macOS primary display to a tiny stream
/// and sends its average color through the app-level command callback.
// Capture callbacks run off-main, but every mutable member is transferred to
// the main queue before use. The instance can therefore be safely referenced
// by ScreenCaptureKit's Sendable callback closures.
final class AmbientLightingController: NSObject, ObservableObject, SCStreamDelegate, @unchecked Sendable {
    @Published private(set) var isActive = false
    @Published private(set) var status = "Ambient apagado."
    @Published private(set) var displayCount = 0
    @Published private(set) var sampleCount = 0
    @Published private(set) var lastSample: AmbientRGB?
    @Published private(set) var sentCount = 0
    @Published private(set) var needsScreenPermission = false

    private let captureQueue = DispatchQueue(label: "com.gitlares.desktop-leds.capture", qos: .utility)
    private var streams: [SCStream] = []
    private var outputs: [ScreenStreamOutput] = []
    private var samples: [CGDirectDisplayID: DisplayColorSample] = [:]
    private var mixer = AmbientColorMixer()
    private var lastSent = Date.distantPast
    private var lastColor: AmbientRGB?
    private var commandSink: ((LEDCommand) -> Void)?

    // 15 small 64 px samples per second are visually smooth while still
    // processing only a few thousand pixels and bytes of BLE traffic.
    private let frameRate = 15
    private let outputWidth = 64

    func setCommandSink(_ sink: @escaping (LEDCommand) -> Void) {
        commandSink = sink
    }

    func start() {
        guard !isActive else { return }
        Task { @MainActor [weak self] in
            await self?.startCapture()
        }
    }

    func stop() {
        let activeStreams = streams
        streams.removeAll()
        outputs.removeAll()
        samples.removeAll()
        mixer.reset()
        lastColor = nil
        isActive = false
        displayCount = 0
        sampleCount = 0
        lastSample = nil
        sentCount = 0
        status = "Ambient apagado."
        needsScreenPermission = false
        Task {
            for stream in activeStreams { try? await stream.stopCapture() }
        }
    }

    @MainActor
    private func startCapture() async {
        status = "Solicitando acceso a la pantalla…"
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let primaryDisplay = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first else {
                status = "No hay pantallas disponibles para capturar."
                return
            }

            let excludedApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            var newStreams: [SCStream] = []
            var newOutputs: [ScreenStreamOutput] = []
            let configuration = SCStreamConfiguration()
            configuration.width = outputWidth
            configuration.height = max(1, Int(Double(outputWidth) * Double(primaryDisplay.height) / Double(primaryDisplay.width)))
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            configuration.queueDepth = 3
            configuration.capturesAudio = false
            configuration.pixelFormat = kCVPixelFormatType_32BGRA

            let filter = SCContentFilter(display: primaryDisplay, excludingApplications: excludedApps, exceptingWindows: [])
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            let output = ScreenStreamOutput(
                displayID: primaryDisplay.displayID,
                weight: 1,
                owner: self
            )
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: captureQueue)
            try await stream.startCapture()
            newStreams.append(stream)
            newOutputs.append(output)
            streams = newStreams
            outputs = newOutputs
            displayCount = newStreams.count
            sampleCount = 0
            lastSample = nil
            sentCount = 0
            isActive = true
            status = "Ambient activo en el monitor principal."
            needsScreenPermission = false
            // Ambient colors are meant to be visible. Set a known physical
            // state once, then only send bounded color updates per frame.
            commandSink?(.power(true))
            commandSink?(.brightness(100))
        } catch {
            stop()
            let denied = error.localizedDescription.localizedCaseInsensitiveContains("declined")
            needsScreenPermission = denied
            status = denied
                ? "macOS no autorizó Grabación de pantalla para Desktop LEDs."
                : "No se pudo capturar la pantalla: \(error.localizedDescription)"
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.stop()
            self?.status = "La captura se detuvo: \(error.localizedDescription)"
        }
    }

    fileprivate func accept(_ sample: DisplayColorSample, from displayID: CGDirectDisplayID) {
        guard isActive else { return }
        samples[displayID] = sample
        sampleCount += 1
        guard let mixed = mixer.mix(Array(samples.values)) else { return }
        lastSample = mixed
        let now = Date()
        guard now.timeIntervalSince(lastSent) >= 1.0 / Double(frameRate) else { return }
        guard lastColor.map({ Self.colorDistance($0, mixed) >= 4 }) ?? true else { return }
        lastSent = now
        lastColor = mixed
        sentCount += 1
        commandSink?(mixed.command)
    }

    fileprivate static func averageColor(from buffer: CVPixelBuffer) -> AmbientRGB? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0 else { return nil }
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let samplingStride = 4
        var blue = 0.0, green = 0.0, red = 0.0, totalWeight = 0.0
        for y in Swift.stride(from: 0, to: height, by: samplingStride) {
            let row = pixels.advanced(by: y * bytesPerRow)
            for x in Swift.stride(from: 0, to: width, by: samplingStride) {
                let pixel = row.advanced(by: x * 4)
                let pixelBlue = Double(pixel[0])
                let pixelGreen = Double(pixel[1])
                let pixelRed = Double(pixel[2])
                let maximum = max(pixelRed, pixelGreen, pixelBlue)
                let minimum = min(pixelRed, pixelGreen, pixelBlue)
                let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0
                let isEdge = x < width / 5 || x >= width * 4 / 5 || y < height / 5 || y >= height * 4 / 5

                // A whole-frame average is usually gray during films. Give
                // colorful pixels and the screen edges more influence, which
                // is more noticeable on a single-zone strip.
                let weight = (0.15 + saturation * 1.85) * (isEdge ? 1.35 : 1)
                blue += pixelBlue * weight
                green += pixelGreen * weight
                red += pixelRed * weight
                totalWeight += weight
            }
        }
        guard totalWeight > 0 else { return nil }
        let averageRed = red / totalWeight
        let averageGreen = green / totalWeight
        let averageBlue = blue / totalWeight
        let gray = (averageRed + averageGreen + averageBlue) / 3
        func vivid(_ component: Double) -> UInt8 {
            UInt8(min(255, max(0, (gray + (component - gray) * 1.45).rounded())))
        }
        return AmbientRGB(red: vivid(averageRed), green: vivid(averageGreen), blue: vivid(averageBlue))
    }

    fileprivate static func colorDistance(_ lhs: AmbientRGB, _ rhs: AmbientRGB) -> Int {
        let red = abs(Int(lhs.red) - Int(rhs.red))
        let green = abs(Int(lhs.green) - Int(rhs.green))
        let blue = abs(Int(lhs.blue) - Int(rhs.blue))
        return red + green + blue
    }
}

private final class ScreenStreamOutput: NSObject, SCStreamOutput {
    private let displayID: CGDirectDisplayID
    private let weight: Double
    private weak var owner: AmbientLightingController?

    init(displayID: CGDirectDisplayID, weight: Double, owner: AmbientLightingController) {
        self.displayID = displayID
        self.weight = weight
        self.owner = owner
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, let pixelBuffer = sampleBuffer.imageBuffer,
              let color = AmbientLightingController.averageColor(from: pixelBuffer) else { return }
        let sample = DisplayColorSample(color: color, weight: weight)
        DispatchQueue.main.async { [weak owner] in owner?.accept(sample, from: self.displayID) }
    }
}
