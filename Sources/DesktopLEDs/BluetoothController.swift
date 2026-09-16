import AppKit
import Combine
import CoreBluetooth
import LEDProtocol

struct NearbyLight: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let driverName: String?

    var isSupported: Bool { driverName != nil }
}

/// CoreBluetooth delegates and all state mutations use the main queue.
final class BluetoothController: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published private(set) var devices: [NearbyLight] = []
    @Published private(set) var status = L(
        "Search for lights to get started.", "Busca las luces para empezar.")
    @Published private(set) var scanning = false
    @Published private(set) var connecting = false
    @Published private(set) var ready = false
    @Published private(set) var bluetoothAvailable = false
    @Published private(set) var selectedName: String?
    @Published private(set) var lastCommand = L(
        "No commands sent on this connection.", "Sin comandos enviados en esta conexión.")
    @Published private(set) var diagnosticLog: [String] = []
    @Published private(set) var probing = false
    @Published private(set) var lastProbedEffect: LEDEffect?
    @Published private(set) var lastProbeKey: String?
    @Published private(set) var lastProbeTitle = ""
    @Published private(set) var probeStage = L("No active test.", "Sin prueba activa.")
    @Published private(set) var observations: [String: String] = [:]
    private var probeTask: Task<Void, Never>?
    var diagnosticEffects: [LEDEffect] { driver?.diagnosticEffects ?? [] }
    private var diagnosticURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Desktop LEDs/diagnostics.txt")
    }
    private func record(_ message: String) {
        diagnosticLog.append(message)
        diagnosticLog = Array(diagnosticLog.suffix(150))
        try? FileManager.default.createDirectory(
            at: diagnosticURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? diagnosticLog.joined(separator: "\n").write(to: diagnosticURL, atomically: true, encoding: .utf8)
    }
    func observe(_ result: String) {
        guard let id = peripheral?.identifier, let key = lastProbeKey else { return }
        stopProbe()
        observations[key] = result
        UserDefaults.standard.set(observations, forKey: "observations.\(id)")
        record(
            L(
                "User observation: \(lastProbeTitle): \(result)",
                "Observación del usuario: \(lastProbeTitle): \(result)"))
    }
    func probe(_ effect: LEDEffect) {
        guard diagnosticEffects.contains(effect) else { return }
        runProbe(
            key: String(effect.rawValue), title: effect.title,
            commands: [.power(true), .brightness(35), .effectSpeed(30), .effect(effect)])
        lastProbedEffect = effect
    }
    func probeColor(_ title: String, red: UInt8, green: UInt8, blue: UInt8, brightness: Int = 35) {
        runProbe(
            key: "manual.\(title)", title: title,
            commands: [.power(true), .color(red, green, blue), .brightness(brightness)])
    }
    func probeAlternation() {
        runProbe(
            key: "manual.Alternancia RGB",
            title: L("RGB alternation · entire strip", "Alternancia RGB · toda la tira"),
            commands: [.power(true), .brightness(35)],
            cycle: [.color(255, 0, 0), .color(0, 255, 0), .color(0, 0, 255)])
    }
    private func runProbe(key: String, title: String, commands: [LEDCommand], cycle: [LEDCommand] = []) {
        guard ready, !probing else { return }
        probing = true
        lastProbeKey = "\(profile.rawValue).\(key)"
        lastProbeTitle = title
        probeStage = L(
            "\(title): watch the lights. Record your result now or when the test ends.",
            "\(title): observa las luces. Puedes registrar el resultado ahora o al terminar.")
        buffer.clear()
        record(
            L(
                "Test \(title), variant \(profile.rawValue); visual result pending.",
                "Prueba \(title), variante \(profile.rawValue); resultado visual pendiente."))
        probeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for command in commands {
                guard !Task.isCancelled, self.ready else { return }
                self.send(command)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            for seconds in (1...20).reversed() {
                guard !Task.isCancelled, self.ready else { return }
                if !cycle.isEmpty { self.send(cycle[(20 - seconds) % cycle.count]) }
                self.probeStage = L("\(title) · \(seconds) s remaining", "\(title) · \(seconds) s restantes")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            self.stopProbe()
        }
    }
    func stopProbe() {
        let wasProbing = probing
        probeTask?.cancel()
        probeTask = nil
        probing = false
        if wasProbing {
            buffer.clear()
            send(.color(255, 140, 50))
            send(.brightness(35))
            probeStage = L(
                "Test complete. Warm light at 35% requested. Record what you saw.",
                "Prueba terminada. Se solicitó luz cálida al 35 %. Registra lo observado.")
            record(probeStage)
        }
    }
    @Published var profile: ELKBLEDOMVariant = .standard {
        didSet {
            stopProbe()
            lastProbedEffect = nil
            lastProbeKey = nil
            buffer.clear()
            // A profile change must take effect immediately; reconnecting just
            // to try another documented packet layout is unnecessary.
            if driver is ELKBLEDOMDriver {
                driver = ELKBLEDOMDriver(variant: profile)
                lastCommand = L(
                    "Protocol updated. Send a color to test it.",
                    "Protocolo actualizado. Envía un color para probarlo.")
            }
            if let id = peripheral?.identifier {
                UserDefaults.standard.set(profile.rawValue, forKey: "profile.\(id)")
            }
        }
    }

    private var central: CBCentralManager?
    private var discovered: [UUID: CBPeripheral] = [:]
    private var discoveredDrivers: [UUID: any LightDriver] = [:]
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var timeout: DispatchWorkItem?
    private var retry: DispatchWorkItem?
    private var sendWork: DispatchWorkItem?
    private var writeTimeout: DispatchWorkItem?
    private var buffer = CommandBuffer()
    private var awaitingResponse = false
    private var lastWrite = Date.distantPast
    private var autoTarget: UUID?
    private var retryCount = 0
    private var wantsConnection = false
    private var pendingSearch = false
    private var driver: (any LightDriver)?
    private var savedID: UUID? {
        UserDefaults.standard.string(forKey: "selectedLight").flatMap(UUID.init(uuidString:))
    }

    override init() {
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func restoreIfKnown() {
        guard central == nil, let id = savedID else { return }
        autoTarget = id
        wantsConnection = true
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func search() {
        guard !ready, !connecting else { return }
        retry?.cancel()
        retryCount = 0
        autoTarget = nil
        wantsConnection = false
        pendingSearch = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central?.state == .poweredOn {
            beginScan()
        } else {
            status = L(
                "Turn on Bluetooth and allow access in System Settings → Privacy & Security → Bluetooth.",
                "Activa Bluetooth y permite su uso en Ajustes del Sistema → Privacidad y seguridad → Bluetooth."
            )
        }
    }

    private func beginScan() {
        guard let central, central.state == .poweredOn else { return }
        pendingSearch = false
        timeout?.cancel()
        devices = []
        discovered = [:]
        discoveredDrivers = [:]
        scanning = true
        status = L("Searching for ELK-BLEDOM for 10 seconds…", "Buscando ELK-BLEDOM durante 10 segundos…")
        // Many controllers do not advertise their service UUID, so filter names locally.
        central.scanForPeripherals(
            withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        setTimeout(after: 10) { [weak self] in
            guard let self else { return }
            self.stopScan()
            self.status =
                self.devices.isEmpty
                ? L(
                    "No lights found. Close duoCo Strip on your iPhone and search again.",
                    "No se encontraron luces. Cierra duoCo Strip en el iPhone y vuelve a buscar.")
                : L("Select your lights to connect.", "Selecciona tus luces para conectar.")
            self.scheduleRetry()
        }
    }

    func stopScan() {
        central?.stopScan()
        scanning = false
        timeout?.cancel()
    }

    func connect(id: UUID) {
        guard let device = discovered[id], discoveredDrivers[id] != nil, !connecting, !ready else {
            status = L(
                "This device does not have a compatible driver yet.",
                "Ese dispositivo aún no tiene un driver compatible.")
            return
        }
        retryCount = 0
        wantsConnection = true
        autoTarget = id
        connect(device)
    }

    private func connect(_ device: CBPeripheral) {
        stopScan()
        retry?.cancel()
        peripheral = device
        lastProbedEffect = nil
        lastProbeKey = nil
        diagnosticLog = []
        observations =
            UserDefaults.standard.dictionary(forKey: "observations.\(device.identifier)") as? [String: String]
            ?? [:]
        record(
            L(
                "Device: \(device.name ?? L("unnamed", "sin nombre")) · \(device.identifier)",
                "Dispositivo: \(device.name ?? L("unnamed", "sin nombre")) · \(device.identifier)"))
        device.delegate = self
        characteristic = nil
        selectedName = device.name ?? "ELK-BLEDOM"
        profile =
            ELKBLEDOMVariant(
                rawValue: UserDefaults.standard.string(forKey: "profile.\(device.identifier)") ?? "")
            ?? .standard
        guard
            let detectedDriver = discoveredDrivers[device.identifier]
                ?? DriverCatalog.shared.driver(forAdvertisedName: device.name ?? "")
        else {
            status = L(
                "No compatible driver found for this device.",
                "No se identificó un driver compatible para este dispositivo.")
            return
        }
        driver =
            detectedDriver.id.hasPrefix("elk-bledom")
            ? ELKBLEDOMDriver(variant: profile)
            : detectedDriver
        connecting = true
        status = L(
            "Connecting to \(selectedName ?? L("the lights", "las luces"))…",
            "Conectando con \(selectedName ?? L("the lights", "las luces"))…")
        central?.connect(device)
        setTimeout(after: 15) { [weak self] in
            self?.fail(
                L(
                    "Connection timed out. Close duoCo Strip and check that the lights are powered on.",
                    "La conexión tardó demasiado. Cierra duoCo Strip y verifica que las luces estén encendidas."
                ))
        }
    }

    func disconnect() {
        wantsConnection = false
        autoTarget = nil
        retry?.cancel()
        stopScan()
        clearConnection()
        status = L(
            "Disconnected. You can use duoCo Strip again.", "Desconectado. Puedes volver a usar duoCo Strip.")
    }

    func forget() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: "selectedLight")
        selectedName = nil
        status = L(
            "Device forgotten. Search to select lights.",
            "Dispositivo olvidado. Busca para elegir unas luces.")
    }

    private func clearConnection() {
        probeTask?.cancel()
        probeTask = nil
        probing = false
        probeStage = L(
            "Test cancelled when the connection closed.", "Prueba cancelada al cerrar la conexión.")
        timeout?.cancel()
        sendWork?.cancel()
        sendWork = nil
        writeTimeout?.cancel()
        buffer.clear()
        awaitingResponse = false
        ready = false
        connecting = false
        characteristic = nil
        driver = nil
        let old = peripheral
        peripheral = nil
        if let old { central?.cancelPeripheralConnection(old) }
        lastCommand = L("No commands sent on this connection.", "Sin comandos enviados en esta conexión.")
    }

    private func fail(_ message: String, retryable: Bool = true) {
        clearConnection()
        status = message
        if retryable { scheduleRetry() } else { wantsConnection = false }
    }

    private func scheduleRetry() {
        guard wantsConnection, autoTarget != nil, retryCount < 3, central?.state == .poweredOn else { return }
        let delay = [2.0, 5.0, 10.0][retryCount]
        retryCount += 1
        status += L(
            " Retry \(retryCount)/3 in \(Int(delay)) s.", " Reintento \(retryCount)/3 en \(Int(delay)) s.")
        retry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.restoreConnection() }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func restoreConnection() {
        guard wantsConnection, let target = autoTarget, central?.state == .poweredOn else { return }
        if let device = central?.retrievePeripherals(withIdentifiers: [target]).first {
            connect(device)
        } else {
            beginScan()
        }
    }

    private func setTimeout(after seconds: Double, action: @escaping () -> Void) {
        timeout?.cancel()
        let work = DispatchWorkItem(block: action)
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// Keep CoreBluetooth alive until the final command leaves the queue. A write
    /// without response has no device acknowledgement, so allow a short grace period.
    func finishPendingWrites() async {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while ready && (!buffer.isEmpty || sendWork != nil || awaitingResponse) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if ready { try? await Task.sleep(nanoseconds: 300_000_000) }
    }

    func discardPendingCommands() {
        sendWork?.cancel()
        sendWork = nil
        buffer.clear()
    }

    func send(_ command: LEDCommand) {
        if case .power(false) = command { stopProbe() }
        guard ready else { return }
        buffer.append(command)
        scheduleSend()
    }

    private func scheduleSend() {
        guard ready, !buffer.isEmpty, sendWork == nil, !awaitingResponse else { return }
        // Ambient mode can use this cadence for a continuous fade. Commands
        // are still coalesced, so a slow controller never accumulates a queue.
        let delay = max(0, 0.06 - Date().timeIntervalSince(lastWrite))
        let work = DispatchWorkItem { [weak self] in
            self?.sendWork = nil
            self?.flush()
        }
        sendWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func flush() {
        guard ready, let peripheral, let characteristic, let driver else { return }
        let type: CBCharacteristicWriteType =
            characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        if type == .withoutResponse && !peripheral.canSendWriteWithoutResponse { return }
        guard let command = buffer.pop() else { return }
        lastWrite = Date()
        let packet = driver.packet(for: command)
        peripheral.writeValue(packet, for: characteristic, type: type)
        if probing {
            record(
                "TX \(packet.map { String(format: "%02X", $0) }.joined(separator: " ")) · \(type == .withoutResponse ? L("without ATT acknowledgment", "sin confirmación ATT") : L("waiting for ATT acknowledgment", "esperando confirmación ATT"))"
            )
        }
        lastCommand = L(
            "Command sent; check the change on your lights.",
            "Comando enviado; confirma el cambio en las luces.")
        if type == .withResponse {
            awaitingResponse = true
            let work = DispatchWorkItem { [weak self] in
                self?.fail(
                    L(
                        "The lights did not acknowledge the Bluetooth write.",
                        "Las luces no confirmaron la escritura Bluetooth."))
            }
            writeTimeout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
        } else {
            scheduleSend()
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothAvailable = central.state == .poweredOn
        if bluetoothAvailable {
            if wantsConnection {
                restoreConnection()
            } else if pendingSearch {
                beginScan()
            } else {
                status = L(
                    "Bluetooth available. Search for your lights.", "Bluetooth disponible. Busca tus luces.")
            }
            return
        }
        retry?.cancel()
        stopScan()
        clearConnection()
        switch central.state {
        case .unauthorized:
            status = L(
                "Allow Bluetooth in System Settings → Privacy & Security → Bluetooth.",
                "Permite Bluetooth en Ajustes del Sistema → Privacidad y seguridad → Bluetooth.")
        case .poweredOff:
            status = L(
                "Bluetooth is off. Turn it on in System Settings.",
                "Bluetooth está apagado. Actívalo en Ajustes del Sistema.")
        case .unsupported:
            status = L(
                "This Mac does not support the required Bluetooth features.",
                "Este Mac no ofrece Bluetooth compatible.")
        default: status = L("Waiting for Bluetooth…", "Esperando a Bluetooth…")
        }
    }

    func centralManager(
        _ central: CBCentralManager, didDiscover device: CBPeripheral, advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard scanning else { return }
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        let peripheralName = device.name ?? ""
        let driver =
            DriverCatalog.shared.driver(forAdvertisedName: advertisedName)
            ?? DriverCatalog.shared.driver(forAdvertisedName: peripheralName)
        let name = peripheralName.isEmpty ? advertisedName : peripheralName
        discovered[device.identifier] = device
        discoveredDrivers[device.identifier] = driver
        let light = NearbyLight(
            id: device.identifier, name: name.isEmpty ? L("Unnamed", "Sin nombre") : name,
            rssi: RSSI.intValue, driverName: driver?.displayName)
        if let index = devices.firstIndex(where: { $0.id == light.id }) {
            devices[index] = light
        } else {
            devices.append(light)
        }
        if wantsConnection, driver != nil, device.identifier == autoTarget { connect(device) }
    }

    func centralManager(_ central: CBCentralManager, didConnect device: CBPeripheral) {
        guard device === peripheral else { return }
        status = L("Checking the lighting service…", "Comprobando el servicio de las luces…")
        device.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect device: CBPeripheral, error: Error?) {
        guard device === peripheral else { return }
        fail(
            L(
                "Could not connect: \(error?.localizedDescription ?? L("device unavailable", "dispositivo no disponible")).",
                "No se pudo conectar: \(error?.localizedDescription ?? L("device unavailable", "dispositivo no disponible"))."
            ))
    }

    func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral device: CBPeripheral, error: Error?
    ) {
        guard device === peripheral else { return }
        fail(L("Connection to the lights was lost.", "Se perdió la conexión con las luces."))
    }

    func peripheral(_ device: CBPeripheral, didDiscoverServices error: Error?) {
        guard device === peripheral else { return }
        guard error == nil, let services = device.services, !services.isEmpty else {
            fail(L("Could not read Bluetooth services.", "No se pudieron leer los servicios Bluetooth."))
            return
        }
        for service in services {
            record(L("Service \(service.uuid.uuidString)", "Servicio \(service.uuid.uuidString)"))
            device.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ device: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard device === peripheral else { return }
        if let error {
            record(
                L(
                    "Discovery error: \(error.localizedDescription)",
                    "Error de descubrimiento: \(error.localizedDescription)"))
            return
        }
        for item in service.characteristics ?? [] {
            record(
                L(
                    "  Characteristic \(item.uuid.uuidString), properties 0x\(String(item.properties.rawValue, radix: 16))",
                    "  Característica \(item.uuid.uuidString), propiedades 0x\(String(item.properties.rawValue, radix: 16))"
                ))
            // Standard Device Information only. No arbitrary vendor reads or writes.
            if service.uuid == CBUUID(string: "180A"), item.properties.contains(.read) {
                device.readValue(for: item)
            }
            if item.uuid == CBUUID(string: "FFF4"), item.properties.contains(.notify) {
                device.setNotifyValue(true, for: item)
            }
        }
        guard !ready else { return }
        if let driver,
            let found = service.characteristics?.first(where: {
                $0.uuid == CBUUID(nsuuid: driver.writeCharacteristicUUID)
                    && (!$0.properties.intersection([.write, .writeWithoutResponse]).isEmpty)
            })
        {
            characteristic = found
            timeout?.cancel()
            connecting = false
            ready = true
            retryCount = 0
            UserDefaults.standard.set(device.identifier.uuidString, forKey: "selectedLight")
            status = L(
                "Connected. Ready to control your lights.", "Conectado. Listo para controlar las luces.")
        } else if device.services?.allSatisfy({ $0.characteristics != nil }) == true {
            fail(
                L(
                    "This device does not provide the expected ELK-BLEDOM channel (FFF3).",
                    "Este dispositivo no ofrece el canal ELK-BLEDOM esperado (FFF3)."), retryable: false)
        }
    }

    func peripheral(_ device: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    {
        guard device === peripheral else { return }
        if let error {
            record(L("Read: \(error.localizedDescription)", "Lectura: \(error.localizedDescription)"))
            return
        }
        let value = characteristic.value ?? Data()
        let hex = value.prefix(64).map { String(format: "%02X", $0) }.joined(separator: " ")
        record("RX \(characteristic.uuid.uuidString): \(hex)")
        if characteristic.service?.uuid == CBUUID(string: "180A"),
            let text = String(data: value, encoding: .utf8)
        {
            record(L("Device information: \(text)", "Información de dispositivo: \(text)"))
        }
    }

    func peripheral(
        _ device: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?
    ) {
        guard device === peripheral else { return }
        record(
            L(
                "Notifications \(characteristic.uuid.uuidString): \(error?.localizedDescription ?? (characteristic.isNotifying ? L("enabled", "activas") : L("disabled", "inactivas")))",
                "Notificaciones \(characteristic.uuid.uuidString): \(error?.localizedDescription ?? (characteristic.isNotifying ? L("enabled", "activas") : L("disabled", "inactivas")))"
            ))
    }

    func peripheralIsReady(toSendWriteWithoutResponse device: CBPeripheral) {
        guard device === peripheral else { return }
        scheduleSend()
    }

    func peripheral(_ device: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?)
    {
        guard device === peripheral else { return }
        writeTimeout?.cancel()
        awaitingResponse = false
        if let error {
            fail(
                L(
                    "Send error: \(error.localizedDescription)",
                    "Error al enviar: \(error.localizedDescription)"))
            return
        }
        scheduleSend()
    }

    @objc private func willSleep() {
        retry?.cancel()
        stopScan()
        clearConnection()
        status = L("Connection paused while the Mac sleeps.", "Conexión pausada mientras el Mac duerme.")
    }

    @objc private func didWake() {
        retryCount = 0
        restoreConnection()
    }
}
