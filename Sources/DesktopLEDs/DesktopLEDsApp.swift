import AppKit
import LEDProtocol
import SwiftUI

@main
@MainActor
struct DesktopLEDsApp: App {
    @NSApplicationDelegateAdaptor(LEDApplicationDelegate.self) private var appDelegate
    @StateObject private var model: LightingController
    init() {
        // Start reconnection and schedules even before the user opens the menu.
        let controller = LightingController()
        _model = StateObject(wrappedValue: controller)
        LEDApplicationDelegate.controller = controller
    }
    var body: some Scene {
        MenuBarExtra("Desktop LEDs", systemImage: "lightbulb.led.fill") {
            MenuControls(model: model)
        }.menuBarExtraStyle(.menu)
    }
}

struct MenuControls: View {
    @ObservedObject var model: LightingController
    @State private var scheduleHour = 22
    @State private var scheduleMinute = 0
    @State private var scheduleScene = "off"
    private let colors: [(String, Int)] = [
        (L("Warm white", "Blanco cálido"), 0xFFCF98),
        (L("White", "Blanco"), 0xFFFFFF), (L("Cool white", "Blanco frío"), 0xC4DEFF),
        (L("Red", "Rojo"), 0xFF0000), (L("Orange", "Naranja"), 0xFF8800), (L("Yellow", "Amarillo"), 0xFFFF00),
        (L("Green", "Verde"), 0x00FF00), (L("Cyan", "Cian"), 0x00FFFF), (L("Blue", "Azul"), 0x0000FF),
        (L("Violet", "Violeta"), 0xBB00FF), (L("Pink", "Rosa"), 0xFF3388), ("Magenta", 0xFF00FF),
    ]
    var body: some View {
        Group {
            Text(model.bluetooth.selectedName ?? "Desktop LEDs")
            Text(
                model.bluetooth.ready
                    ? (model.isOn
                        ? L("Active · \(model.settings.mode.title)", "Activo · \(model.settings.mode.title)")
                        : L("Lights paused", "Luces en pausa")) : model.bluetooth.status)
            Button(model.isOn ? L("Turn lights off", "Apagar luces") : L("Turn lights on", "Encender luces"))
            { model.isOn ? model.powerOff() : model.powerOn() }
            .disabled(!model.bluetooth.ready)
            Divider()
            Menu(modeTitle("Color", selected: model.settings.mode == .solid && !selectedScene)) {
                ForEach(colors, id: \.0) { name, hex in
                    MenuChoice(
                        name, selected: model.settings.mode == .solid && model.settings.hex == hex, hex: hex
                    ) {
                        model.setColor(.init(hex: hex))
                    }
                    if hex == 0xC4DEFF { Divider() }
                }
                Divider()
                Text(L("Adjustments", "Ajustes"))
                brightnessMenu
                smoothingMenu
            }.disabled(!model.bluetooth.ready)
            Menu(modeTitle(L("Scenes", "Escenas"), selected: selectedScene)) {
                ForEach(LightScene.all) { scene in
                    MenuChoice(
                        scene.name,
                        selected: model.settings.mode == .solid && model.settings.hex == scene.hex
                            && model.settings.brightness == scene.brightness,
                        hex: scene.hex
                    ) { model.scene(scene) }
                }
                Divider()
                Text(L("Adjustments", "Ajustes"))
                brightnessMenu
                smoothingMenu
            }.disabled(!model.bluetooth.ready)
            Menu(modeTitle(L("Animation", "Animación"), selected: model.settings.mode == .animation)) {
                ForEach(AnimationStyle.allCases) { animation in
                    MenuChoice(
                        animation.title,
                        selected: model.settings.mode == .animation && model.settings.animation == animation
                    ) {
                        model.settings.animation = animation
                        model.choose(.animation)
                    }
                }
                Divider()
                Text(L("Adjustments", "Ajustes"))
                Menu(
                    L("Palette · \(model.settings.palette.title)", "Paleta · \(model.settings.palette.title)")
                ) {
                    ForEach(LightPalette.allCases) { palette in
                        MenuChoice(palette.title, selected: model.settings.palette == palette) {
                            model.settings.palette = palette
                        }
                    }
                }
                Menu(L("Animation color", "Color de animación")) {
                    ForEach(colors, id: \.0) { name, hex in
                        MenuChoice(name, selected: model.settings.hex == hex, hex: hex) {
                            model.settings.hex = hex
                            model.settings.palette = .selected
                        }
                    }
                }
                Menu(L("Speed", "Velocidad")) {
                    MenuChoice(L("Slow", "Lenta"), selected: model.settings.speed == 0.5) {
                        model.settings.speed = 0.5
                    }
                    MenuChoice("Normal", selected: model.settings.speed == 1) { model.settings.speed = 1 }
                    MenuChoice(L("Fast", "Rápida"), selected: model.settings.speed == 2) {
                        model.settings.speed = 2
                    }
                }
                brightnessMenu
            }.disabled(!model.bluetooth.ready)
            Menu(modeTitle("Ambient", selected: model.settings.mode == .ambient)) {
                ForEach(ScreenColorStyle.allCases) { style in
                    MenuChoice(
                        style.title,
                        selected: model.settings.mode == .ambient && model.settings.screenStyle == style
                    ) {
                        model.settings.screenStyle = style
                        model.choose(.ambient)
                    }
                }
                Divider()
                Text(L("Adjustments", "Ajustes"))
                displayMenu
                valuesMenu(
                    L("Color intensity", "Intensidad del color"), values: [0, 0.7, 1, 1.4, 1.8, 2.5],
                    current: model.settings.saturation, suffix: "×"
                ) { model.settings.saturation = $0 }
                smoothingMenu
                brightnessMenu
            }.disabled(!model.bluetooth.ready)
            Menu(modeTitle(L("Music", "Música"), selected: model.settings.mode == .music)) {
                ForEach(MusicStyle.allCases) { style in
                    MenuChoice(
                        style.title, selected: model.settings.mode == .music && model.settings.music == style
                    ) {
                        model.settings.music = style
                        model.choose(.music)
                    }
                }
                Divider()
                Text(L("Adjustments", "Ajustes"))
                audioMenu
                Menu(L("Pulse color", "Color para pulso")) {
                    ForEach(colors, id: \.0) { name, hex in
                        MenuChoice(name, selected: model.settings.hex == hex, hex: hex) {
                            model.settings.hex = hex
                        }
                    }
                }
                sensitivityMenu
                smoothingMenu
                brightnessMenu
                if model.isOn && model.settings.mode == .music {
                    Text(
                        model.audioReceived
                            ? (model.audioLevel > 0.005
                                ? L("Receiving audio", "Recibiendo sonido")
                                : L("Audio connected · silence", "Audio conectado · silencio"))
                            : L("Waiting for audio…", "Esperando audio…"))
                }
            }.disabled(!model.bluetooth.ready)
            Menu(modeTitle(L("Game", "Juego"), selected: model.settings.mode == .game)) {
                ForEach(GameTheme.allCases) { theme in
                    MenuChoice(
                        theme.title,
                        selected: model.settings.mode == .game && model.settings.gameTheme == theme
                    ) {
                        model.settings.gameTheme = theme
                        model.choose(.game)
                    }
                }
                Divider()
                Text(L("Adjustments", "Ajustes"))
                displayMenu
                audioMenu
                sensitivityMenu
                smoothingMenu
                brightnessMenu
                Text(L("Reacts to screen and audio", "Reacciona a pantalla y sonido"))
            }.disabled(!model.bluetooth.ready)
            Divider()
            Menu(L("Turn off after…", "Apagar en…")) {
                ForEach([15, 30, 60, 120], id: \.self) { minutes in
                    Button(L("\(minutes) minutes", "\(minutes) minutos")) {
                        model.setSleepTimer(minutes: minutes)
                    }
                }
                if let deadline = model.sleepDeadline {
                    Divider()
                    Text(
                        L(
                            "Turn off at: \(deadline.formatted(date: .omitted,time: .shortened))",
                            "Apagado: \(deadline.formatted(date: .omitted,time: .shortened))"))
                    Button(L("Cancel timer", "Cancelar temporizador")) { model.cancelSleepTimer() }
                }
            }
            if model.capture.starting { Text(L("Starting capture…", "Preparando captura…")) }
            if !model.message.isEmpty
                && ![
                    "Color", L("Animation", "Animación"), "Ambient", L("Music", "Música"), L("Game", "Juego"),
                ].contains(model.message)
            {
                Text(model.message)
            }
            if model.capture.needsPermission {
                Button(L("Open capture permissions…", "Abrir permisos de captura…")) {
                    NSWorkspace.shared.open(
                        URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                        )!)
                }
            }
            Menu(L("Notifications", "Notificaciones")) {
                Toggle(
                    L("Light up for notifications", "Avisar con luces"),
                    isOn: Binding(
                        get: { model.notifications.enabled }, set: { model.notifications.setEnabled($0) }))
                Text(model.notifications.status)
                Button(L("Test RGB flash", "Probar parpadeo RGB")) { model.flashNotification() }.disabled(
                    !model.bluetooth.ready)
                if model.notifications.enabled && !model.notifications.authorized {
                    Button(L("Allow in Accessibility…", "Permitir en Accesibilidad…")) {
                        model.notifications.openPermission()
                    }
                }
                Divider()
                Text(
                    L(
                        "Red → green → blue · restores previous mode",
                        "Rojo → verde → azul · vuelve al modo anterior"))
                Text(
                    L(
                        "Detects visible notifications · experimental",
                        "Detecta avisos visibles · experimental"))
            }
            Menu(L("Settings", "Ajustes")) {
                connectionMenu
                Divider()
                Button(L("Check Screen Recording permission", "Comprobar permiso de Grabación de pantalla")) {
                    model.requestScreenCapturePermission()
                }
                if !model.capture.status.isEmpty { Text(model.capture.status) }
                if model.capture.needsPermission {
                    Button(L("Open capture permissions…", "Abrir permisos de captura…")) {
                        NSWorkspace.shared.open(
                            URL(
                                string:
                                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                            )!)
                    }
                }
                Divider()
                Toggle(
                    L("Launch at login", "Abrir al iniciar sesión"),
                    isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                if !model.loginMessage.isEmpty { Text(model.loginMessage) }
                Toggle(
                    L("Dim lights at night", "Reducir brillo de noche"), isOn: $model.settings.nightDimming)
                scheduleMenu
            }
            Divider()
            Button(L("Check for Updates…", "Buscar actualizaciones…")) { model.updater.checkForUpdates() }
            Button(L("Help & website", "Ayuda y sitio web")) {
                NSWorkspace.shared.open(URL(string: "https://gitlares.github.io/fs-desktop-leds/")!)
            }
            Button(L("♥ Support the project", "♥ Apoyar el proyecto")) {
                NSWorkspace.shared.open(
                    URL(string: "https://www.paypal.com/donate/?hosted_button_id=7RDCBR3QXXEMJ")!)
            }
            Divider()
            Text("Desktop LEDs · 0.1.0-beta.1")
            Button(L("Quit Desktop LEDs", "Salir de Desktop LEDs")) { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
    private var selectedScene: Bool {
        model.settings.mode == .solid
            && LightScene.all.contains {
                $0.hex == model.settings.hex && $0.brightness == model.settings.brightness
            }
    }
    private func modeTitle(_ title: String, selected: Bool) -> String {
        model.isOn && selected ? "\(title)  ✓" : title
    }
    private var connectionMenu: some View {
        Menu(L("Lights", "Luces")) {
            Text(model.bluetooth.status)
            if model.bluetooth.ready {
                Text(model.bluetooth.selectedName ?? L("Connected", "Conectado"))
                Button(L("Disconnect", "Desconectar")) {
                    model.pauseForDiagnostics()
                    model.bluetooth.disconnect()
                }
            } else if model.bluetooth.scanning || model.bluetooth.connecting {
                Button(L("Cancel search", "Cancelar búsqueda")) { model.bluetooth.disconnect() }
            } else {
                Button(L("Search for lights", "Buscar luces")) { model.bluetooth.search() }
            }
            ForEach(model.bluetooth.devices) { device in
                if device.isSupported {
                    Button(deviceLabel(device)) { model.bluetooth.connect(id: device.id) }
                        .disabled(model.bluetooth.ready || model.bluetooth.connecting)
                } else {
                    Button(
                        L("Inspect \(deviceLabel(device))", "Inspeccionar \(deviceLabel(device))"),
                        systemImage: "magnifyingglass") { model.bluetooth.inspect(id: device.id) }
                        .disabled(model.bluetooth.ready || model.bluetooth.connecting)
                }
            }
            Divider()
            Menu(L("Protocol", "Protocolo")) {
                MenuChoice(L("Standard", "Estándar"), selected: model.bluetooth.profile == .standard) {
                    model.bluetooth.profile = .standard
                }
                MenuChoice(L("Alternate", "Alternativo"), selected: model.bluetooth.profile == .alternate) {
                    model.bluetooth.profile = .alternate
                }
            }.disabled(model.isOn)
            Button(L("Forget lights", "Olvidar luces")) {
                model.pauseForDiagnostics()
                model.bluetooth.forget()
            }
        }
    }

    private func deviceLabel(_ device: NearbyLight) -> String {
        "\(device.name) · \(device.rssi) dBm · \(device.identifierSuffix)"
    }
    private var scheduleMenu: some View {
        Menu(L("Schedules", "Horarios")) {
            ForEach($model.schedules) { $rule in
                Menu(
                    String(
                        format: "%02d:%02d · %@", rule.hour, rule.minute,
                        rule.sceneID == "off"
                            ? L("Turn off", "Apagar")
                            : LightScene.all.first(where: { $0.id == rule.sceneID })?.name
                                ?? L("Scene", "Escena"))
                ) {
                    Toggle(L("Enabled", "Activado"), isOn: $rule.enabled)
                    Button(L("Delete", "Eliminar")) { model.schedules.removeAll { $0.id == rule.id } }
                }
            }
            Menu(L("Add daily schedule", "Añadir horario diario")) {
                Menu(L("Hour", "Hora")) {
                    ForEach(0..<24, id: \.self) { hour in
                        MenuChoice(String(format: "%02d", hour), selected: scheduleHour == hour) {
                            scheduleHour = hour
                        }
                    }
                }
                Menu(L("Minute", "Minuto")) {
                    ForEach([0, 15, 30, 45], id: \.self) { minute in
                        MenuChoice(String(format: "%02d", minute), selected: scheduleMinute == minute) {
                            scheduleMinute = minute
                        }
                    }
                }
                Menu(L("Action", "Acción")) {
                    MenuChoice(L("Turn off", "Apagar"), selected: scheduleScene == "off") {
                        scheduleScene = "off"
                    }
                    ForEach(LightScene.all) { scene in
                        MenuChoice(scene.name, selected: scheduleScene == scene.id, hex: scene.hex) {
                            scheduleScene = scene.id
                        }
                    }
                }
                Divider()
                let action =
                    scheduleScene == "off"
                    ? L("Turn off", "Apagar") : LightScene.all.first { $0.id == scheduleScene }?.name ?? ""
                Button(
                    String(
                        format: L("Add %02d:%02d · %@", "Añadir %02d:%02d · %@"), scheduleHour,
                        scheduleMinute, action)
                ) {
                    addSchedule(scheduleHour, scheduleMinute, scheduleScene)
                }
            }
        }
    }
    private func addSchedule(_ hour: Int, _ minute: Int, _ scene: String) {
        model.schedules.append(.init(hour: hour, minute: minute, sceneID: scene))
    }
    private var brightnessMenu: some View {
        Menu(
            L(
                "Brightness · \(Int(model.settings.brightness)) %",
                "Brillo · \(Int(model.settings.brightness)) %")
        ) {
            ForEach([10, 25, 50, 75, 100], id: \.self) { value in
                MenuChoice("\(value) %", selected: Int(model.settings.brightness) == value) {
                    model.settings.brightness = Double(value)
                }
            }
            Divider()
            Toggle(
                L("Night brightness limit: 25%", "Límite nocturno al 25 %"),
                isOn: $model.settings.nightDimming)
        }
    }
    private var smoothingMenu: some View {
        Menu(L("Smoothing", "Suavidad")) {
            MenuChoice(L("Fast", "Rápida"), selected: model.settings.smoothing == 0) {
                model.settings.smoothing = 0
            }
            MenuChoice(L("Balanced", "Equilibrada"), selected: model.settings.smoothing == 0.45) {
                model.settings.smoothing = 0.45
            }
            MenuChoice(L("Smooth", "Suave"), selected: model.settings.smoothing == 1) {
                model.settings.smoothing = 1
            }
        }
    }
    private var displayMenu: some View {
        Menu(L("Display", "Monitor")) {
            MenuChoice(L("Main display", "Principal"), selected: model.settings.displayID == 0) {
                model.settings.displayID = 0
            }
            ForEach(model.capture.displays) { display in
                MenuChoice(display.name, selected: model.settings.displayID == display.id) {
                    model.settings.displayID = display.id
                }
            }
        }
    }
    private var audioMenu: some View {
        Menu(
            L("Source · \(model.settings.audioSource.title)", "Fuente · \(model.settings.audioSource.title)")
        ) {
            ForEach(AudioSource.allCases) { source in
                MenuChoice(source.title, selected: model.settings.audioSource == source) {
                    model.settings.audioSource = source
                }
            }
        }
    }
    private var sensitivityMenu: some View {
        Menu(L("Sensitivity", "Sensibilidad")) {
            MenuChoice(L("Low", "Baja"), selected: model.settings.sensitivity == 0.5) {
                model.settings.sensitivity = 0.5
            }
            MenuChoice("Normal", selected: model.settings.sensitivity == 1.2) {
                model.settings.sensitivity = 1.2
            }
            MenuChoice(L("High", "Alta"), selected: model.settings.sensitivity == 3) {
                model.settings.sensitivity = 3
            }
        }
    }
    private func valuesMenu(
        _ title: String, values: [Double], current: Double, suffix: String, set: @escaping (Double) -> Void
    ) -> some View {
        Menu(title) {
            ForEach(values, id: \.self) { value in
                MenuChoice(String(format: "%g%@", value, suffix), selected: current == value) { set(value) }
            }
        }
    }
}

@MainActor
final class LEDApplicationDelegate: NSObject, NSApplicationDelegate {
    static var controller: LightingController?
    private var terminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        guard let controller = Self.controller else { return .terminateNow }
        terminating = true
        Task {
            await controller.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
