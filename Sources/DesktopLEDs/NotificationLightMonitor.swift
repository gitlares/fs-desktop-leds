import AppKit
import ApplicationServices
import Combine
import LEDProtocol

/// Best-effort detection of visible banners. Never reads titles or message bodies.
@MainActor
final class NotificationLightMonitor: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var authorized = false
    @Published private(set) var status = L("Disabled", "Desactivado")
    var onNotification: (() -> Void)?
    private var timer: Timer?
    private var previous: [AXUIElement] = []
    private var primed = false
    private var processID: pid_t?
    private var observer: AXObserver?
    private var pendingPoll: DispatchWorkItem?

    init() {
        setEnabled(UserDefaults.standard.bool(forKey: "notificationLights.enabled"), prompt: false)
    }
    func setEnabled(_ value: Bool, prompt: Bool = true) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "notificationLights.enabled")
        pendingPoll?.cancel()
        pendingPoll = nil
        timer?.invalidate()
        timer = nil
        previous = []
        primed = false
        processID = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        guard value else {
            setStatus(L("Disabled", "Desactivado"))
            return
        }
        if prompt {
            _ = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
        poll()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func openPermission() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    private func setStatus(_ value: String) { if status != value { status = value } }
    private func schedulePoll() {
        guard enabled, pendingPoll == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPoll = nil
            if self.enabled { self.poll() }
        }
        pendingPoll = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
    private func poll() {
        let trusted = AXIsProcessTrusted()
        if authorized != trusted { authorized = trusted }
        guard authorized else {
            setStatus(L("Accessibility permission required", "Necesita permiso de Accesibilidad"))
            primed = false
            previous = []
            return
        }
        guard
            let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.notificationcenterui"
            ).first
        else {
            setStatus(L("Waiting for Notification Center", "Esperando al Centro de notificaciones"))
            primed = false
            previous = []
            return
        }
        if processID != app.processIdentifier {
            processID = app.processIdentifier
            primed = false
            previous = []
            if let observer {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            observer = nil
            var next: AXObserver?
            if AXObserverCreate(
                app.processIdentifier,
                { _, _, _, context in
                    guard let context else { return }
                    let monitor = Unmanaged<NotificationLightMonitor>.fromOpaque(context)
                        .takeUnretainedValue()
                    MainActor.assumeIsolated { monitor.schedulePoll() }
                }, &next) == .success, let next
            {
                let target = AXUIElementCreateApplication(app.processIdentifier)
                AXObserverAddNotification(
                    next, target, kAXWindowCreatedNotification as CFString,
                    Unmanaged.passUnretained(self).toOpaque())
                observer = next
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(next), .commonModes)
            }
        }
        // Opening the history is not a newly delivered notification.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            previous = []
            primed = false
            return
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.03)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &raw) == .success,
            let windows = raw as? [AXUIElement]
        else {
            setStatus(L("Could not detect notifications", "No se pudieron detectar avisos"))
            return
        }
        var banners: [AXUIElement] = []
        var budget = 120
        let deadline = ProcessInfo.processInfo.systemUptime + 0.06
        var interrupted = false
        func visit(_ node: AXUIElement, _ depth: Int) {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                interrupted = true
                return
            }
            guard depth < 7, budget > 0 else { return }
            budget -= 1
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(node, kAXSubroleAttribute as CFString, &role)
            // Conservative: do not treat arbitrary Notification Center windows as alerts.
            if let role = role as? String,
                ["AXNotificationCenterAlert", "AXNotificationCenterBanner"].contains(role)
            {
                banners.append(node)
                return
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &children) == .success,
                let children = children as? [AXUIElement]
            {
                for child in children.prefix(30) { visit(child, depth + 1) }
            }
        }
        for window in windows.prefix(12) { visit(window, 0) }
        guard !interrupted else { return }
        let fresh = banners.contains { item in !previous.contains { CFEqual($0, item) } }
        previous = banners
        setStatus(L("Enabled · waiting for visible notifications", "Activado · esperando avisos visibles"))
        if primed && fresh { onNotification?() }
        primed = true
    }
}
