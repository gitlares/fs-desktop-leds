import AppKit
import Combine
import LEDProtocol
import ServiceManagement

struct LightingSettings: Codable, Equatable {
    var mode = LightingMode.solid
    var hex = 0xFFAC58
    var brightness = 50.0
    var animation = AnimationStyle.rainbow
    var palette = LightPalette.seven
    var speed = 1.0
    var music = MusicStyle.spectrum
    var audioSource = AudioSource.system
    var sensitivity = 1.2
    var smoothing = 0.45
    var saturation = 1.4
    var screenStyle = ScreenColorStyle.dominant
    var displayID: UInt32 = 0
    var gameTheme = GameTheme.automatic
    var nightDimming = false
}

@MainActor
final class LightingController: ObservableObject {
    let bluetooth = BluetoothController()
    let capture = MediaCaptureController()
    let notifications = NotificationLightMonitor()
    let updater = AppUpdater()
    private struct FlashState {
        let started: Double
        let resumeMode: Bool
        let color: AmbientRGB
    }
    private var flashState: FlashState?
    @Published var settings: LightingSettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: "lighting.settings.v1")
            }
            guard initialized else { return }
            if settings.music != oldValue.music { envelope = .init() }
            if settings.nightDimming != oldValue.nightDimming { scheduleNightTimer() }
            if isOn {
                if settings.mode != oldValue.mode || settings.audioSource != oldValue.audioSource
                    || settings.displayID != oldValue.displayID
                    || settings.screenStyle != oldValue.screenStyle
                    || settings.saturation != oldValue.saturation
                {
                    restartWork?.cancel()
                    let work = DispatchWorkItem { [weak self] in self?.startMode() }
                    restartWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
                } else {
                    if settings.brightness != oldValue.brightness
                        || settings.nightDimming != oldValue.nightDimming
                    {
                        applyBrightness()
                    }
                    if settings.mode == .solid { startTimer() }
                }
            }
        }
    }
    @Published private(set) var isOn = false {
        didSet { UserDefaults.standard.set(isOn, forKey: "lighting.active") }
    }
    private(set) var currentColor = AmbientRGB(hex: 0xFFAC58)
    private(set) var audioLevel = 0.0
    private(set) var audioReceived = false
    @Published private(set) var message = ""
    @Published private(set) var activeTheme = GameTheme.neutral
    @Published var schedules: [LightSchedule] = [] {
        didSet {
            saveSchedules()
            scheduleNext()
        }
    }
    @Published private(set) var sleepDeadline: Date?
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginMessage = ""
    private var subscriptions = Set<AnyCancellable>()
    private var initialized = false
    private var timer: Timer?
    private var sleepTimer: Timer?
    private var scheduleTimer: Timer?
    private var nightTimer: Timer?
    private var restartWork: DispatchWorkItem?
    private var sceneStarted = ProcessInfo.processInfo.systemUptime
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var lastAudioTime = -Double.infinity
    private var levels = AudioLevels()
    private var envelope = AudioLightEnvelope()
    private var screenColor: AmbientRGB?
    private var lastSent: AmbientRGB?
    private var sleeping = false
    private var terminating = false

    init() {
        settings =
            UserDefaults.standard.data(forKey: "lighting.settings.v1").flatMap {
                try? JSONDecoder().decode(LightingSettings.self, from: $0)
            } ?? LightingSettings()
        schedules =
            UserDefaults.standard.data(forKey: "lighting.schedules.v1").flatMap {
                try? JSONDecoder().decode([LightSchedule].self, from: $0)
            } ?? []
        isOn = UserDefaults.standard.bool(forKey: "lighting.active")
        loginEnabled = SMAppService.mainApp.status == .enabled
        notifications.onNotification = { [weak self] in self?.flashNotification() }
        notifications.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(
            in: &subscriptions)
        capture.onColor = { [weak self] color in self?.screenColor = color }
        capture.onAudio = { [weak self] levels in
            guard let self else { return }
            self.levels = levels
            self.lastAudioTime = ProcessInfo.processInfo.systemUptime
            self.audioReceived = true
        }
        capture.onFailure = { [weak self] in
            guard let self else { return }
            if let flash = self.flashState, flash.resumeMode {
                self.bluetooth.discardPendingCommands()
                self.bluetooth.send(flash.color.command)
                self.flashState = nil
            }
            self.timer?.invalidate()
            self.timer = nil
            self.isOn = false
            self.message = self.capture.status
        }
        let connectionChanges = Publishers.MergeMany([
            bluetooth.$status.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            bluetooth.$ready.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            bluetooth.$scanning.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            bluetooth.$connecting.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            bluetooth.$selectedName.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            bluetooth.$profile.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            bluetooth.$devices.map { _ in () }.eraseToAnyPublisher(),
        ])
        connectionChanges.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        capture.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(
            in: &subscriptions)
        bluetooth.$ready.removeDuplicates().sink { [weak self] ready in
            DispatchQueue.main.async {
                guard let self else { return }
                if ready && self.isOn && !self.sleeping {
                    self.startMode()
                } else if ready {
                    self.message = ""
                }
                if !ready {
                    self.stopRuntime()
                    self.message = L("Waiting for connection", "Esperando conexión")
                }
            }
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification).sink {
            [weak self] _ in
            self?.sleeping = true
            self?.stopRuntime()
            self?.scheduleTimer?.invalidate()
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink {
            [weak self] _ in
            guard let self else { return }
            self.sleeping = false
            if let deadline = self.sleepDeadline, deadline <= Date() {
                self.powerOff()
            } else if self.isOn && self.bluetooth.ready {
                self.startMode()
            }
            self.scheduleNext()
            self.scheduleNightTimer()
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    app.bundleIdentifier != Bundle.main.bundleIdentifier
                else { return }
                let theme = GameTheme.detect(appName: app.localizedName ?? "")
                if self?.activeTheme != theme { self?.activeTheme = theme }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).sink {
            [weak self] _ in
            guard let self else { return }
            Task { await self.capture.refreshDisplays() }
            if self.isOn && [.ambient, .game, .music].contains(self.settings.mode) { self.startMode() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange).sink {
            [weak self] _ in
            self?.scheduleNext()
            self?.scheduleNightTimer()
        }.store(in: &subscriptions)
        initialized = true
        Task { await capture.refreshDisplays() }
        bluetooth.restoreIfKnown()
        scheduleNext()
        scheduleNightTimer()
    }
    func choose(_ mode: LightingMode) {
        guard !terminating else { return }
        settings.mode = mode
        isOn = true
        startMode()
    }
    func setColor(_ color: AmbientRGB) {
        settings.hex = color.hex
        if settings.mode != .solid { choose(.solid) } else if !isOn { choose(.solid) }
    }
    func scene(_ scene: LightScene) {
        var next = settings
        next.mode = .solid
        next.hex = scene.hex
        next.brightness = scene.brightness
        settings = next
        isOn = true
        startMode()
    }
    func powerOn() {
        isOn = true
        startMode()
    }
    func powerOff() {
        isOn = false
        stopRuntime()
        bluetooth.stopProbe()
        bluetooth.discardPendingCommands()
        bluetooth.send(.power(false))
        cancelSleepTimer()
        message = L("Lights off", "Luces apagadas")
    }
    func prepareForTermination() async {
        terminating = true
        notifications.onNotification = nil
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        nightTimer?.invalidate()
        nightTimer = nil
        powerOff()
        await bluetooth.finishPendingWrites()
        bluetooth.disconnect()
    }
    func pauseForDiagnostics() {
        isOn = false
        stopRuntime()
        bluetooth.discardPendingCommands()
        message = L("Mode paused for testing", "Modo pausado para pruebas")
    }
    func flashNotification() {
        guard !terminating, bluetooth.ready, !sleeping, !bluetooth.probing, flashState == nil else { return }
        flashState = FlashState(
            started: ProcessInfo.processInfo.systemUptime, resumeMode: isOn, color: currentColor)
        lastSent = nil
        bluetooth.discardPendingCommands()
        bluetooth.send(.power(true))
        applyBrightness()
        startTimer()
    }
    private func stopRuntime() {
        if flashState != nil && !isOn && bluetooth.ready { bluetooth.send(.power(false)) }
        flashState = nil
        restartWork?.cancel()
        restartWork = nil
        timer?.invalidate()
        timer = nil
        capture.stop()
        levels = .init()
        audioLevel = 0
        audioReceived = false
        lastAudioTime = -Double.infinity
        screenColor = nil
        lastSent = nil
    }
    private func startMode() {
        stopRuntime()
        guard !terminating, isOn, bluetooth.ready, !sleeping else {
            message = L("Connect your lights to start", "Conecta tus luces para iniciar")
            return
        }
        bluetooth.stopProbe()
        bluetooth.discardPendingCommands()
        bluetooth.send(.power(true))
        applyBrightness()
        sceneStarted = ProcessInfo.processInfo.systemUptime
        lastTick = sceneStarted
        envelope = .init()
        message = settings.mode.title
        if [.ambient, .music, .game].contains(settings.mode) {
            capture.start(
                screen: settings.mode != .music, audio: settings.mode != .ambient,
                source: settings.audioSource, displayID: settings.displayID, style: settings.screenStyle,
                saturation: settings.saturation)
        }
        startTimer()
    }
    private func startTimer() {
        guard timer == nil, isOn || flashState != nil, bluetooth.ready else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func applyBrightness() {
        let hour = Calendar.current.component(.hour, from: Date())
        let ceiling = settings.nightDimming && (hour >= 22 || hour < 7) ? 25.0 : 100.0
        bluetooth.send(.brightness(Int(min(ceiling, max(0, min(100, settings.brightness))))))
    }
    private func tick() {
        guard bluetooth.ready, !bluetooth.probing else { return }
        if let flash = flashState {
            let elapsed = ProcessInfo.processInfo.systemUptime - flash.started
            if let color = NotificationFlash.color(elapsed: elapsed) {
                if lastSent != color {
                    bluetooth.send(color.command)
                    lastSent = color
                }
                return
            }
            flashState = nil
            lastSent = nil
            bluetooth.discardPendingCommands()
            if !flash.resumeMode {
                bluetooth.send(.power(false))
                timer?.invalidate()
                timer = nil
                return
            }
            // Restore the snapshot before resuming rendering, including slow or
            // temporarily unavailable screen/audio capture. Never leave the final
            // black frame of the alert as the strip's current color.
            isOn = true
            currentColor = flash.color
            bluetooth.send(.power(true))
            applyBrightness()
            bluetooth.send(flash.color.command)
            lastSent = flash.color
            lastTick = ProcessInfo.processInfo.systemUptime
            sceneStarted += elapsed
            return
        }
        guard isOn else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.25, max(0.001, now - lastTick))
        lastTick = now
        let base = AmbientRGB(hex: settings.hex)
        let freshLevels = now - lastAudioTime < 0.4 ? levels : AudioLevels()
        audioLevel = min(1, freshLevels.volume * 5)
        let target: AmbientRGB
        switch settings.mode {
        case .solid: target = base
        case .animation:
            target = AnimationRenderer.color(
                style: settings.animation, palette: settings.palette.colors(base: base),
                elapsed: now - sceneStarted, speed: settings.speed)
        case .ambient:
            guard let color = screenColor else { return }
            target = color
        case .music:
            guard capture.running else { return }
            target = envelope.color(
                levels: freshLevels, style: settings.music, base: base, sensitivity: settings.sensitivity,
                delta: dt)
        case .game:
            guard capture.running, var color = screenColor else { return }
            let theme = settings.gameTheme == .automatic ? activeTheme : settings.gameTheme
            if let tint = theme.tint { color = color.blended(with: tint, amount: 0.22) }
            let pulse = envelope.color(
                levels: freshLevels, style: .beat, base: .init(hex: 0xFFD595),
                sensitivity: settings.sensitivity, delta: dt)
            color = color.scaled(0.45 + min(0.55, freshLevels.volume * settings.sensitivity * 4))
            target = color.blended(with: pulse, amount: Double(pulse.red) / 255 * 0.5)
        }
        let immediate = settings.mode == .animation && [.jump, .blink, .strobe].contains(settings.animation)
        // Screen smoothing is intentionally slower; music must preserve short attacks.
        let smoothingTime =
            settings.mode == .music ? 0.035 + settings.smoothing * 0.09 : 0.04 + settings.smoothing * 0.8
        let response = immediate ? 1 : 1 - exp(-dt / smoothingTime)
        let mixed = currentColor.blended(with: target, amount: response)
        // Snap near target to avoid integer rounding leaving a permanent tint.
        let next = colorDistance(mixed, target) <= 8 ? target : mixed
        currentColor = next
        if lastSent.map({ colorDistance($0, next) >= 3 }) ?? true {
            bluetooth.send(next.command)
            lastSent = next
        }
        if settings.mode == .solid && next == target {
            timer?.invalidate()
            timer = nil
        }
    }
    private func colorDistance(_ a: AmbientRGB, _ b: AmbientRGB) -> Int {
        abs(Int(a.red) - Int(b.red)) + abs(Int(a.green) - Int(b.green)) + abs(Int(a.blue) - Int(b.blue))
    }
    func setSleepTimer(minutes: Int) {
        cancelSleepTimer()
        sleepDeadline = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: false) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.powerOff() }
        }
    }
    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepDeadline = nil
    }
    private func saveSchedules() {
        if let data = try? JSONEncoder().encode(schedules) {
            UserDefaults.standard.set(data, forKey: "lighting.schedules.v1")
        }
    }
    private func scheduleNext() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        guard !sleeping else { return }
        let now = Date()
        let candidates = schedules.compactMap { rule -> (LightSchedule, Date)? in
            rule.nextDate(after: now).map { (rule, $0) }
        }
        guard let first = candidates.min(by: { $0.1 < $1.1 }) else { return }
        let due = candidates.filter { abs($0.1.timeIntervalSince(first.1)) < 1 }.map(\.0)
        scheduleTimer = Timer(fire: first.1, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Do not replay old events after sleep, clock changes, or a stalled run loop.
                if abs(Date().timeIntervalSince(first.1)) < 90, !self.sleeping {
                    for rule in due {
                        if rule.sceneID == "off" {
                            self.powerOff()
                        } else if self.bluetooth.ready,
                            let scene = LightScene.all.first(where: { $0.id == rule.sceneID })
                        {
                            self.scene(scene)
                        } else {
                            self.message = L(
                                "Schedule skipped: lights disconnected",
                                "Horario omitido: luces desconectadas")
                        }
                    }
                }
                self.scheduleNext()
            }
        }
        RunLoop.main.add(scheduleTimer!, forMode: .common)
    }
    private func scheduleNightTimer() {
        nightTimer?.invalidate()
        nightTimer = nil
        guard settings.nightDimming else { return }
        if isOn { applyBrightness() }
        let next = Calendar.current.nextDate(
            after: Date(), matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime)!
        nightTimer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleNightTimer() }
        }
        RunLoop.main.add(nightTimer!, forMode: .common)
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginMessage =
                SMAppService.mainApp.status == .requiresApproval
                ? L(
                    "Allow launch at login in System Settings → Login Items.",
                    "Autoriza el inicio en Ajustes del Sistema → Ítems de inicio.") : ""
        } catch { loginMessage = error.localizedDescription }
    }
}
