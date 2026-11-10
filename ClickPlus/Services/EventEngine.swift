import Foundation
import ApplicationServices
import AppKit
import OSLog

final class EventEngine {
    var onStatus: ((String) -> Void)?
    var onButtonCaptured: ((Int) -> Void)?
    var onCaptureEnded: ((String?) -> Void)?
    var onDiagnostics: ((InputDiagnostics) -> Void)?
    private let captureLog = Logger(subsystem: "br.com.clickplus", category: "ButtonCapture")
    private var capture = ButtonCapture()
    private var captureTimer: Timer?
    private var diagnostics = InputDiagnostics()
    private var lastDiagnosticReport = 0.0
    private let sourceResolver: ((CGEvent) -> DeviceIdentity.Source)?
    private let pointerPreparation: ((UInt64) -> Bool)?
    private let eventSink: (CGEvent) -> Void
    private let actionSink: (ButtonAction) -> Void
    var onFrequency: ((Int) -> Void)?
    private let lock = NSLock()
    private var pendingDevice = HardwareState()
    private var pending = Preferences()
    private var prefs = Preferences()
    private var tap: CFMachPort?
    private var loop: CFRunLoop?
    private var starting = false
    private var sleeping = false
    private var thread: Thread?
    private let identity = DeviceIdentity()
    private let pointer = PointerController()
    private let accessibility = AccessibilityService()
    private var timer: Timer?
    private var impulses: [(x: Double, y: Double, weights: [Double], index: Int, flags: CGEventFlags)] = []
    private var residualX = 0.0, residualY = 0.0
    private var pressed: [Int: ButtonAction] = [:]
    private var suppressedReleases: Set<Int> = []
    private var panDown: CGEvent?
    private var panActive = false
    private var hardwarePan = false
    private var panDistance = 0.0
    private var panLast = CGPoint.zero
    private var panVelocity = CGPoint.zero
    private var panFlags: CGEventFlags = []
    private var rateStart = ProcessInfo.processInfo.systemUptime
    private var count = 0
    init(preferences: Preferences = Preferences(), sourceResolver: ((CGEvent) -> DeviceIdentity.Source)? = nil,
         pointerPreparation: ((UInt64) -> Bool)? = nil,
         eventSink: @escaping (CGEvent) -> Void = ActionService.post,
         actionSink: @escaping (ButtonAction) -> Void = ActionService.perform) {
        self.prefs = preferences; self.pending = preferences
        self.sourceResolver = sourceResolver; self.pointerPreparation = pointerPreparation
        self.eventSink = eventSink; self.actionSink = actionSink
    }
    func beginButtonCapture() {
        lock.lock(); let runLoop = loop; lock.unlock()
        guard let runLoop else { onCaptureEnded?("A captura ainda não está pronta. Confira a Acessibilidade e tente novamente."); return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in
            guard let self else { return }
            self.cancel(); self.capture.begin()
            self.captureLog.notice("Capture started")
            let timer = Timer(timeInterval: 60, repeats: false) { [weak self] _ in self?.endCapture("Nenhum botão detectado. Clique em Adicionar botão para tentar novamente.") }
            self.captureTimer = timer; RunLoop.current.add(timer, forMode: .common)
        }
        CFRunLoopWakeUp(runLoop)
    }
    func cancelButtonCapture() {
        lock.lock(); let runLoop = loop; lock.unlock()
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in self?.endCapture(nil) }
        CFRunLoopWakeUp(runLoop)
    }
    private func endCapture(_ reason: String?) {
        let wasWaiting = capture.waiting
        capture.cancel(); captureTimer?.invalidate(); captureTimer = nil
        if wasWaiting { captureLog.notice("Capture ended: \(reason ?? "cancelled", privacy: .public)"); onCaptureEnded?(reason) }
    }
    private func reportDiagnostics(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now-lastDiagnosticReport >= 0.5 else { return }
        lastDiagnosticReport = now; onDiagnostics?(diagnostics)
    }
    private func perform(_ action: ButtonAction) {
        actionSink(action); diagnostics.mappedActions += 1
        diagnostics.lastAction = action.kind.displayName; reportDiagnostics(force: true)
    }
    func hardwarePanState(_ button: Int, down: Bool) {
        lock.lock(); let runLoop = loop; lock.unlock()
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in
            guard let point = CGEvent(source: nil)?.location else { return }
            self?.handleHardwarePan(button, down: down, at: point)
        }
        CFRunLoopWakeUp(runLoop)
    }
    func cancelHardwarePan() {
        lock.lock(); let runLoop = loop; lock.unlock()
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in
            if self?.hardwarePan == true { self?.cancel() }
        }
        CFRunLoopWakeUp(runLoop)
    }
    func handleHardwarePan(_ button: Int, down: Bool, at point: CGPoint) {
        guard prefs.enabled, !sleeping, button == prefs.panButton, button >= 2 else { return }
        if down {
            guard let initial = CGEvent(mouseEventSource: nil,mouseType: .otherMouseDown,mouseCursorPosition: point,mouseButton: CGMouseButton(rawValue: UInt32(button))!) else { return }
            initial.setIntegerValueField(.mouseEventButtonNumber,value: Int64(button))
            timer?.invalidate(); timer = nil; impulses.removeAll(); residualX = 0; residualY = 0
            panDown = initial; panActive = false; panDistance = 0; panVelocity = .zero; hardwarePan = true
        } else if hardwarePan {
            finishPan(button)
        }
    }
    private func finishPan(_ button: Int) {
        guard let initial = panDown else { return }
        if !panActive {
            if prefs.captures(button), let action = prefs.buttons[button], action.kind != .original { perform(action) }
            else { replayClick(initial) }
        } else if prefs.panMomentum { enqueue(x: panVelocity.x*5,y: panVelocity.y*5,flags: panFlags) }
        panDown = nil; panActive = false; hardwarePan = false
    }
    func hardwareButtonReleased(_ button: Int) {
        lock.lock(); let runLoop = loop; lock.unlock()
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in
            self?.handleHardwareRelease(button)
        }
        CFRunLoopWakeUp(runLoop)
    }
    func handleHardwareRelease(_ button: Int) {
        guard !sleeping, let action = prefs.hardwareAction(button) else { return }
        diagnostics.lastSource = "Mouse Logitech • botão HID++ identificado"
        let destination = action.kind == .application ? URL(fileURLWithPath: action.applicationPath).deletingPathExtension().lastPathComponent : action.kind.displayName
        diagnostics.lastButtonAction = "\(DetectedButton.name(button)) → \(destination)"
        captureLog.notice("HID button=\(button) action=\(destination,privacy: .public)")
        perform(action)
    }
    func configure(_ value: Preferences) {
        lock.lock(); pending = value; let runLoop = loop; lock.unlock()
        if let runLoop { CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in self?.update() }; CFRunLoopWakeUp(runLoop) }
    }
    func devicesChanged() {
        lock.lock(); let runLoop = loop; lock.unlock()
        if let runLoop { CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in
            self?.cancel(); self?.identity.receiverUSBID = nil; self?.identity.selectedMouseID = nil; self?.identity.reset()
        }; CFRunLoopWakeUp(runLoop) }
    }
    func setDevice(_ state: HardwareState) {
        lock.lock(); pendingDevice = state; let runLoop = loop; lock.unlock()
        if let runLoop { CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in self?.applyDevice(state) }; CFRunLoopWakeUp(runLoop) }
    }
    private func applyDevice(_ state: HardwareState) {
        if identity.selectedMouseID != state.mouseDeviceID || identity.receiverUSBID != state.receiverUSBID { cancel() }
        identity.receiverUSBID = state.receiverUSBID
        identity.selectedMouseID = state.mouseDeviceID
    }
    func start() {
        lock.lock()
        guard !starting, tap == nil, AXIsProcessTrusted() else { lock.unlock(); return }
        starting = true; lock.unlock()
        thread = Thread { [weak self] in self?.run() }; thread?.name = "ClickPlus.Events"; thread?.start()
    }
    private func run() {
        let types: [CGEventType] = [.scrollWheel,.mouseMoved,.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,.otherMouseDown,.otherMouseUp,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<EventEngine>.fromOpaque(context).takeUnretainedValue().handle(type, event)
        }
        guard identity.available, let created = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            lock.lock(); starting = false; lock.unlock()
            onStatus?(identity.available ? "A captura requer permissão de Acessibilidade" : "Identificação do dispositivo indisponível neste macOS")
            return
        }
        lock.lock(); tap = created; loop = CFRunLoopGetCurrent(); starting = false; lock.unlock()
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        update(); CGEvent.tapEnable(tap: created, enable: true); CFRunLoopRun()
    }
    private func update() {
        lock.lock(); prefs = pending; let device = pendingDevice; lock.unlock()
        cancel(); applyDevice(device); identity.reset()
        onStatus?(prefs.enabled ? "Ativo • somente eventos identificados do mouse Logitech" : "Pausado • mouse no comportamento original")
    }
    func suspend(completion: @escaping () -> Void = {}) {
        lock.lock(); let runLoop = loop; lock.unlock()
        if let runLoop { CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in self?.sleeping = true; self?.cancel(); completion() }; CFRunLoopWakeUp(runLoop) } else { completion() }
    }
    func resume() {
        lock.lock(); let runLoop = loop; lock.unlock()
        if let runLoop { CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in self?.sleeping = false; self?.identity.reset() }; CFRunLoopWakeUp(runLoop) }
    }
    private func cancel() {
        endCapture(nil)
        pointer.restore()
        timer?.invalidate(); timer = nil; impulses.removeAll(); residualX = 0; residualY = 0
        // A consumed press must not leak an unmatched release when settings change.
        if let down = panDown { suppressedReleases.insert(Int(down.getIntegerValueField(.mouseEventButtonNumber))) }
        suppressedReleases.formUnion(pressed.keys)
        panDown = nil; panActive = false; hardwarePan = false; panDistance = 0; pressed.removeAll()
    }
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { cancel(); if let tap { CGEvent.tapEnable(tap: tap, enable: true) }; return pass }
        guard event.getIntegerValueField(.eventSourceUserData) != ActionService.marker else { return pass }
        let source = sourceResolver?(event) ?? identity.source(event)
        if capture.waiting, [.otherMouseDown, .otherMouseUp].contains(type) {
            captureLog.notice("Capture event type=\(type.rawValue) button=\(event.getIntegerValueField(.mouseEventButtonNumber)) target=\(source == .mouse) source=\(String(describing: source),privacy: .public) sender=\(self.identity.senderID(event)) pid=\(event.getIntegerValueField(.eventSourceUnixProcessID))")
        }
        if source == .trackpad, [.mouseMoved,.leftMouseDragged,.scrollWheel].contains(type), TrackpadEdgeService.shared.suppressesMotion() { return nil }
        if source == .trackpad { diagnostics.trackpadPassed += 1; diagnostics.lastSource = "Trackpad • evento preservado"; reportDiagnostics() }
        guard source == .mouse else { return pass }
        diagnostics.mouseEvents += 1; diagnostics.lastSource = "Mouse Logitech • evento identificado"
        defer { reportDiagnostics() }
        switch capture.process(type: type, button: Int(event.getIntegerValueField(.mouseEventButtonNumber)), isTarget: true) {
        case .consume: return nil
        case .detected(let button):
            captureTimer?.invalidate(); captureTimer = nil; captureLog.notice("Detected button \(button)"); onButtonCaptured?(button); return nil
        case .pass: break
        }
        let pendingButton = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        if [.leftMouseUp,.rightMouseUp,.otherMouseUp].contains(type), suppressedReleases.remove(pendingButton) != nil { return nil }
        if [.leftMouseDragged,.rightMouseDragged,.otherMouseDragged].contains(type), suppressedReleases.contains(pendingButton) { return nil }
        if [.leftMouseDown,.rightMouseDown,.otherMouseDown].contains(type) { suppressedReleases.remove(pendingButton) }
        guard prefs.enabled, !sleeping else { return pass }
        let now = ProcessInfo.processInfo.systemUptime
        count += 1
        if now - rateStart >= 1 { onFrequency?(Int(Double(count)/(now-rateStart))); count = 0; rateStart = now }
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let down = [.leftMouseDown,.rightMouseDown,.otherMouseDown].contains(type)
        let up = [.leftMouseUp,.rightMouseUp,.otherMouseUp].contains(type)
        let dragged = [.leftMouseDragged,.rightMouseDragged,.otherMouseDragged].contains(type)
        if down {
            timer?.invalidate(); timer = nil; impulses.removeAll(); residualX = 0; residualY = 0
            if (button == 0 && prefs.leftClickThrough) || (button == 1 && prefs.rightClickThrough) { accessibility.raise(at: event.location) }
            if button == prefs.panButton {
                hardwarePan = false
                panDown = event.copy(); panActive = false; panDistance = 0; panLast = event.location; panVelocity = .zero
                return nil
            }
            let allowed = prefs.captures(button)
            if allowed, let action = prefs.buttons[button], action.kind != .original { pressed[button] = action; return nil }
        }
        if dragged, pressed[button] != nil { return nil }
        if up, let action = pressed.removeValue(forKey: button) { perform(action); return nil }
        if ((dragged && button == prefs.panButton) || (hardwarePan && type == .mouseMoved)), let initial = panDown {
            let dx = event.getDoubleValueField(.mouseEventDeltaX), dy = event.getDoubleValueField(.mouseEventDeltaY)
            panDistance += hypot(dx,dy)
            if !panActive && panDistance >= 4 {
                panActive = true
                if prefs.panClickThrough { accessibility.raise(at: initial.location) }
            }
            if panActive {
                let sign = prefs.panInvert ? 1.0 : -1.0
                panVelocity = CGPoint(x: dx*sign, y: dy*sign); panFlags = event.flags
                scroll(x: panVelocity.x, y: panVelocity.y, event: event, isPan: true)
                if prefs.holdCursor { CGWarpMouseCursorPosition(initial.location) }
                else if let movement = event.copy() { movement.type = .mouseMoved; eventSink(movement) }
            }
            return nil
        }
        if up, panDown != nil, button == prefs.panButton {
            finishPan(button); return nil
        }
        if type == .scrollWheel, prefs.scrollEnabled {
            let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            let y = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) : event.getDoubleValueField(.scrollWheelEventDeltaAxis1)*10
            let x = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) : event.getDoubleValueField(.scrollWheelEventDeltaAxis2)*10
            diagnostics.scrollTransforms += 1
            scroll(x: x, y: y, event: event, isPan: false); return nil
        }
        if (type == .mouseMoved || dragged), prefs.cursorEnabled {
            guard pointerPreparation?(identity.senderID(event)) ?? pointer.prepare(senderID: identity.senderID(event)) else {
                diagnostics.pointerStatus = "Falha ao isolar a aceleração"
                onStatus?("Controle do cursor indisponível: não foi possível isolar a aceleração do mouse")
                return pass
            }
            diagnostics.cursorTransforms += 1; diagnostics.pointerStatus = "Aceleração isolada no serviço do mouse"
            let dx = event.getDoubleValueField(.mouseEventDeltaX), dy = event.getDoubleValueField(.mouseEventDeltaY)
            // System acceleration is disabled only for this service; zero is linear.
            var gain = prefs.cursorSpeed * (1 + prefs.cursorAcceleration * min(hypot(dx,dy),50)/50)
            if prefs.precisionModifier.matches(event.flags) { gain *= prefs.precisionGain }
            let point = event.location
            event.location = CGPoint(x: point.x + dx*(gain-1), y: point.y + dy*(gain-1))
            event.setDoubleValueField(.mouseEventDeltaX, value: dx*gain); event.setDoubleValueField(.mouseEventDeltaY, value: dy*gain)
        }
        return pass
    }
    private func replayClick(_ initial: CGEvent) {
        let button = initial.getIntegerValueField(.mouseEventButtonNumber)
        eventSink(initial)
        if let release = initial.copy() { release.type = button == 0 ? .leftMouseUp : button == 1 ? .rightMouseUp : .otherMouseUp; eventSink(release) }
    }
    private func scroll(x: Double, y: Double, event: CGEvent, isPan: Bool) {
        var x = x, y = y, flags = event.flags
        if prefs.horizontalModifier.matches(flags) { x += y * (prefs.invertModifiedHorizontal ? -1 : 1); y = 0; flags.remove(prefs.horizontalModifier.flag) }
        if prefs.zoomModifier.matches(flags) {
            let delta = (y == 0 ? x : y) * (prefs.invertZoom ? -1 : 1)
            if isPan { panVelocity = .zero }
            guard delta != 0 else { return }
            actionSink(ButtonAction(kind: .shortcut, keyCode: delta > 0 ? 24 : 27, flags: CGEventFlags.maskCommand.rawValue)); return
        }
        var gain = 1.0
        if prefs.speedModifier.matches(flags) { gain = prefs.modifierGain; flags.remove(prefs.speedModifier.flag) }
        x = ScrollMath.distance(x, speed: prefs.horizontalSpeed, acceleration: prefs.scrollAcceleration) * gain * (prefs.invertHorizontal ? -1 : 1)
        y = ScrollMath.distance(y, speed: prefs.scrollSpeed, acceleration: prefs.scrollAcceleration) * gain * (prefs.invertVertical ? -1 : 1)
        if isPan { panVelocity = CGPoint(x: x,y: y); panFlags = flags }
        if (prefs.verticalSliders && y != 0) || (prefs.horizontalSliders && x != 0) {
            if accessibility.adjustSlider(at: event.location, delta: prefs.verticalSliders && y != 0 ? y : x) { if isPan { panVelocity = .zero }; return }
        }
        if prefs.raiseOnScroll { accessibility.raise(at: event.location) }
        if prefs.smooth && !isPan { enqueue(x: x, y: y, flags: flags) } else { emit(x: x, y: y, flags: flags) }
    }
    private func enqueue(x: Double, y: Double, flags: CGEventFlags) {
        if let last = impulses.last, last.x*x < 0 || last.y*y < 0 { impulses.removeAll(); residualX = 0; residualY = 0 }
        impulses.append((x,y,ScrollMath.weights(duration: prefs.duration, brake: prefs.brake, extra: prefs.extraSmooth),0,flags))
        if timer == nil {
            let created = Timer(timeInterval: 1/120, repeats: true) { [weak self] _ in self?.tick() }
            timer = created; RunLoop.current.add(created, forMode: .common)
        }
    }
    private func tick() {
        guard prefs.enabled, !sleeping, AXIsProcessTrusted() else { cancel(); return }
        var x = 0.0, y = 0.0
        let flags = impulses.last?.flags ?? []
        for i in impulses.indices { let w = impulses[i].weights[impulses[i].index]; x += impulses[i].x*w; y += impulses[i].y*w; impulses[i].index += 1 }
        impulses.removeAll { $0.index == $0.weights.count }
        emit(x: x, y: y, flags: flags)
        if impulses.isEmpty { timer?.invalidate(); timer = nil }
    }
    private func emit(x: Double, y: Double, flags: CGEventFlags) {
        residualX += x; residualY += y
        let ix = Int32(residualX.rounded(.towardZero)), iy = Int32(residualY.rounded(.towardZero))
        residualX -= Double(ix); residualY -= Double(iy)
        guard ix != 0 || iy != 0, let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: iy, wheel2: ix, wheel3: 0) else { return }
        event.flags = flags; eventSink(event)
    }
}
