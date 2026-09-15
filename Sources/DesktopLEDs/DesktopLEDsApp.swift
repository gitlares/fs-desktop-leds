import SwiftUI
import AppKit
import LEDProtocol

@main
struct DesktopLEDsApp: App {
    @StateObject private var bluetooth = BluetoothController()
    @StateObject private var ambient = AmbientLightingController()

    var body: some Scene {
        Window("Desktop LEDs", id: "controls") {
            ControlView(controller: bluetooth, ambient: ambient)
                .onAppear {
                    bluetooth.restoreIfKnown()
                    ambient.setCommandSink { [weak bluetooth] command in bluetooth?.send(command) }
                }
        }
        .windowResizability(.contentSize)
        MenuBarExtra("Desktop LEDs", systemImage: "lightbulb.led.fill") {
            Text(bluetooth.status)
            Button("Encender") { bluetooth.send(.power(true)) }.disabled(!bluetooth.ready)
            Button("Apagar") { bluetooth.send(.power(false)) }.disabled(!bluetooth.ready)
            Divider()
            OpenControlsButton()
            Button("Salir") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

private struct OpenControlsButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Mostrar controles") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "controls")
        }
    }
}

struct ControlView: View {
    @ObservedObject var controller: BluetoothController
    @ObservedObject var ambient: AmbientLightingController
    @State private var color = Color(red: 1, green: 0.55, blue: 0.2)
    @State private var brightness = 50.0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "lightbulb.led.fill")
                    .font(.system(size: 32)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Desktop LEDs").font(.title2.bold())
                    Text("La luz de tu escritorio, desde tu Mac.").foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(controller.ready ? Color.green : Color.secondary.opacity(0.4)).frame(width: 9, height: 9)
                    .accessibilityLabel(controller.ready ? "Conectado" : "Desconectado")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(controller.status).font(.callout).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if controller.scanning || controller.connecting {
                            ProgressView().controlSize(.small)
                            Button("Cancelar") { controller.disconnect() }
                        } else if controller.ready {
                            Label(controller.selectedName ?? "ELK-BLEDOM", systemImage: "wave.3.right")
                            Spacer()
                            Button("Desconectar") { controller.disconnect() }
                        } else {
                            Button("Buscar luces", systemImage: "magnifyingglass") { controller.search() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    if !controller.ready && !controller.connecting {
                        ForEach(controller.devices) { device in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(device.name).bold()
                                    Text(device.isSupported
                                        ? "Compatible con \(device.driverName ?? "un driver") · \(device.rssi) dBm"
                                        : "Detectado, sin driver · \(device.rssi) dBm")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Conectar") { controller.connect(id: device.id) }
                                    .disabled(!device.isSupported)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }

            GroupBox("Control de luz") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button("Encender", systemImage: "power") { controller.send(.power(true)) }
                        Button("Apagar") { controller.send(.power(false)) }
                        Spacer()
                        ColorPicker("Color", selection: $color, supportsOpacity: false)
                            .onChange(of: color) { _, value in sendColor(value) }
                    }
                    HStack(spacing: 12) {
                        preset("Rojo", .red)
                        preset("Verde", .green)
                        preset("Azul", .blue)
                        preset("Cálido", Color(red: 1, green: 0.55, blue: 0.2))
                        preset("Blanco", .white)
                    }
                    HStack {
                        Text("Brillo")
                        Slider(value: $brightness, in: 0...100, step: 1) { editing in
                            if !editing { controller.send(.brightness(Int(brightness))) }
                        }.accessibilityLabel("Brillo")
                        Text("\(Int(brightness)) %").monospacedDigit().frame(width: 45)
                    }
                    Text("Valores elegidos en la app; el estado real de las luces no se lee.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(controller.lastCommand).font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }.disabled(!controller.ready)

            GroupBox("Ambient") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Sincronizar con todas las pantallas", isOn: Binding(
                        get: { ambient.isActive },
                        set: { $0 ? ambient.start() : ambient.stop() }
                    ))
                    Text(ambient.status).font(.caption).foregroundStyle(.secondary)
                    if ambient.isActive {
                        Text("Muestra cada monitor como una miniatura de 64 px de ancho y combina sus colores según su área.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let color = ambient.lastSample {
                            Text("Muestras: \(ambient.sampleCount) · enviados: \(ambient.sentCount) · RGB(\(color.red), \(color.green), \(color.blue))")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        } else {
                            Text("Esperando las primeras muestras de pantalla…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding(8)
            }.disabled(!controller.ready)

            DisclosureGroup("Compatibilidad y conexión") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No necesitas emparejar desde Ajustes. Cierra duoCo Strip en el iPhone para liberar las luces. Se recuerda el dispositivo al conectar.")
                    Picker("Protocolo", selection: $controller.profile) {
                        Text("ELK-BLEDOM estándar").tag(ELKBLEDOMVariant.standard)
                        Text("ELK-BLEDOM alternativo").tag(ELKBLEDOMVariant.alternate)
                    }.disabled(!controller.ready)
                    Text("Si conecta pero no cambia de color, prueba el alternativo y pulsa un color de nuevo.")
                        .foregroundStyle(.secondary)
                    Button("Olvidar dispositivo") { controller.forget() }
                }.font(.callout).padding(.top, 8)
            }
            Text("MVP · Control manual por Bluetooth").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 510)
        .onChange(of: controller.ready) { _, connected in
            if !connected { ambient.stop() }
        }
    }

    private func preset(_ label: String, _ value: Color) -> some View {
        Button {
            color = value
            sendColor(value)
        } label: {
            Circle().fill(value).frame(width: 24, height: 24)
                .overlay(Circle().stroke(.primary.opacity(0.15), lineWidth: 1))
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    private func sendColor(_ value: Color) {
        guard let rgb = NSColor(value).usingColorSpace(.sRGB) else { return }
        func byte(_ component: CGFloat) -> UInt8 { UInt8((min(1, max(0, component)) * 255).rounded()) }
        controller.send(.color(byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent)))
    }
}
