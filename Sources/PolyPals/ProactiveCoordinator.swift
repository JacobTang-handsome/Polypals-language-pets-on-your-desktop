import Foundation

@MainActor
final class ProactiveCoordinator {
    private let model: AppModel
    private var timer: Timer?
    private var lastResetDay: Date?

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        stop()
        lastResetDay = Calendar.current.startOfDay(for: Date())
        evaluateInvitations()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateInvitations() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func evaluateInvitations(now: Date = Date()) {
        resetDailyCountersIfNeeded(now: now)
        let dueSchedules = model.consumeDueRuntimeSchedules(now: now)
        let quietSchedules = dueSchedules.filter { model.isPetQuiet($0.petID, at: now) }
        quietSchedules.forEach {
            model.recordScheduleExecution($0, outcome: .suppressed, reason: "宠物安静时间", at: now)
        }
        let scheduleCandidates = dueSchedules.filter { !model.isPetQuiet($0.petID, at: now) }
        guard model.pendingInvitations.isEmpty else { return }
        var candidates = scheduleCandidates
        let eligible = PetID.allCases.filter { petID in
            let profile = model.profile(for: petID)
            return ProactiveMode(rawValue: profile.proactiveMode) == .occasionalInvite
                && profile.isVisible && !profile.isSleeping && !model.isPetQuiet(petID, at: now)
        }
        if let petID = eligible.max(by: {
            (model.profile(for: $0).lastInteractionAt ?? .distantPast)
                < (model.profile(for: $1).lastInteractionAt ?? .distantPast)
        }) {
            let definition = PetDefinition.definition(for: petID)
            candidates.append(InvitationCandidate(
                petID: petID,
                priority: .occasional,
                createdAt: now,
                expiresAt: now.addingTimeInterval(15 * 60),
                title: "\(definition.name) 有一个一分钟的小邀请",
                body: invitationBody(for: petID)
            ))
        }
        guard !candidates.isEmpty else { return }

        var snapshot = model.schedulerSnapshot
        snapshot.now = now
        snapshot.todayOnlyPet = model.todayOnlyPet
        switch model.scheduler.decide(candidates: candidates, snapshot: snapshot) {
        case let .deliver(winner):
            model.schedulerSuppressionReason = nil
            model.schedulerSnapshot = snapshot
            model.deliverInvitation(winner)
            candidates.filter { $0.id != winner.id }.forEach { model.recordScheduleExecution($0, outcome: .suppressed, reason: "同一时间已有更高优先级事件") }
        case let .suppress(reason):
            model.schedulerSuppressionReason = reason
            candidates.forEach { model.recordScheduleExecution($0, outcome: .suppressed, reason: reason) }
        }
    }

    private func resetDailyCountersIfNeeded(now: Date) {
        let day = Calendar.current.startOfDay(for: now)
        guard lastResetDay != day else { return }
        lastResetDay = day
        model.resetDailySchedulerState(now: now)
    }

    private func invitationBody(for petID: PetID) -> String {
        switch petID {
        case .sol: "Tengo un juego de un minuto. ¿Vienes?"
        case .mousse: "Une petite pause ? J’ai apporté quelque chose."
        case .ash: "A one-minute detour. Strictly recreational, allegedly."
        }
    }
}
