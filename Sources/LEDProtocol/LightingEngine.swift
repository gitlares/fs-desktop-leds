import Foundation

public enum LightingMode: String, CaseIterable, Codable, Identifiable {
    case solid, animation, ambient, music, game
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .solid: return "Color"
        case .animation: return L("Animation", "Animación")
        case .ambient: return "Ambient"
        case .music: return L("Music", "Música")
        case .game: return L("Game", "Juego")
        }
    }
}
public enum AnimationStyle: String, CaseIterable, Codable, Identifiable {
    case rainbow, breathe, fade, jump, blink, strobe
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .rainbow: return L("Rainbow", "Arcoíris")
        case .breathe: return L("Breathing", "Respiración")
        case .fade: return L("Fade", "Fundido")
        case .jump: return L("Alternating colors", "Alternancia")
        case .blink: return L("Blink", "Parpadeo")
        case .strobe: return L("Strobe", "Destellos")
        }
    }
}
public enum LightPalette: String, CaseIterable, Codable, Identifiable {
    case selected, rgb, seven, sunset, ocean
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .selected: return L("My color", "Mi color")
        case .rgb: return L("Red · green · blue", "Rojo · verde · azul")
        case .seven: return L("Seven colors", "Siete colores")
        case .sunset: return L("Sunset", "Atardecer")
        case .ocean: return L("Ocean", "Océano")
        }
    }
    public func colors(base: AmbientRGB) -> [AmbientRGB] {
        switch self {
        case .selected: return [base]
        case .rgb: return [0xFF0000, 0x00FF00, 0x0000FF].map(AmbientRGB.init(hex:))
        case .seven:
            return [0xFF0000, 0xFFAA00, 0xFFFF00, 0x00FF00, 0x00FFFF, 0x0000FF, 0xFF00FF].map(
                AmbientRGB.init(hex:))
        case .sunset: return [0xFF4400, 0xFF1478, 0x8C23FF].map(AmbientRGB.init(hex:))
        case .ocean: return [0x007BFF, 0x00DDBB, 0x4522EE].map(AmbientRGB.init(hex:))
        }
    }
}
public enum MusicStyle: String, CaseIterable, Codable, Identifiable {
    case spectrum, beat, pulse
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .spectrum: return L("Frequency colors", "Colores por frecuencias")
        case .beat: return L("Beat colors", "Colores al ritmo")
        case .pulse: return L("Single-color pulse", "Pulso de un color")
        }
    }
}
public enum AudioSource: String, CaseIterable, Codable, Identifiable {
    case system, microphone
    public var id: String { rawValue }
    public var title: String {
        self == .system ? L("Mac audio", "Audio del Mac") : L("Microphone", "Micrófono")
    }
}
public enum ScreenColorStyle: String, CaseIterable, Codable, Identifiable {
    case dominant, average, edges
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .dominant: return L("Dominant color", "Color dominante")
        case .average: return L("Average", "Promedio")
        case .edges: return L("Edges", "Bordes")
        }
    }
}
public enum GameTheme: String, CaseIterable, Codable, Identifiable {
    case automatic, neutral, tactical, forest, neon, western, blocks, horror
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .automatic: return L("Automatic", "Automático")
        case .neutral: return L("No theme", "Sin tema")
        case .tactical: return L("Tactical · Call of Duty", "Táctico · Call of Duty")
        case .forest: return L("Forest · The Last of Us", "Bosque · The Last of Us")
        case .neon: return L("Neon · Cyberpunk", "Neón · Cyberpunk")
        case .western: return L("Western · Red Dead", "Oeste · Red Dead")
        case .blocks: return L("Blocks · Minecraft", "Bloques · Minecraft")
        case .horror: return L("Horror", "Terror")
        }
    }
    public var tint: AmbientRGB? {
        switch self {
        case .automatic, .neutral: return nil
        case .tactical: return .init(hex: 0xB1D040)
        case .forest: return .init(hex: 0x35AC58)
        case .neon: return .init(hex: 0xE02AFF)
        case .western: return .init(hex: 0xFF8536)
        case .blocks: return .init(hex: 0x5FE878)
        case .horror: return .init(hex: 0x5865B2)
        }
    }
    public static func detect(appName: String) -> GameTheme {
        let name = appName.lowercased()
        let rules: [([String], GameTheme)] = [
            (["call of duty", "warzone", "modernwarfare"], .tactical),
            (["last of us", "lastofus"], .forest), (["cyberpunk"], .neon),
            (["red dead", "rdr2"], .western), (["minecraft"], .blocks),
            (["resident evil", "silent hill", "outlast", "amnesia", "alan wake"], .horror),
        ]
        for (words, theme) in rules where words.contains(where: name.contains) { return theme }
        return .neutral
    }
}
extension AmbientRGB {
    public init(hex: Int) {
        self.init(red: UInt8((hex >> 16) & 255), green: UInt8((hex >> 8) & 255), blue: UInt8(hex & 255))
    }
    public var hex: Int { Int(red) << 16 | Int(green) << 8 | Int(blue) }
    public func scaled(_ value: Double) -> AmbientRGB {
        let v = value.isFinite ? min(1, max(0, value)) : 0
        return .init(
            red: UInt8((Double(red) * v).rounded()), green: UInt8((Double(green) * v).rounded()),
            blue: UInt8((Double(blue) * v).rounded()))
    }
    public func blended(with other: AmbientRGB, amount: Double) -> AmbientRGB {
        let t = min(1, max(0, amount))
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(a) * (1 - t) + Double(b) * t).rounded()) }
        return .init(red: mix(red, other.red), green: mix(green, other.green), blue: mix(blue, other.blue))
    }
    public static func hsv(_ hue: Double, _ saturation: Double, _ value: Double) -> AmbientRGB {
        let h = (hue - floor(hue)) * 6
        let s = min(1, max(0, saturation))
        let v = min(1, max(0, value))
        let c = v * s
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let rgb: (Double, Double, Double)
        switch Int(h) {
        case 0: rgb = (c, x, 0)
        case 1: rgb = (x, c, 0)
        case 2: rgb = (0, c, x)
        case 3: rgb = (0, x, c)
        case 4: rgb = (x, 0, c)
        default: rgb = (c, 0, x)
        }
        return .init(
            red: UInt8(((rgb.0 + m) * 255).rounded()), green: UInt8(((rgb.1 + m) * 255).rounded()),
            blue: UInt8(((rgb.2 + m) * 255).rounded()))
    }
}
public enum AnimationRenderer {
    public static func color(style: AnimationStyle, palette: [AmbientRGB], elapsed: Double, speed: Double)
        -> AmbientRGB
    {
        let colors = palette.isEmpty ? [AmbientRGB(hex: 0xFFAA55)] : palette
        let rate = max(0.1, min(3, speed))
        let time = max(0, elapsed) * rate
        let index = Int(time / 2) % colors.count
        let phase = (time / 2).truncatingRemainder(dividingBy: 1)
        let base = colors[index]
        switch style {
        case .rainbow: return .hsv(time / 12, 1, 1)
        case .jump: return colors[Int(time) % colors.count]
        case .breathe: return base.scaled(0.04 + 0.96 * pow((1 - cos(phase * 2 * .pi)) / 2, 1.4))
        case .fade:
            if colors.count == 1 { return base.scaled(1 - abs(2 * phase - 1)) }
            return base.blended(
                with: colors[(index + 1) % colors.count], amount: phase * phase * (3 - 2 * phase))
        case .blink: return base.scaled(phase < 0.5 ? 1 : 0)
        case .strobe: return base.scaled(phase < 0.15 ? 1 : 0)
        }
    }
}
public struct LightScene: Identifiable {
    public let id: String
    public let name: String
    public let hex: Int
    public let brightness: Double
    public static let all: [LightScene] = [
        .init(id: "relax", name: "Relax", hex: 0xFFAC58, brightness: 45),
        .init(id: "focus", name: L("Focus", "Concentración"), hex: 0x8CCBFF, brightness: 65),
        .init(id: "gaming", name: "Gaming", hex: 0xF42380, brightness: 65),
        .init(id: "movie", name: L("Movie", "Cine"), hex: 0x7542BC, brightness: 30),
        .init(id: "sunset", name: L("Sunset", "Atardecer"), hex: 0xFF7038, brightness: 55),
        .init(id: "forest", name: L("Forest", "Bosque"), hex: 0x3AB475, brightness: 45),
        .init(id: "sleep", name: L("Sleep", "Descanso"), hex: 0xFF5020, brightness: 12),
        .init(id: "party", name: L("Party", "Fiesta"), hex: 0xFF34DD, brightness: 75),
        .init(id: "ocean", name: L("Ocean", "Océano"), hex: 0x168DF4, brightness: 50),
        .init(id: "warm", name: L("Warm", "Cálido"), hex: 0xFFCF98, brightness: 60),
        .init(id: "cool", name: L("Cool", "Frío"), hex: 0xC4DEFF, brightness: 60),
        .init(id: "romantic", name: L("Romantic", "Romántico"), hex: 0xE96C90, brightness: 30),
        .init(id: "study", name: L("Study", "Estudio"), hex: 0xFFE8CD, brightness: 80),
        .init(id: "midnight", name: L("Midnight", "Medianoche"), hex: 0x44208B, brightness: 18),
    ]
}
/// Weighted hue groups retain a dominant hue instead of averaging complementary colors to gray.
public enum ScreenColorAnalyzer {
    public static func color(pixels: [AmbientRGB], style: ScreenColorStyle, saturation: Double) -> AmbientRGB
    {
        guard !pixels.isEmpty else { return .init(hex: 0) }
        var buckets = Array(repeating: [AmbientRGB](), count: 24)
        var weights = Array(repeating: 0.0, count: 24)
        for pixel in pixels {
            let r = Double(pixel.red) / 255
            let g = Double(pixel.green) / 255
            let b = Double(pixel.blue) / 255
            let top = max(r, g, b)
            let bottom = min(r, g, b)
            let delta = top - bottom
            guard top > 0.06, delta > 0.10 else { continue }
            let h: Double
            if top == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if top == g {
                h = (b - r) / delta + 2
            } else {
                h = (r - g) / delta + 4
            }
            let normalized = (h / 6 + 1).truncatingRemainder(dividingBy: 1)
            let index = min(23, Int(normalized * 24))
            buckets[index].append(pixel)
            weights[index] += delta
        }
        let winner = weights.indices.max(by: { weights[$0] < weights[$1] }) ?? 0
        let source = style == .dominant && !buckets[winner].isEmpty ? buckets[winner] : pixels
        let count = Double(source.count)
        let r = source.reduce(0.0) { $0 + Double($1.red) } / count
        let g = source.reduce(0.0) { $0 + Double($1.green) } / count
        let b = source.reduce(0.0) { $0 + Double($1.blue) } / count
        let gray = (r + g + b) / 3
        let boost = min(2.5, max(0, saturation))
        func vivid(_ x: Double) -> UInt8 { UInt8(min(255, max(0, gray + (x - gray) * boost)).rounded()) }
        return .init(red: vivid(r), green: vivid(g), blue: vivid(b))
    }
}
public struct AudioLevels: Sendable {
    public var bass: Double, mid: Double, treble: Double, volume: Double
    public init(bass: Double = 0, mid: Double = 0, treble: Double = 0, volume: Double = 0) {
        self.bass = bass
        self.mid = mid
        self.treble = treble
        self.volume = volume
    }
}
/// Streaming three-band energy analysis; state belongs to a single serial capture queue.
public struct AudioAnalyzer {
    private var low = 0.0, upper = 0.0
    public init() {}
    public mutating func process(_ samples: [Float], sampleRate: Double) -> AudioLevels {
        guard !samples.isEmpty, sampleRate > 0 else { return .init() }
        let a = 1 - exp(-2 * .pi * 250 / sampleRate)
        let b = 1 - exp(-2 * .pi * 2800 / sampleRate)
        var bass = 0.0
        var mid = 0.0
        var treble = 0.0
        var total = 0.0
        for raw in samples {
            let x = raw.isFinite ? Double(raw) : 0
            low += a * (x - low)
            upper += b * (x - upper)
            bass += low * low
            mid += (upper - low) * (upper - low)
            treble += (x - upper) * (x - upper)
            total += x * x
        }
        let n = Double(samples.count)
        return .init(
            bass: sqrt(bass / n), mid: sqrt(mid / n), treble: sqrt(treble / n), volume: sqrt(total / n))
    }
}
public struct AudioLightEnvelope {
    private var reference = 0.03, bassAverage = 0.01, volumeAverage = 0.01
    private var beat = 0.0, cooldown = 0.0, hue = 0.0
    public init() {}
    public mutating func color(
        levels: AudioLevels, style: MusicStyle, base: AmbientRGB, sensitivity: Double, delta: Double
    ) -> AmbientRGB {
        let dt = min(0.25, max(0.001, delta))
        let gain = min(4, max(0.2, sensitivity))
        reference = max(0.03, max(levels.volume, reference * exp(-dt / 3)))
        let previousBass = bassAverage
        let previousVolume = volumeAverage
        bassAverage += (levels.bass - bassAverage) * (1 - exp(-dt / 0.7))
        volumeAverage += (levels.volume - volumeAverage) * (1 - exp(-dt / 0.7))
        cooldown = max(0, cooldown - dt)
        beat *= exp(-dt / 0.18)
        guard levels.volume > 0.001 else {
            beat = 0
            return .init(hex: 0)
        }
        // Detect energy rises, not elapsed time: sustained notes do not invent a beat.
        let threshold = 1.15 + 0.3 / gain
        let onset =
            levels.bass > max(0.008, previousBass * threshold)
            || levels.volume > max(0.012, previousVolume * (threshold + 0.1))
        if onset && cooldown == 0 {
            beat = 1
            cooldown = 0.22
            hue = (hue + 0.381966).truncatingRemainder(dividingBy: 1)
            // Following the attack prevents a sustained loud tone from retriggering.
            bassAverage = max(bassAverage, levels.bass)
            volumeAverage = max(volumeAverage, levels.volume)
        }
        let intensity = min(1, levels.volume / reference * gain)
        switch style {
        case .pulse: return base.scaled(pow(intensity, 1.4))
        case .beat:
            return .hsv(hue, 0.95, min(1, intensity * (0.12 + 0.88 * beat)))
        case .spectrum:
            // Emphasize relative band balance instead of clipping all three RGB
            // channels to the same brightness. This preserves saturated colors.
            let bands = [levels.bass, levels.mid * 1.2, levels.treble * 1.8]
            let peak = max(0.0001, bands.max() ?? 0)
            let weights = bands.map { pow(max(0, $0 / peak), 3) }
            let floor = (weights.min() ?? 0) * 0.95
            let scale = max(0.0001, 1 - floor)
            let color = AmbientRGB(
                red: UInt8(min(255, (weights[0] - floor) / scale * 255)),
                green: UInt8(min(255, (weights[1] - floor) / scale * 255)),
                blue: UInt8(min(255, (weights[2] - floor) / scale * 255)))
            let accent = AmbientRGB.hsv(hue, 1, 1)
            return color.blended(with: accent, amount: beat * 0.55).scaled(0.2 + 0.8 * intensity)
        }
    }
}
public struct LightSchedule: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var hour: Int
    public var minute: Int
    public var sceneID: String
    public var enabled = true
    public init(hour: Int, minute: Int, sceneID: String) {
        self.hour = hour
        self.minute = minute
        self.sceneID = sceneID
    }
    public func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        guard enabled, (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return calendar.nextDate(
            after: date, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime,
            repeatedTimePolicy: .first)
    }
}
