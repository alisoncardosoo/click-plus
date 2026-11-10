import AppKit
import UserNotifications

struct BatteryAlertPreferences: Codable, Equatable {
    var enabled = false
    var low = 20
    var critical = 5
    var sound = true

    var normalized: Self {
        var value = self
        value.low = min(100, max(2, low))
        value.critical = min(value.low - 1, max(1, critical))
        return value
    }
}

struct BatteryReading {
    let id: String
    let name: String
    let percent: Int
}

/// Keeps one warning per threshold until a later reading confirms a recharge.
/// Missing devices and unknown levels never reset the history.
struct BatteryAlertHistory: Codable {
    var sent: [String: Set<Int>] = [:]

    mutating func threshold(for reading: BatteryReading, preferences: BatteryAlertPreferences) -> Int? {
        guard (0...100).contains(reading.percent) else { return nil }
        let preferences = preferences.normalized
        if reading.percent > preferences.low && reading.percent > min(99, preferences.low + 3) {
            sent.removeValue(forKey: reading.id)
            return nil
        }
        guard preferences.enabled else { return nil }
        let threshold = reading.percent <= preferences.critical ? preferences.critical : preferences.low
        guard reading.percent <= threshold, !(sent[reading.id] ?? []).contains(threshold) else { return nil }
        return threshold
    }

    mutating func record(_ reading: BatteryReading, threshold: Int, preferences: BatteryAlertPreferences) {
        sent[reading.id, default: []].insert(threshold)
        // Starting below the critical limit must not send both warnings.
        if threshold == preferences.critical { sent[reading.id, default: []].insert(preferences.low) }
    }
}

@MainActor final class BatteryAlertService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var preferences: BatteryAlertPreferences
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var error: String?
    @Published private(set) var requestingPermission = false
    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()
    private var history: BatteryAlertHistory
    private var readings: [BatteryReading] = []
    private var evaluating = false
    private var needsEvaluation = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = defaults.data(forKey: "batteryAlerts.preferences.v1")
            .flatMap { try? JSONDecoder().decode(BatteryAlertPreferences.self, from: $0) }?.normalized ?? BatteryAlertPreferences()
        history = defaults.data(forKey: "batteryAlerts.history.v1")
            .flatMap { try? JSONDecoder().decode(BatteryAlertHistory.self, from: $0) } ?? BatteryAlertHistory()
        super.init()
    }

    func start() {
        center.delegate = self
        refreshAuthorization()
    }

    func update(_ value: BatteryAlertPreferences) {
        preferences = value.normalized
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "batteryAlerts.preferences.v1") }
        if preferences.enabled { requestPermission() }
        evaluate()
    }

    func requestPermission() {
        guard !requestingPermission else { return }
        requestingPermission = true
        Task {
            defer { requestingPermission = false }
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
                error = nil
            } catch { self.error = "Não foi possível autorizar notificações: \(error.localizedDescription)" }
            await loadAuthorization()
        }
    }

    func refreshAuthorization() { Task { await loadAuthorization() } }

    private func loadAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
        evaluate()
    }

    func observe(_ values: [BatteryReading]) {
        readings = values
        evaluate()
    }

    private func evaluate() {
        needsEvaluation = true
        guard !evaluating else { return }
        evaluating = true
        Task {
            defer { evaluating = false }
            while needsEvaluation {
                needsEvaluation = false
                let configuration = preferences
                for reading in readings {
                    guard configuration == preferences else { break }
                    guard readings.contains(where: { $0.id == reading.id && $0.percent == reading.percent }) else { continue }
                    let threshold = history.threshold(for: reading, preferences: configuration)
                    guard configuration.enabled, authorization == .authorized || authorization == .provisional,
                          let threshold else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = threshold == configuration.critical ? "Bateria crítica" : "Bateria baixa"
                    content.body = "\(reading.name) está com \(reading.percent)% de bateria. Conecte à energia para recarregar."
                    if configuration.sound { content.sound = .default }
                    let request = UNNotificationRequest(identifier: "battery.\(reading.id)", content: content, trigger: nil)
                    do {
                        try await center.add(request)
                        history.record(reading, threshold: threshold, preferences: configuration)
                        error = nil
                    } catch { self.error = "Não foi possível enviar o aviso de bateria: \(error.localizedDescription)" }
                }
                if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: "batteryAlerts.history.v1") }
            }
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
