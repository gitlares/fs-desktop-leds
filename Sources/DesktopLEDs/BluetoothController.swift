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
    @Published private(set) var status = "Busca las luces para empezar."
    @Published private(set) var scanning = false
    @Published private(set) var connecting = false
    @Published private(set) var ready = false
    @Published private(set) var bluetoothAvailable = false
    @Published private(set) var selectedName: String?
    @Published private(set) var lastCommand = "Sin comandos enviados en esta conexión."
    @Published var profile: ELKBLEDOMVariant = .standard {
        didSet {
            buffer.clear()
            // A profile change must take effect immediately; reconnecting just
            // to try another documented packet layout is unnecessary.
            if driver is ELKBLEDOMDriver {
                driver = ELKBLEDOMDriver(variant: profile)
                lastCommand = "Protocolo actualizado. Envía un color para probarlo."
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
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
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
            status = "Activa Bluetooth y permite su uso en Ajustes del Sistema → Privacidad y seguridad → Bluetooth."
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
        status = "Buscando ELK-BLEDOM durante 10 segundos…"
        // Many controllers do not advertise their service UUID, so filter names locally.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        setTimeout(after: 10) { [weak self] in
            guard let self else { return }
            self.stopScan()
            self.status = self.devices.isEmpty
                ? "No se encontraron luces. Cierra duoCo Strip en el iPhone y vuelve a buscar."
                : "Selecciona tus luces para conectar."
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
            status = "Ese dispositivo aún no tiene un driver compatible."
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
        device.delegate = self
        characteristic = nil
        selectedName = device.name ?? "ELK-BLEDOM"
        profile = ELKBLEDOMVariant(rawValue: UserDefaults.standard.string(forKey: "profile.\(device.identifier)") ?? "") ?? .standard
        guard let detectedDriver = discoveredDrivers[device.identifier]
                ?? DriverCatalog.shared.driver(forAdvertisedName: device.name ?? "") else {
            status = "No se identificó un driver compatible para este dispositivo."
            return
        }
        driver = detectedDriver.id.hasPrefix("elk-bledom")
            ? ELKBLEDOMDriver(variant: profile)
            : detectedDriver
        connecting = true
        status = "Conectando con \(selectedName ?? "las luces")…"
        central?.connect(device)
        setTimeout(after: 15) { [weak self] in
            self?.fail("La conexión tardó demasiado. Cierra duoCo Strip y verifica que las luces estén encendidas.")
        }
    }

    func disconnect() {
        wantsConnection = false
        autoTarget = nil
        retry?.cancel()
        stopScan()
        clearConnection()
        status = "Desconectado. Puedes volver a usar duoCo Strip."
    }

    func forget() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: "selectedLight")
        selectedName = nil
        status = "Dispositivo olvidado. Busca para elegir unas luces."
    }

    private func clearConnection() {
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
        lastCommand = "Sin comandos enviados en esta conexión."
    }

    private func fail(_ message: String, retryable: Bool = true) {
        clearConnection()
        status = message
        if retryable { scheduleRetry() }
        else { wantsConnection = false }
    }

    private func scheduleRetry() {
        guard wantsConnection, autoTarget != nil, retryCount < 3, central?.state == .poweredOn else { return }
        let delay = [2.0, 5.0, 10.0][retryCount]
        retryCount += 1
        status += " Reintento \(retryCount)/3 en \(Int(delay)) s."
        retry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.restoreConnection() }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func restoreConnection() {
        guard wantsConnection, let target = autoTarget, central?.state == .poweredOn else { return }
        if let device = central?.retrievePeripherals(withIdentifiers: [target]).first {
            connect(device)
        } else { beginScan() }
    }

    private func setTimeout(after seconds: Double, action: @escaping () -> Void) {
        timeout?.cancel()
        let work = DispatchWorkItem(block: action)
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func send(_ command: LEDCommand) {
        guard ready else { return }
        buffer.append(command)
        scheduleSend()
    }

    private func scheduleSend() {
        guard ready, !buffer.isEmpty, sendWork == nil, !awaitingResponse else { return }
        let delay = max(0, 0.1 - Date().timeIntervalSince(lastWrite))
        let work = DispatchWorkItem { [weak self] in
            self?.sendWork = nil
            self?.flush()
        }
        sendWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func flush() {
        guard ready, let peripheral, let characteristic, let driver else { return }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        if type == .withoutResponse && !peripheral.canSendWriteWithoutResponse { return }
        guard let command = buffer.pop() else { return }
        lastWrite = Date()
        peripheral.writeValue(driver.packet(for: command), for: characteristic, type: type)
        lastCommand = "Comando enviado; confirma el cambio en las luces."
        if type == .withResponse {
            awaitingResponse = true
            let work = DispatchWorkItem { [weak self] in self?.fail("Las luces no confirmaron la escritura Bluetooth.") }
            writeTimeout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
        } else { scheduleSend() }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothAvailable = central.state == .poweredOn
        if bluetoothAvailable {
            if wantsConnection { restoreConnection() }
            else if pendingSearch { beginScan() }
            else { status = "Bluetooth disponible. Busca tus luces." }
            return
        }
        retry?.cancel()
        stopScan()
        clearConnection()
        switch central.state {
        case .unauthorized: status = "Permite Bluetooth en Ajustes del Sistema → Privacidad y seguridad → Bluetooth."
        case .poweredOff: status = "Bluetooth está apagado. Actívalo en Ajustes del Sistema."
        case .unsupported: status = "Este Mac no ofrece Bluetooth compatible."
        default: status = "Esperando a Bluetooth…"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover device: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanning else { return }
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        let peripheralName = device.name ?? ""
        let driver = DriverCatalog.shared.driver(forAdvertisedName: advertisedName)
            ?? DriverCatalog.shared.driver(forAdvertisedName: peripheralName)
        let name = peripheralName.isEmpty ? advertisedName : peripheralName
        discovered[device.identifier] = device
        discoveredDrivers[device.identifier] = driver
        let light = NearbyLight(id: device.identifier, name: name.isEmpty ? "Sin nombre" : name, rssi: RSSI.intValue, driverName: driver?.displayName)
        if let index = devices.firstIndex(where: { $0.id == light.id }) { devices[index] = light }
        else { devices.append(light) }
        if wantsConnection, driver != nil, device.identifier == autoTarget { connect(device) }
    }

    func centralManager(_ central: CBCentralManager, didConnect device: CBPeripheral) {
        guard device === peripheral else { return }
        status = "Comprobando el servicio de las luces…"
        device.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect device: CBPeripheral, error: Error?) {
        guard device === peripheral else { return }
        fail("No se pudo conectar: \(error?.localizedDescription ?? "dispositivo no disponible").")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral device: CBPeripheral, error: Error?) {
        guard device === peripheral else { return }
        fail("Se perdió la conexión con las luces.")
    }

    func peripheral(_ device: CBPeripheral, didDiscoverServices error: Error?) {
        guard device === peripheral else { return }
        guard error == nil, let services = device.services, !services.isEmpty else {
            fail("No se pudieron leer los servicios Bluetooth."); return
        }
        guard let driver else { fail("No se identificó un driver compatible.", retryable: false); return }
        for service in services {
            device.discoverCharacteristics([CBUUID(nsuuid: driver.writeCharacteristicUUID)], for: service)
        }
    }

    func peripheral(_ device: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard device === peripheral, !ready else { return }
        if let driver, let found = service.characteristics?.first(where: {
            $0.uuid == CBUUID(nsuuid: driver.writeCharacteristicUUID) && (!$0.properties.intersection([.write, .writeWithoutResponse]).isEmpty)
        }) {
            characteristic = found
            timeout?.cancel()
            connecting = false
            ready = true
            retryCount = 0
            UserDefaults.standard.set(device.identifier.uuidString, forKey: "selectedLight")
            status = "Conectado. Listo para controlar las luces."
        } else if device.services?.allSatisfy({ $0.characteristics != nil }) == true {
            fail("Este dispositivo no ofrece el canal ELK-BLEDOM esperado (FFF3).", retryable: false)
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse device: CBPeripheral) {
        guard device === peripheral else { return }
        scheduleSend()
    }

    func peripheral(_ device: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard device === peripheral else { return }
        writeTimeout?.cancel()
        awaitingResponse = false
        if let error { fail("Error al enviar: \(error.localizedDescription)"); return }
        scheduleSend()
    }

    @objc private func willSleep() {
        retry?.cancel()
        stopScan()
        clearConnection()
        status = "Conexión pausada mientras el Mac duerme."
    }

    @objc private func didWake() {
        retryCount = 0
        restoreConnection()
    }
}
