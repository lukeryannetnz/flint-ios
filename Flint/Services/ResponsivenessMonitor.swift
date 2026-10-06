import Foundation

/// The clock and main-queue delivery can be driven without sleeping in tests.
final class ResponsivenessMonitor {
    enum Observation: Equatable {
        case slow(UUID, DebugLogStep, Double)
        case stall([UUID])
        case recovered(Double)
    }
    private struct Action {
        var step: DebugLogStep
        var elapsed: Double = 0
        var reported = false
    }
    private let lock = NSLock()
    private let clock: () -> Double
    private let emit: (Observation) -> Void
    private var actions: [UUID: Action] = [:]
    private var active = false
    private var lastTick: Double
    private var heartbeat: (id: UUID, start: Double)?
    private var stalled = false

    init(clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         emit: @escaping (Observation) -> Void) {
        self.clock = clock; self.emit = emit; lastTick = clock()
    }

    func setActive(_ value: Bool) {
        lock.lock()
        advance(to: clock())
        active = value; heartbeat = nil; stalled = false
        lock.unlock()
    }
    func begin(_ id: UUID, step: DebugLogStep) {
        lock.lock(); advance(to: clock()); actions[id] = Action(step: step); lock.unlock()
    }
    func end(_ id: UUID, parent: UUID? = nil) {
        lock.lock(); advance(to: clock())
        if let parent, let action = actions[id] { actions[parent]?.step = action.step }
        actions.removeValue(forKey: id); lock.unlock()
    }

    /// Returns a token only when no heartbeat is outstanding. No main-actor reads occur here.
    func tick() -> UUID? {
        var observations: [Observation] = []
        lock.lock()
        let now = clock(); advance(to: now)
        guard active else { lock.unlock(); return nil }
        for (id, var action) in actions where !action.reported && action.elapsed >= 5 {
            action.reported = true; actions[id] = action
            observations.append(.slow(id, action.step, action.elapsed))
        }
        if let heartbeat, now - heartbeat.start >= 2, !stalled {
            stalled = true; observations.append(.stall(Array(actions.keys).sorted { $0.uuidString < $1.uuidString }))
        }
        var token: UUID?
        if heartbeat == nil {
            token = UUID(); heartbeat = (token!, now)
        }
        lock.unlock()
        observations.forEach(emit)
        return token
    }

    func acknowledge(_ token: UUID) {
        lock.lock()
        guard active, let heartbeat, heartbeat.id == token else { lock.unlock(); return }
        let duration = max(0, clock() - heartbeat.start)
        let recovered = stalled
        self.heartbeat = nil; stalled = false
        lock.unlock()
        if recovered { emit(.recovered(duration)) }
    }

    private func advance(to now: Double) {
        let elapsed = active ? max(0, now - lastTick) : 0
        for id in actions.keys { actions[id]?.elapsed += elapsed }
        lastTick = now
    }
}

/// Separate sampling queue, separate writer. Main queue work is limited to one outstanding acknowledgment.
enum RuntimeMonitoring {
    static let monitor = ResponsivenessMonitor { DebugLog.shared.monitorObservation($0) }
    private static var timer: DispatchSourceTimer?
    static func start() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "flint.responsiveness", qos: .utility))
        source.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(50))
        source.setEventHandler {
            if let token = monitor.tick() { DispatchQueue.main.async { monitor.acknowledge(token) } }
        }
        timer = source; source.resume()
    }
}
