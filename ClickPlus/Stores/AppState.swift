import SwiftUI
import ServiceManagement
import ApplicationServices
import IOKit.hid

@MainActor final class AppState: ObservableObject {
    @Published var trackpadPreferences = TrackpadPreferences() { didSet {
        if let data = try? JSONEncoder().encode(trackpadPreferences) { UserDefaults.standard.set(data,forKey: "trackpad.v1") }
        configureTrackpad()
    } }
    @Published var trackpadStatus = "Gestos de borda desativados"
    @Published var trackpadLastAction = "Nenhum gesto nesta execução"
    let trackpad = TrackpadEdgeService.shared
    @Published var preferences: Preferences { didSet { if !preferences.enabled { preferences.enabled = true; return }; save(); configureTrackpad(); engine.configure(preferences); if trusted && inputAccess { hardware.configureButtons(preferences) } } }
    @Published var status = "Aguardando permissão de Acessibilidade"
    @Published var trusted = AXIsProcessTrusted()
    @Published var inputAccess = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    @Published var mouseDevices: [LogitechMouse] = []
    @Published var keyboardBatteries: [KeyboardBattery] = []
    @Published var device = HardwareState()
    @Published var frequency = 0
    @Published var capturingButton = false
    @Published var capturedButton: DetectedButton?
    @Published var captureHint: String?
    @Published var diagnostics = InputDiagnostics()
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var message: String?
    let engine = EventEngine()
    let hardware = HardwareService()
    let bluetooth = BluetoothBatteryService()
    let batteryAlerts = BatteryAlertService()
    private var timer: Timer?
    private var lastTrackpadAllowed = false
    init() {
        var loaded = Preferences()
        if let data = UserDefaults.standard.data(forKey: "preferences.v1"), let saved = try? JSONDecoder().decode(Preferences.self, from: data), saved.version == 1 { loaded = saved }
        // Migrate legacy paused settings without changing any feature's configuration.
        loaded.enabled = true
        preferences = loaded
        if let data = UserDefaults.standard.data(forKey: "trackpad.v1"), let saved = try? JSONDecoder().decode(TrackpadPreferences.self,from: data) { trackpadPreferences = saved }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        save()
        trackpad.onStatus = { [weak self] text in DispatchQueue.main.async { self?.trackpadStatus = text } }
        trackpad.onAction = { [weak self] text in DispatchQueue.main.async { self?.trackpadLastAction = text } }
        configureTrackpad()
        ActionService.onError = { [weak self] error in self?.message = error }
        engine.onStatus = { [weak self] text in DispatchQueue.main.async { self?.status = text } }
        engine.onFrequency = { [weak self] value in DispatchQueue.main.async { self?.frequency = value } }
        engine.onButtonCaptured = { [weak self] button in DispatchQueue.main.async {
            self?.capturingButton = false; self?.captureHint = nil
            self?.capturedButton = DetectedButton(id: button)
        } }
        engine.onCaptureEnded = { [weak self] reason in DispatchQueue.main.async {
            self?.capturingButton = false; self?.captureHint = reason
        } }
        engine.onDiagnostics = { [weak self] value in DispatchQueue.main.async { self?.diagnostics = value } }
        hardware.onMouseDevices = { [weak self] values in DispatchQueue.main.async { self?.mouseDevices = values } }
        hardware.onKeyboardBatteries = { [weak self] values in DispatchQueue.main.async { self?.keyboardBatteries = values; self?.evaluateBatteryAlerts() } }
        hardware.onChange = { [weak self] value in DispatchQueue.main.async { self?.device = value; self?.engine.setDevice(value); self?.evaluateBatteryAlerts() } }
        hardware.onPanButtonState = { [weak self] button, down in self?.engine.hardwarePanState(button,down: down) }
        hardware.onPanCancelled = { [weak self] in self?.engine.cancelHardwarePan() }
        hardware.onMappedButton = { [weak self] button in self?.engine.hardwareButtonReleased(button) }
        hardware.onCapturedButton = { [weak self] button, reason in DispatchQueue.main.async {
            self?.capturingButton = false; self?.captureHint = reason
            if let button { self?.capturedButton = DetectedButton(id: button) }
        } }
        hardware.onDisconnect = { [weak self] in self?.engine.devicesChanged() }
        if trusted { hardware.configureButtons(preferences) }
        batteryAlerts.start()
        bluetooth.onDevicesChanged = { [weak self] in self?.evaluateBatteryAlerts() }
        hardware.start()
        bluetooth.start()
        engine.configure(preferences)
        engine.start()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                if trusted != self.trusted {
                    if trusted { self.engine.resume(); if self.inputAccess { self.hardware.configureButtons(self.preferences) } }
                    else { self.hardware.stopButtons(); self.engine.suspend() }
                }
                self.trusted = trusted
                let inputAllowed = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
                if inputAllowed != self.inputAccess {
                    self.inputAccess = inputAllowed
                    if inputAllowed && trusted { self.hardware.configureButtons(self.preferences) }
                    else { self.hardware.stopButtons() }
                    self.hardware.refresh()
                }
                self.launchAtLogin = SMAppService.mainApp.status == .enabled
                self.configureTrackpadIfPermissionChanged()
                self.engine.start()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.trackpad.stop(); self?.hardware.stopButtons(); self?.engine.suspend() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.engine.resume(); if let self { self.configureTrackpad(); self.hardware.configureButtons(self.preferences); self.hardware.refresh() } }
    }
    private func evaluateBatteryAlerts() {
        var readings: [BatteryReading] = []
        if let id = device.id, let percent = device.battery {
            readings.append(.init(id: "mouse.\(id)", name: device.name, percent: percent))
        }
        readings += keyboardBatteries.compactMap { keyboard in
            keyboard.percent.map { .init(id: "keyboard.\(keyboard.id)", name: keyboard.name, percent: $0) }
        }
        for accessory in bluetooth.devices {
            readings += accessory.levels.filter { $0.lastKnownAt == nil }.map { level in
                .init(id: "bluetooth.\(accessory.id).\(level.id)",
                      name: accessory.name + (level.label.isEmpty ? "" : " · \(level.label)"), percent: level.percent)
            }
        }
        batteryAlerts.observe(readings)
    }
    private func configureTrackpad() {
        lastTrackpadAllowed = trusted && inputAccess && preferences.enabled
        trackpad.configure(trackpadPreferences,allowed: lastTrackpadAllowed)
    }
    private func configureTrackpadIfPermissionChanged() {
        if lastTrackpadAllowed != (trusted && inputAccess && preferences.enabled) { configureTrackpad() }
    }
    func beginButtonCapture() {
        guard trusted else { message = "Permita Acessibilidade antes de identificar um botão."; return }
        captureHint = nil; capturedButton = nil; capturingButton = true
        if device.buttonCaptureAvailable { hardware.beginButtonCapture() }
        else { engine.beginButtonCapture() }
    }
    func recoverNativeButtons() {
        captureHint = "Verificando o modo dos botões…"
        hardware.recoverNativeButtons { [weak self] result in
            DispatchQueue.main.async { self?.captureHint = result }
        }
    }
    func cancelButtonCapture() {
        capturingButton = false; engine.cancelButtonCapture(); hardware.cancelButtonCapture()
    }
    func assignButton(_ button: Int, action: ButtonAction) {
        var updated = preferences; updated.assign(action, to: button); preferences = updated
    }
    private func save() { if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: "preferences.v1") } }
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacyPane("Privacy_Accessibility")
    }
    func requestInputAccess() {
        hardware.requestAccess()
        openPrivacyPane("Privacy_ListenEvent")
    }
    func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
    private func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"), NSWorkspace.shared.open(url) else {
            message = "Abra Ajustes do Sistema → Privacidade e Segurança. Adicione o Click + pelo botão + e habilite a permissão. Use Localizar aplicativo para encontrar esta versão."
            return
        }
    }
    func login(_ value: Bool) {
        do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; launchAtLogin = value }
        catch { message = error.localizedDescription }
    }
    func shutdown(completion: @escaping (Bool) -> Void) {
        bluetooth.stop()
        trackpad.stop()
        engine.suspend { [hardware] in
            hardware.stopButtons {
                hardware.restoreDPI { success in DispatchQueue.main.async { completion(success) } }
            }
        }
    }
}
