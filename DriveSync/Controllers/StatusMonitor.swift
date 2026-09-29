import Foundation
import Observation
import Combine

@Observable
final class DriveSyncStatusMonitor {
    private let statusController = DriveSyncStatusController()
    private let serviceController = DriveSyncServiceController()
    private let issueStore = DriveSyncIssueStore()
    private let logController = DriveSyncLogController()
    private let updateController = DriveSyncUpdateController()

    private var timerCancellable: AnyCancellable?
    private var tickCount = 0

    var runtimeStatus = DriveSyncRuntimeStatus(
        lastSuccessfulSync: nil,
        isRunning: false
    )

    var serviceStatus = DriveSyncServiceStatus(
        syncLoaded: false,
        healthLoaded: false
    )

    var currentIssues: [DriveSyncIssue] = []

    var latestLogName: String?
    
    var availableUpdate: DriveSyncUpdate?

    init() {
        refreshAll()

        timerCancellable = Timer.publish(
            every: 1,
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            self?.timerTick()
        }
    }

    func refresh() {
        refreshFastStatus()
    }

    func refreshAll() {
        refreshFastStatus()
        refreshSlowStatus()
    }
    
    @MainActor
    @discardableResult
    func refreshUpdateStatus(force: Bool = false) async -> DriveSyncUpdateCheck {
        let result = await updateController.checkForUpdate(force: force)

        switch result {
        case .available(let update):
            availableUpdate = update

        case .upToDate:
            availableUpdate = nil

        case .failed:
            break
        }

        return result
    }

    private func timerTick() {
        tickCount += 1

        refreshFastStatus()

        if tickCount >= 5 {
            tickCount = 0
            refreshSlowStatus()
        }
    }

    private func refreshFastStatus() {
        runtimeStatus = statusController.runtimeStatus()

        do {
            currentIssues = try issueStore.currentIssues()
        } catch {
            currentIssues = []
        }
    }

    private func refreshSlowStatus() {
        serviceStatus = serviceController.serviceStatus()
        latestLogName = logController.latestLogName()
    }
}
